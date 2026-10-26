import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('Cindel getAll transactions', () {
    late String directory;
    late CindelDatabase database;

    Future<CindelDatabase> open() => openTestDatabase(
      directory: directory,
      schemas: [ApiProductSchema, ImmutableUserSchema, UserSchema],
    );

    setUp(() async {
      directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await open();
      addTearDown(() => database.close());
    });

    // Scenario: A batch alternates empty, null and growing dynamic fields.
    // Covers:
    // - Reused row layouts, input order, missing IDs and mutable duplicates.
    // - The same generated API inside and outside a read transaction.
    // Expected: Offsets never leak between rows and duplicate objects are independent.
    test('keeps variable payloads independent across batch rows.', () async {
      // Arrange.
      final products = [
        for (var i = 1; i <= 256; i++)
          _product(i, i.isEven ? '' : 'é漢🙂' * (i % 17))
            ..id = i % 3 == 0 ? null : 'key-$i',
      ];
      await database.apiProducts.putAll(products);
      final ids = [256, 999, ...List.generate(256, (i) => 256 - i), 1];
      Future<void> verify() async {
        // Act.
        final rows = await database.apiProducts.getAll(ids);
        // Assert.
        expect(rows.length, ids.length);
        for (var i = 0; i < ids.length; i++) {
          if (ids[i] == 999) {
            expect(rows[i], isNull);
          } else {
            final expected = products[ids[i] - 1];
            expect(rows[i]!.dbId, expected.dbId);
            expect(rows[i]!.name, expected.name);
            expect(rows[i]!.id, expected.id);
          }
        }
        expect(identical(rows[0], rows[2]), isFalse);
        rows[0]!.name = 'changed only in memory';
        expect(rows[2]!.name, products.last.name);
        expect((await database.apiProducts.get(256))!.name, products.last.name);
      }

      await verify();
      await database.readTxn(verify);
    });

    // Scenario: Large duplicate payloads straddle the SQLite parameter boundary.
    // Covers:
    // - Web response assembly without per-position Rust document copies.
    // - Null positions, chunk order, independent objects and transaction parity.
    // Expected: All backends return identical values without sharing mutable models.
    test('preserves duplicate payloads across response chunks.', () async {
      // Arrange.
      final large = 'é漢🙂' * 8192;
      await database.apiProducts.putAll([_product(1, large), _product(2, '')]);
      final ids = List<int>.filled(32768, 999);
      ids[0] = 1;
      ids[1] = 2;
      ids[32766] = 1;
      Future<void> verify() async {
        // Act.
        final rows = await database.apiProducts.getAll(ids);
        // Assert.
        expect(rows.length, ids.length);
        expect(rows[0]!.name, large);
        expect(rows[1]!.name, '');
        expect(rows[32766]!.name, large);
        expect(rows.where((row) => row == null).length, ids.length - 3);
        expect(identical(rows[0], rows[32766]), isFalse);
        rows[0]!.name = 'local mutation';
        expect(rows[32766]!.name, large);
        expect((await database.apiProducts.get(1))!.name, large);
      }

      await verify();
      await database.readTxn(verify);
      await database.writeTxn(verify);
    });

    // Scenario: Repeated reads vary their IDs and batch lengths around updates.
    // Covers:
    // - Prepared-read reuse, eviction, independent overlapping calls and reopen.
    // - Fresh values after commits and restoration of values after rollback.
    // Expected: All three backends preserve order, nulls and transaction visibility.
    test(
      'reuses read preparation without retaining parameters or results.',
      () async {
        // Arrange.
        await database.apiProducts.putAll([
          _product(1, 'first'),
          _product(2, 'second'),
        ]);
        // Act / Assert.
        for (var size = 1; size <= 20; size++) {
          final ids = List.generate(size, (i) => [2, 99, 1][i % 3]);
          expect(_names(await database.apiProducts.getAll(ids)), [
            for (final id in ids)
              id == 99 ? null : (id == 1 ? 'first' : 'second'),
          ]);
        }
        await database.apiProducts.put(_product(1, 'updated'));
        expect((await database.apiProducts.get(1))!.name, 'updated');
        await database.readTxn(() async {
          final batches = await Future.wait([
            database.apiProducts.getAll([1, 2, 99]),
            database.apiProducts.getAll([2, 99, 1]),
          ]);
          expect(_names(batches[0]), ['updated', 'second', null]);
          expect(_names(batches[1]), ['second', null, 'updated']);
          expect(identical(batches[0][0], batches[1][2]), isFalse);
        });
        final failure = StateError('rollback prepared reads');
        await expectLater(
          database.writeTxn(() async {
            await database.apiProducts.put(_product(1, 'pending'));
            await database.apiProducts.delete(2);
            expect(_names(await database.apiProducts.getAll([1, 2, 1])), [
              'pending',
              null,
              'pending',
            ]);
            throw failure;
          }),
          throwsA(same(failure)),
        );
        expect(_names(await database.apiProducts.getAll([1, 2])), [
          'updated',
          'second',
        ]);
        await database.close();
        database = await open();
        expect(_names(await database.apiProducts.getAll([2, 1, 99])), [
          'second',
          'updated',
          null,
        ]);
      },
    );

    for (final rollback in [false, true]) {
      // Scenario: Bulk reads are interleaved with writes in an explicit txn.
      // Covers: Input order, duplicates, missing/deleted rows, latest staged
      // values, committed rows, empty input, and persistence after commit/rollback.
      // Expected: All three backends expose the same read-your-writes behavior.
      test(
        'reads pending changes before ${rollback ? 'rollback' : 'commit'}.',
        () async {
          // Arrange.
          await database.apiProducts.putAll([
            _product(10, 'Original'),
            _product(20, 'Delete me'),
            _product(30, 'Unchanged'),
          ]);
          final inserted = ApiProduct()..name = 'Inserted';
          final failure = StateError('Roll back after reading');

          Future<void> writeAndRead() => database.writeTxn(() async {
            expect(await database.apiProducts.getAll([]), isEmpty);
            expect(
              _names(await database.apiProducts.getAll([30, 999, 10, 30])),
              ['Unchanged', null, 'Original', 'Unchanged'],
            );
            await database.apiProducts.putAll([
              _product(10, 'Updated'),
              inserted,
            ]);
            await database.apiProducts.deleteAll([20, 999]);
            final ids = [inserted.dbId, 20, 10, 30, 999, inserted.dbId, 10];
            final rows = await database.apiProducts.getAll(ids);
            expect(rows.map((row) => row?.dbId), [
              inserted.dbId,
              null,
              10,
              30,
              null,
              inserted.dbId,
              10,
            ]);
            expect(_names(rows), [
              'Inserted',
              null,
              'Updated',
              'Unchanged',
              null,
              'Inserted',
              'Updated',
            ]);
            await database.apiProducts.put(_product(20, 'Reinserted'));
            await database.apiProducts.delete(10);
            expect(_names(await database.apiProducts.getAll([10, 20])), [
              null,
              'Reinserted',
            ]);
            await database.apiProducts.put(_product(10, 'Latest'));
            expect(_names(await database.apiProducts.getAll([10, 20, 10])), [
              'Latest',
              'Reinserted',
              'Latest',
            ]);
            // A previous result is detached from subsequent writes.
            expect(rows[2]!.name, 'Updated');
            if (rollback) {
              throw failure;
            }
          });

          // Act / Assert.
          if (rollback) {
            await expectLater(writeAndRead(), throwsA(same(failure)));
          } else {
            await writeAndRead();
          }
          final expected = rollback
              ? ['Original', 'Delete me', 'Unchanged', null]
              : ['Latest', 'Reinserted', 'Unchanged', 'Inserted'];
          final ids = [10, 20, 30, inserted.dbId];
          expect(_names(await database.apiProducts.getAll(ids)), expected);
          await database.close();
          database = await open();
          await database.readTxn(() async {
            expect(_names(await database.apiProducts.getAll(ids)), expected);
          });
        },
      );
    }

    // Scenario: Immutable IDs must survive the transaction-aware reader.
    // Covers: Existing and new final IDs, updates, duplicate and missing rows.
    // Expected: Reading a staged object never substitutes the autoIncrement sentinel.
    test('preserves immutable IDs inside writeTxn.', () async {
      // Arrange.
      await database.immutableUsers.put(
        const ImmutableUser(
          dbId: 1,
          email: 'before@example.com',
          active: false,
        ),
      );
      // Act / Assert.
      await database.writeTxn(() async {
        final id = await database.allocateId('immutableUsers');
        await database.immutableUsers.putAll([
          const ImmutableUser(
            dbId: 1,
            email: 'after@example.com',
            active: true,
          ),
          ImmutableUser(dbId: id, email: 'new@example.com', active: false),
        ]);
        final rows = await database.immutableUsers.getAll([id, 1, 999, id]);
        expect(rows.map((row) => row?.dbId), [id, 1, null, id]);
        expect(rows.map((row) => row?.email), [
          'new@example.com',
          'after@example.com',
          null,
          'new@example.com',
        ]);
        expect(rows[1]!.active, isTrue);
      });
    });

    // Scenario: Staged bulk reads use all generated typed field readers.
    // Covers: Null/empty/populated lists, embedded data, enums and temporal values.
    // Expected: Both transaction reads and post-commit reads preserve the model.
    test('preserves generated field types inside writeTxn.', () async {
      // Arrange.
      final recipient = Recipient()
        ..name = 'Ada'
        ..address = 'ada@example.com'
        ..metadata = (RecipientMetadata()..label = 'Primary');
      final users = [
        User()
          ..name = 'Nulls'
          ..email = 'nulls@example.com',
        User()
          ..name = 'Empty'
          ..email = 'empty@example.com'
          ..scores = []
          ..recipients = [],
        User()
          ..name = 'Values'
          ..email = 'values@example.com'
          ..active = true
          ..tags = ['one', 'two']
          ..scores = [0, -42, 9007199254740991]
          ..createdAt = DateTime.utc(2026, 10, 24, 12)
          ..sessionLength = const Duration(microseconds: 1234567)
          ..role = UserRole.owner
          ..status = UserStatus.active
          ..plan = UserPlan.pro
          ..primaryRecipient = recipient
          ..recipients = [recipient],
      ];
      Future<void> verify() async {
        final rows = await database.users.getAll(
          users.map((user) => user.dbId),
        );
        expect(rows.map((row) => row?.dbId), users.map((user) => user.dbId));
        expect(
          rows.map((row) => UserSchema.toDocument(row!)),
          users.map(UserSchema.toDocument),
        );
      }

      // Act / Assert.
      await database.writeTxn(() async {
        await database.users.putAll(users);
        await verify();
      });
      await verify();
    });
  });
}

ApiProduct _product(int id, String name) => ApiProduct()
  ..dbId = id
  ..name = name;

List<String?> _names(List<ApiProduct?> rows) =>
    rows.map((row) => row?.name).toList();
