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
