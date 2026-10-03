import 'dart:async';
import 'dart:typed_data';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

void main({bool includeSameDirectoryHandles = true}) {
  group('database close', () {
    // Scenario: the same handle is closed again after teardown has finished.
    // Covers:
    // - Sequential idempotence and the cached close future.
    // - Closed-handle rejection and persistence through a distinct handle.
    // Expected: later closes share the successful future and stored data remains.
    test('shares completion with repeated sequential closes.', () async {
      // Arrange.
      final fixture = await _openSeededDatabase();
      final database = fixture.database;

      // Act.
      final first = database.close();
      await first;
      final second = database.close();
      final third = database.close();
      await Future.wait([second, third]);

      // Assert.
      expect(second, same(first));
      expect(third, same(first));
      await _expectClosed(database);
      await _expectStoredProducts(fixture.directory, const {1: 'original'});
    });

    for (final count in [2, 16]) {
      // Scenario: all close calls start before any caller awaits completion.
      // Covers:
      // - Concurrent close callers sharing a single teardown and future.
      // - Successful completion and persisted data after reopening.
      // Expected: every caller has the same successful future and the handle closes.
      test('shares completion between $count concurrent closes.', () async {
        // Arrange.
        final fixture = await _openSeededDatabase();
        final database = fixture.database;

        // Act.
        final closes = [
          for (var index = 0; index < count; index++) database.close(),
        ];
        await Future.wait(closes);

        // Assert.
        for (final close in closes) {
          expect(close, same(closes.first));
        }
        await _expectClosed(database);
        await _expectStoredProducts(fixture.directory, const {1: 'original'});
      });
    }

    for (final paused in [false, true]) {
      // Scenario: a typed collection watcher is active when close starts.
      // Covers:
      // - Stream completion without watcher errors.
      // - Shared teardown while a paused listener delays stream completion.
      // - Reads failing after detachment, before the paused listener resumes.
      // Expected: paused closes remain pending, then finish together on resume.
      test('closes ${paused ? 'paused' : 'active'} watcher streams.', () async {
        // Arrange.
        final fixture = await _openSeededDatabase();
        final database = fixture.database;
        final initial = Completer<void>();
        final done = Completer<void>();
        final errors = <Object>[];
        final snapshots = <List<ApiProduct>>[];
        final subscription = database.apiProducts
            .watchCollection(pollInterval: const Duration(milliseconds: 5))
            .listen(
              (users) {
                snapshots.add(users);
                if (!initial.isCompleted) initial.complete();
              },
              onError: (Object error, StackTrace _) {
                errors.add(error);
                if (!initial.isCompleted) initial.complete();
              },
              onDone: done.complete,
            );
        addTearDown(subscription.cancel);
        await initial.future.timeout(_gateTimeout);
        if (paused) subscription.pause();

        // Act. Attach observers before yielding, so unexpected failures are handled.
        final firstFuture = database.close();
        final first = _Observed(firstFuture);
        await _eventLoopTurn();
        final secondFuture = database.close();
        final second = _Observed(secondFuture);
        final firstPending = !first.finished;
        final secondPending = !second.finished;
        _Observed<ApiProduct?>? readWhilePaused;
        if (paused) {
          readWhilePaused = _Observed(database.apiProducts.get(1));
          await readWhilePaused.done;
          // Release before assertions so a failure cannot strand a paused stream.
          subscription.resume();
        }
        await Future.wait([first.done, second.done]);
        await done.future.timeout(_gateTimeout);

        // Assert.
        expect(errors, isEmpty);
        expect(snapshots.first.single.name, 'original');
        expect(first.error, isNull);
        expect(second.error, isNull);
        expect(secondFuture, same(firstFuture));
        if (paused) {
          expect(firstPending, isTrue);
          expect(secondPending, isTrue);
          expect(readWhilePaused!.error, isA<CindelDatabaseClosedError>());
        }
        await _expectClosed(database);
        await _expectStoredProducts(fixture.directory, const {1: 'original'});
      });
    }

    for (final write in [false, true]) {
      for (final throws in [false, true]) {
        // Scenario: a transaction callback resumes only after another task closes.
        // Covers:
        // - Read/write callbacks suspended across rollback and storage teardown.
        // - Original callback exception identity after cancellation.
        // - Pending writes remaining absent when a new handle reopens the data.
        // Expected: returning callbacks report closed; throwing callbacks keep
        // their original exception, and no canceled write is committed.
        test(
          'cancels suspended ${write ? 'write' : 'read'} transactions '
          '${throws ? 'without replacing callback errors' : 'before commit'}.',
          () async {
            // Arrange.
            final fixture = await _openSeededDatabase();
            final database = fixture.database;
            final entered = Completer<void>();
            final release = Completer<void>();
            final callbackError = StateError('controlled callback error');
            addTearDown(() {
              if (!release.isCompleted) release.complete();
            });
            Future<String> callback() async {
              expect((await database.apiProducts.get(1))?.name, 'original');
              if (write) await database.apiProducts.put(_product(2, 'pending'));
              entered.complete();
              await release.future;
              if (throws) throw callbackError;
              return 'returned';
            }

            final transaction = _Observed(
              write ? database.writeTxn(callback) : database.readTxn(callback),
            );
            await _waitForEntry(entered, transaction);

            // Act. Teardown must complete without waiting for this callback.
            await database.close().timeout(_gateTimeout);
            final transactionWasPending = !transaction.finished;
            release.complete();
            await transaction.done.timeout(_gateTimeout);

            // Assert.
            expect(transactionWasPending, isTrue);
            expect(
              transaction.error,
              throws ? same(callbackError) : isA<CindelDatabaseClosedError>(),
            );
            await _expectClosed(database);
            await _expectStoredProducts(
              fixture.directory,
              const {1: 'original'},
              absentIds: const [2],
            );
          },
        );
      }

      // Scenario: an active callback awaits close on its own database handle.
      // Covers:
      // - Self-close completing without waiting for its own transaction callback.
      // - Cancellation before transaction finalization and pending-write rollback.
      // Expected: close succeeds, the outer transaction reports closed, and its
      // pending write does not persist.
      test(
        'closes inside its own ${write ? 'write' : 'read'} transaction.',
        () async {
          // Arrange.
          final fixture = await _openSeededDatabase();
          final database = fixture.database;
          var ownCloseCompleted = false;
          Future<String> callback() async {
            expect((await database.apiProducts.get(1))?.name, 'original');
            if (write) await database.apiProducts.put(_product(2, 'pending'));

            // Act.
            await database.close();
            ownCloseCompleted = true;
            return 'returned';
          }

          final transaction = _Observed(
            write ? database.writeTxn(callback) : database.readTxn(callback),
          );
          await transaction.done.timeout(_gateTimeout);

          // Assert.
          expect(ownCloseCompleted, isTrue);
          expect(transaction.error, isA<CindelDatabaseClosedError>());
          await _expectClosed(database);
          await _expectStoredProducts(
            fixture.directory,
            const {1: 'original'},
            absentIds: const [2],
          );
        },
      );
    }

    // Scenario: reads and writes enter immediately after close, before its await.
    // Covers:
    // - Existing admission before native-handle detachment.
    // - A committed write finishing without a later watcher-metadata close error.
    // Expected: both operations succeed and the admitted write persists.
    test('preserves immediately admitted read and write results.', () async {
      // Arrange.
      final fixture = await _openSeededDatabase();
      final database = fixture.database;

      // Act. Keep the three calls in the same synchronous turn.
      final close = _Observed(database.close());
      final read = _Observed(database.apiProducts.get(1));
      final write = _Observed(
        database.apiProducts.put(_product(2, 'admitted')),
      );
      await Future.wait([close.done, read.done, write.done]);

      // Assert.
      expect(close.error, isNull);
      expect(read.error, isNull);
      expect(read.value?.name, 'original');
      expect(write.error, isNull);
      await _expectClosed(database);
      await _expectStoredProducts(fixture.directory, const {
        1: 'original',
        2: 'admitted',
      });
    });

    // Scenario: a write callback starts put and close without awaiting either.
    // Covers:
    // - An admitted storage substep finishing successfully during cancellation.
    // - The outer transaction refusing to commit after close rolls it back.
    // Expected: put and close succeed, the callback returns, the transaction
    // reports closed, and its pending row remains absent after reopening.
    test('rolls back a transaction with an already admitted put.', () async {
      // Arrange.
      final fixture = await _openSeededDatabase();
      final database = fixture.database;
      _Observed<void>? pendingWrite;
      _Observed<void>? callbackClose;
      var callbackReturned = false;

      // Act.
      final transaction = _Observed(
        database.writeTxn(() async {
          expect((await database.apiProducts.get(1))?.name, 'original');
          final writeFuture = database.apiProducts.put(_product(2, 'pending'));
          pendingWrite = _Observed(writeFuture);
          final closeFuture = database.close();
          callbackClose = _Observed(closeFuture);
          // Await the actual operations: observers must not swallow callback errors.
          await Future.wait([writeFuture, closeFuture]);
          callbackReturned = true;
          return 'returned';
        }),
      );
      await transaction.done.timeout(_gateTimeout);

      // Assert.
      expect(pendingWrite, isNotNull);
      expect(callbackClose, isNotNull);
      expect(pendingWrite!.error, isNull);
      expect(callbackClose!.error, isNull);
      expect(callbackReturned, isTrue);
      expect(transaction.error, isA<CindelDatabaseClosedError>());
      await _expectClosed(database);
      await _expectStoredProducts(
        fixture.directory,
        const {1: 'original'},
        absentIds: const [2],
      );
    });

    // Scenario: two independently opened handles own the same persisted data.
    // Covers:
    // - Close state and native ownership remaining local to one handle.
    // - Reads and committed writes through the second handle after the first closes.
    // Expected: closing one handle leaves the other usable and its write persists.
    if (includeSameDirectoryHandles) {
      test('preserves a second handle when the first handle closes.', () async {
        // Arrange.
        final fixture = await _openSeededDatabase();
        final other = await _openDatabase(fixture.directory);

        // Act.
        await fixture.database.close();
        final original = await other.apiProducts.get(1);
        await other.apiProducts.put(_product(3, 'independent'));
        final inserted = await other.apiProducts.get(3);
        await other.close();

        // Assert.
        expect(original?.name, 'original');
        expect(inserted?.name, 'independent');
        await _expectClosed(fixture.database);
        await _expectClosed(other);
        await _expectStoredProducts(fixture.directory, const {
          1: 'original',
          3: 'independent',
        });
      });
    }

    // Scenario: a synchronous native hydration callback requests close.
    // Covers:
    // - Borrowed native reader access until hydration returns and releases it.
    // - A reentrant close preserving the generated reader's exact field layout.
    // Expected: hydration still returns valid data, then close completes safely.
    test('finishes a borrowed native reader before reentrant close.', () async {
      // Arrange.
      final fixture = await _openSeededDatabase();
      final database = fixture.database;
      final generatedReader = ApiProductSchema.readNativeDocument!;
      final fields =
          ApiProductSchema.fields.where((field) => !field.isId).toList()
            ..sort((left, right) => left.name.compareTo(right.name));
      final fieldTypes = Uint8List.fromList([
        for (final field in fields)
          switch (field.binaryType) {
            'bool' => 0,
            'int' => 1,
            'double' => 2,
            'string' => 3,
            'list' => 4,
            'object' => 5,
            _ => throw StateError(
              'Unsupported fixture type ${field.binaryType}',
            ),
          },
      ]);
      _Observed<void>? callbackClose;
      var callbackCount = 0;
      int? continuedId;

      // Act. The reader stays borrowed inside the callback and never escapes it.
      final rows = await database.getAllNativeBinaryDocuments<ApiProduct>(
        ApiProductSchema.name,
        [1],
        fieldTypes,
        (reader, index) {
          callbackCount += 1;
          callbackClose ??= _Observed(database.close());
          final user = generatedReader(reader, index);
          continuedId = reader.readId(index);
          return user;
        },
      );
      if (callbackClose != null) await callbackClose!.done;

      // Assert.
      expect(callbackCount, 1);
      expect(continuedId, 1);
      expect(callbackClose, isNotNull);
      expect(callbackClose!.error, isNull);
      expect(rows.single?.name, 'original');
      await _expectClosed(database);
      await _expectStoredProducts(fixture.directory, const {1: 'original'});
    });

    // Scenario: concurrent closes arrive while an adapter pull waits behind a gate.
    // Covers:
    // - The existing in-flight sync drain before handle detachment.
    // - One shared close future and persistence of the drained remote change.
    // Expected: both callers wait for pull, close without sync errors, and preserve
    // the remotely applied row without starting another pull.
    test('drains in-flight sync before concurrent close completes.', () async {
      // Arrange. Seed without sync so preparation cannot race the scheduler.
      final fixture = await _openSeededDatabase();
      await fixture.database.close();
      final adapter = _GatedSyncAdapter();
      final errors = <Object>[];
      final database = await _openDatabase(
        fixture.directory,
        sync: CindelSyncConfig(
          adapter: adapter,
          interval: const Duration(milliseconds: 5),
          onError: (error, _) => errors.add(error),
        ),
      );
      addTearDown(() {
        if (!adapter.releasePull.isCompleted) {
          adapter.releasePull.complete(
            const CindelPullResult(checkpoint: 'cleanup', changes: []),
          );
        }
      });
      await adapter.pullEntered.future.timeout(_gateTimeout);

      // Act.
      final firstFuture = database.close();
      final secondFuture = database.close();
      final first = _Observed(firstFuture);
      final second = _Observed(secondFuture);
      await _eventLoopTurn();
      final bothPending = !first.finished && !second.finished;
      adapter.releasePull.complete(
        CindelPullResult(
          checkpoint: 'drained',
          changes: [
            CindelRemoteUpsert(
              collection: ApiProductSchema.name,
              id: 3,
              document: ApiProductSchema.toDocument(_product(3, 'remote')),
            ),
          ],
        ),
      );
      await Future.wait([first.done, second.done]).timeout(_gateTimeout);

      // Assert.
      expect(bothPending, isTrue);
      expect(secondFuture, same(firstFuture));
      expect(first.error, isNull);
      expect(second.error, isNull);
      expect(errors, isEmpty);
      expect(adapter.pullCount, 1);
      await _expectClosed(database);
      await _expectStoredProducts(fixture.directory, const {
        1: 'original',
        3: 'remote',
      });
    });
  }, timeout: const Timeout(Duration(seconds: 30)));
}

const _gateTimeout = Duration(seconds: 5);

/// Registers handle cleanup before callers add gates or subscriptions, so their
/// teardown can release those resources before the database close is awaited.
Future<CindelDatabase> _openDatabase(
  String directory, {
  CindelSyncConfig? sync,
}) async {
  final database = await openTestDatabase(
    directory: directory,
    schemas: [ApiProductSchema],
    sync: sync,
  );
  addTearDown(database.close);
  return database;
}

Future<({String directory, CindelDatabase database})>
_openSeededDatabase() async {
  final directory = await createCloseTestDirectory();
  addTearDown(() => deleteCloseTestDirectory(directory));
  final database = await _openDatabase(directory);
  await database.apiProducts.put(_product(1, 'original'));
  return (directory: directory, database: database);
}

ApiProduct _product(int id, String name) => ApiProduct()
  ..dbId = id
  ..name = name
  ..id = 'close-$id';

Future<void> _expectClosed(CindelDatabase database) async {
  await expectLater(
    database.apiProducts.get(1),
    throwsA(isA<CindelDatabaseClosedError>()),
  );
  await expectLater(
    database.apiProducts.put(_product(4, 'closed')),
    throwsA(isA<CindelDatabaseClosedError>()),
  );
}

/// Persistence assertions use a new handle, rather than canceled callback state.
Future<void> _expectStoredProducts(
  String directory,
  Map<int, String> names, {
  Iterable<int> absentIds = const [],
}) async {
  final database = await _openDatabase(directory);
  for (final entry in names.entries) {
    expect((await database.apiProducts.get(entry.key))?.name, entry.value);
  }
  for (final id in absentIds) {
    expect(await database.apiProducts.get(id), isNull);
  }
  await database.close();
}

Future<void> _waitForEntry(
  Completer<void> entered,
  _Observed<Object?> operation,
) async {
  await Future.any([entered.future, operation.done]).timeout(_gateTimeout);
  expect(
    entered.isCompleted,
    isTrue,
    reason:
        'Callback must reach its controlled gate; error: ${operation.error}',
  );
}

Future<void> _eventLoopTurn() => Future<void>.delayed(Duration.zero);

/// Observe immediately so a deliberately suspended race never leaves errors
/// unhandled. Tests assert the captured outcome; application callbacks still
/// await their original operations when error propagation is part of the case.
final class _Observed<T> {
  _Observed(Future<T> operation) {
    done = operation.then<void>(
      (value) {
        this.value = value;
        finished = true;
      },
      onError: (Object error, StackTrace _) {
        this.error = error;
        finished = true;
      },
    );
  }

  late final Future<void> done;
  T? value;
  Object? error;
  bool finished = false;
}

/// A real adapter gate isolates close ordering from scheduler timing.
final class _GatedSyncAdapter implements CindelSyncAdapter {
  final pullEntered = Completer<void>();
  final releasePull = Completer<CindelPullResult>();
  int pullCount = 0;

  @override
  Future<CindelPullResult> pull(CindelPullRequest request) {
    pullCount += 1;
    if (!pullEntered.isCompleted) pullEntered.complete();
    return releasePull.future;
  }

  @override
  Future<CindelPushResult> push(CindelPushRequest request) async =>
      CindelPushResult(
        acceptedMutationIds: {
          for (final mutation in request.mutations) mutation.mutationId,
        },
      );
}
