import 'dart:async';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'backup_contract_fixture.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'dart_distinct_fixture.dart';
import 'schema_generation_fixture.dart'
    show ImmutableUser, ImmutableUserSchema, Recipient, RecipientMetadata;

void main({bool concurrentHandles = true}) {
  group('Cindel atomic migrations', () {
    Future<String> seed({int count = 7}) async {
      final path = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(path));
      final db = await CindelDatabase.openForMigration(
        directory: path,
        backend: testStorageBackend,
        schemas: [backupNodeSchema, backupLeafSchema],
      );
      try {
        await db.typedCollection(backupNodeSchema).putAll([
          for (var id = 1; id <= count; id++)
            BackupNode(id, payload: 'old-$id'),
        ]);
        await db
            .typedCollection(backupLeafSchema)
            .put(BackupNode(50, payload: 'untouched'));
        await db.saveLinkIds(
          sourceCollection: 'backup_nodes',
          sourceId: 1,
          linkName: 'children',
          targetCollection: 'backup_nodes',
          targetIds: [2],
        );
        await db.setMigrationVersion(1);
      } finally {
        await db.close();
      }
      return path;
    }

    CindelMigrationStep step({
      int from = 1,
      int to = 2,
      CindelMigrationCallback? before,
      CindelMigrationCallback? migrate,
      CindelMigrationCallback? after,
    }) => CindelMigrationStep(
      fromVersion: from,
      toVersion: to,
      openSchemas: [backupNodeSchema, backupLeafSchema],
      targetSchemas: [backupNodeSchema],
      verifyBefore: before,
      migrate:
          migrate ??
          (context) async {
            await context.registerTargetSchemas();
            await context.importObjectStream(
              backupNodeSchema,
              context
                  .streamObjects(backupNodeSchema, batchSize: 2)
                  .map(
                    (node) =>
                        BackupNode(node.dbId, payload: 'new-${node.dbId}'),
                  ),
              batchSize: 2,
            );
          },
      verifyAfter: after,
    );

    Future<CindelDatabase> run(
      String path,
      List<CindelMigrationStep> steps, {
      int version = 2,
    }) => Cindel.open(
      directory: path,
      backend: testStorageBackend,
      schemas: [backupNodeSchema, backupLeafSchema],
      migrationPlan: CindelMigrationPlan(
        targetVersion: version,
        steps: steps,
        compactOnSuccess: false,
      ),
    );

    Future<void> assertState(
      String path, {
      int version = 1,
      String prefix = 'old',
      int count = 7,
    }) async {
      final db = await CindelDatabase.openForMigration(
        directory: path,
        backend: testStorageBackend,
        schemas: [backupNodeSchema, backupLeafSchema],
      );
      try {
        expect(await db.migrationVersion(), version);
        expect(await db.typedCollection(backupNodeSchema).all().count(), count);
        expect(await db.schemaVersion('backup_nodes'), version);
        for (var id = 1; id <= count; id++) {
          expect(
            (await db.typedCollection(backupNodeSchema).get(id))!.payload,
            '$prefix-$id',
          );
        }
        final first = (await db.typedCollection(backupNodeSchema).get(1))!;
        await first.children.load();
        expect(first.children.single.dbId, 2);
        final second = (await db.typedCollection(backupNodeSchema).get(2))!;
        await second.owners.load();
        expect(second.owners.single.dbId, 1);
        expect(
          (await db.typedCollection(backupLeafSchema).get(50))!.payload,
          'untouched',
        );
      } finally {
        await db.close();
      }
    }

    for (final failure in [
      'before',
      'schema',
      'batch',
      'verify',
      'unique',
      'close',
    ]) {
      test(
        'failure at $failure preserves data, schema, relations and version after reopen.',
        () async {
          final path = await seed();
          final planStep = step(
            before: (context) async {
              if (failure == 'before') {
                await context.database
                    .typedCollection(backupNodeSchema)
                    .put(BackupNode(99));
                throw StateError('injected');
              }
            },
            migrate: (context) async {
              await context.registerTargetSchemas();
              if (failure == 'schema') throw StateError('injected');
              if (failure == 'close') {
                await context.database.close();
                throw StateError('injected');
              }
              Stream<BackupNode> transformed() async* {
                var seen = 0;
                await for (final node in context.streamObjects(
                  backupNodeSchema,
                  batchSize: 2,
                )) {
                  if (++seen == 5 && failure == 'batch') {
                    throw StateError('injected');
                  }
                  yield BackupNode(
                    node.dbId,
                    code: failure == 'unique' && node.dbId == 5 ? 1 : node.dbId,
                    payload: 'new-${node.dbId}',
                  );
                }
              }

              await context.importObjectStream(
                backupNodeSchema,
                transformed(),
                batchSize: 2,
              );
            },
            after: (_) {
              if (failure == 'verify') throw StateError('injected');
            },
          );
          await expectLater(run(path, [planStep]), throwsA(anything));
          await assertState(path);
          final retried = await run(path, [step()]);
          await retried.close();
          await assertState(path, version: 2, prefix: 'new');
        },
      );
    }

    test(
      'streams original rows after target registration and publishes exactly once.',
      () async {
        final path = await seed();
        var seen = 0;
        final migrationStep = step(
          migrate: (context) async {
            await context.registerTargetSchemas();
            await context.importDocumentStream(
              backupNodeSchema,
              context.streamDocuments(backupNodeSchema, batchSize: 3).map((
                document,
              ) {
                seen++;
                return {...document, 'payload': 'new-${document['dbId']}'};
              }),
              batchSize: 2,
            );
          },
        );
        final db = await run(path, [migrationStep]);
        expect(seen, 7);
        await db.close();
        await assertState(path, version: 2, prefix: 'new');
        final again = await run(path, [migrationStep]);
        expect(seen, 7);
        await again
            .typedCollection(backupNodeSchema)
            .put(BackupNode(autoIncrement, code: 100));
        expect(await again.documentIds('backup_nodes'), [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
        ]);
        await again.close();
      },
    );

    test('later step failure keeps the earlier committed step.', () async {
      final path = await seed();
      await expectLater(
        run(path, [
          step(),
          step(from: 2, to: 3, after: (_) => throw StateError('later')),
        ], version: 3),
        throwsStateError,
      );
      await assertState(path, version: 2, prefix: 'new');
    });

    test(
      'lazy iterable is consumed one batch at a time and empty streams work.',
      () async {
        final path = await seed();
        final db = await run(path, [
          step(
            migrate: (context) async {
              await context.registerTargetSchemas();
              Iterable<BackupNode> generate() sync* {
                for (var id = 1; id <= 7; id++) {
                  yield BackupNode(id, payload: 'new-$id');
                }
              }

              await context.importObjects(
                backupNodeSchema,
                generate(),
                batchSize: 2,
              );
              await context.importObjectStream(
                backupNodeSchema,
                const Stream.empty(),
              );
              await expectLater(
                context.importObjects(backupNodeSchema, [], batchSize: 0),
                throwsArgumentError,
              );
            },
          ),
        ]);
        await db.close();
        await assertState(path, version: 2, prefix: 'new');
      },
    );

    test('preserves immutable IDs and generated nested/list values.', () async {
      final path = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(path));
      final schemas = [ImmutableUserSchema, DistinctRecordSchema];
      final source = await CindelDatabase.openForMigration(
        directory: path,
        backend: testStorageBackend,
        schemas: schemas,
      );
      await source
          .typedCollection(ImmutableUserSchema)
          .put(const ImmutableUser(dbId: 91, email: 'á@local', active: true));
      await source
          .typedCollection(DistinctRecordSchema)
          .put(
            DistinctRecord()
              ..dbId = 7
              ..name = 'nested'
              ..email = 'n@local'
              ..tags = ['a,b', '', '🚀']
              ..primaryRecipient = (Recipient()
                ..name = 'r'
                ..metadata = (RecipientMetadata()..label = 'inside'))
              ..recipients = [],
          );
      await source.setMigrationVersion(1);
      await source.close();
      final db = await Cindel.open(
        directory: path,
        backend: testStorageBackend,
        schemas: schemas,
        migrationPlan: CindelMigrationPlan(
          targetVersion: 3,
          compactOnSuccess: false,
          steps: [
            for (final from in [1, 2])
              CindelMigrationStep(
                fromVersion: from,
                toVersion: from + 1,
                openSchemas: schemas,
                migrate: (context) async {
                  await context.registerTargetSchemas();
                  await context.importObjectStream(
                    ImmutableUserSchema,
                    context.streamObjects(ImmutableUserSchema).map((row) {
                      expect(row.dbId, 91);
                      return row;
                    }),
                  );
                  await context.importObjectStream(
                    DistinctRecordSchema,
                    context.streamObjects(DistinctRecordSchema).map((row) {
                      // Also checks the persisted output on the second step.
                      expect(row.tags, ['a,b', '', '🚀']);
                      expect(row.primaryRecipient!.metadata!.label, 'inside');
                      expect(row.recipients, isEmpty);
                      return row;
                    }),
                  );
                },
              ),
          ],
        ),
      );
      try {
        final immutable = (await db
            .typedCollection(ImmutableUserSchema)
            .get(91))!;
        expect(await db.documentIds(ImmutableUserSchema.name), [91]);
        expect(immutable.email, 'á@local');
        final nested = (await db.typedCollection(DistinctRecordSchema).get(7))!;
        expect(nested.tags, ['a,b', '', '🚀']);
        expect(nested.displayName, isNull);
        expect(nested.primaryRecipient!.metadata!.label, 'inside');
        expect(await db.migrationVersion(), 3);
      } finally {
        await db.close();
      }
    });

    for (final size in [1000, 10000]) {
      test(
        'streams $size objects with bounded pending objects and one visit per ID.',
        () async {
          final elapsed = Stopwatch()..start();
          final path = await seed(count: 2);
          final source = await openTestDatabase(
            directory: path,
            schemas: [backupNodeSchema],
          );
          for (var start = 1; start <= size; start += 100) {
            await source.typedCollection(backupNodeSchema).putAll([
              for (var id = start; id < start + 100; id++)
                BackupNode(id, payload: 'x' * 1024),
            ]);
          }
          await source.close();
          print(
            'Migration $testStorageBackend $size: seeded in ${elapsed.elapsedMilliseconds} ms',
          );
          var produced = 0;
          var written = 0;
          var maximumPending = 0;
          final target = _trackedSchema(() {
            written++;
          });
          final db = await run(path, [
            step(
              migrate: (context) async {
                await context.registerTargetSchemas();
                print(
                  'Migration $testStorageBackend $size: prepared in ${elapsed.elapsedMilliseconds} ms',
                );
                final transformed = context
                    .streamObjects(backupNodeSchema, batchSize: 73)
                    .map((row) {
                      expect(row.dbId, ++produced);
                      final pending = produced - written;
                      if (pending > maximumPending) maximumPending = pending;
                      return row;
                    });
                await context.importObjectStream(
                  target,
                  transformed,
                  batchSize: 29,
                );
                print(
                  'Migration $testStorageBackend $size: imported in ${elapsed.elapsedMilliseconds} ms',
                );
              },
            ),
          ]);
          try {
            print(
              'Migration $testStorageBackend $size: published in ${elapsed.elapsedMilliseconds} ms, pending=$maximumPending',
            );
            expect(produced, size);
            expect(written, size);
            expect(maximumPending, 29);
            expect(
              await db.typedCollection(backupNodeSchema).all().count(),
              size,
            );
            expect(
              (await db.typedCollection(backupNodeSchema).get(size))!
                  .payload
                  .length,
              1024,
            );
          } finally {
            await db.close();
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    }

    test(
      'removed identities lose orphaned links before verification.',
      () async {
        final path = await seed();
        final db = await run(path, [
          step(
            migrate: (context) async {
              await context.registerTargetSchemas();
              await context.importObjectStream(
                backupNodeSchema,
                context
                    .streamObjects(backupNodeSchema)
                    .where((row) => row.dbId != 2),
              );
            },
            after: (context) async {
              final first = (await context.database
                  .typedCollection(backupNodeSchema)
                  .get(1))!;
              await first.children.load();
              expect(first.children, isEmpty);
            },
          ),
        ]);
        try {
          await db.typedCollection(backupNodeSchema).put(BackupNode(2));
          final first = (await db.typedCollection(backupNodeSchema).get(1))!;
          await first.children.load();
          expect(first.children, isEmpty);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'renamed persisted fields roll back on failure and publish on retry.',
      () async {
        final path = await seed();
        var fail = true;
        Future<CindelDatabase> migrate() => Cindel.open(
          directory: path,
          backend: testStorageBackend,
          schemas: [_renamedSchema, backupLeafSchema],
          migrationPlan: CindelMigrationPlan(
            targetVersion: 2,
            compactOnSuccess: false,
            steps: [
              CindelMigrationStep(
                fromVersion: 1,
                toVersion: 2,
                openSchemas: [backupNodeSchema, backupLeafSchema],
                targetSchemas: [_renamedSchema],
                migrate: (context) async {
                  await context.registerTargetSchemas();
                  await context.importObjectStream(
                    _renamedSchema,
                    context.streamObjects(backupNodeSchema, batchSize: 2),
                  );
                },
                verifyAfter: (context) async {
                  expect(
                    (await context.database
                            .typedCollection(_renamedSchema)
                            .get(7))!
                        .payload,
                    'old-7',
                  );
                  if (fail) throw StateError('after renamed field import');
                },
              ),
            ],
          ),
        );
        await expectLater(migrate(), throwsStateError);
        await assertState(path);
        fail = false;
        final db = await migrate();
        try {
          expect(await db.migrationVersion(), 2);
          expect(
            (await db.typedCollection(_renamedSchema).get(7))!.payload,
            'old-7',
          );
          expect(
            (await db.typedCollection(backupLeafSchema).get(50))!.payload,
            'untouched',
          );
        } finally {
          await db.close();
        }
        final reopened = await migrate();
        try {
          expect(
            (await reopened.typedCollection(_renamedSchema).get(1))!.payload,
            'old-1',
          );
        } finally {
          await reopened.close();
        }
      },
    );

    if (concurrentHandles) {
      test(
        'streamed native SQLite and MDBX migrations preserve int64 precision.',
        () async {
          final path = await seed(count: 2);
          final source = await openTestDatabase(
            directory: path,
            schemas: [backupNodeSchema],
          );
          // Parsed only in native tests; dart2js rejects unsafe integer literals
          // even in a test that is excluded at runtime.
          final large = int.parse('9007199254740993');
          final values = [large, -large];
          await source.typedCollection(backupNodeSchema).putAll([
            for (var i = 0; i < values.length; i++)
              BackupNode(i + 1, code: values[i]),
          ]);
          await source.close();
          final db = await run(path, [
            step(
              migrate: (context) async {
                await context.registerTargetSchemas();
                await context.importObjectStream(
                  backupNodeSchema,
                  context.streamObjects(backupNodeSchema).map((row) {
                    expect(row.code, values[row.dbId - 1]);
                    return row;
                  }),
                );
              },
            ),
          ]);
          try {
            expect(
              (await db.typedCollection(backupNodeSchema).get(1))!.code,
              values[0],
            );
            expect(
              (await db.typedCollection(backupNodeSchema).get(2))!.code,
              values[1],
            );
          } finally {
            await db.close();
          }
        },
      );

      test('concurrent writes reject publication and remain intact.', () async {
        final path = await seed();
        final other = await openTestDatabase(
          directory: path,
          schemas: [backupNodeSchema, backupLeafSchema],
        );
        try {
          await expectLater(
            run(path, [
              step(
                after: (_) async {
                  await other
                      .typedCollection(backupNodeSchema)
                      .put(BackupNode(9, payload: 'concurrent'));
                },
              ),
            ]),
            throwsA(predicate((e) => e.toString().contains('changed'))),
          );
          expect(
            (await other.typedCollection(backupNodeSchema).get(9))!.payload,
            'concurrent',
          );
          expect(
            (await other.typedCollection(backupNodeSchema).get(1))!.payload,
            'old-1',
          );
          expect(await other.migrationVersion(), 1);
        } finally {
          await other.close();
        }
      });
    }
  });
}

final _renamedSchema = CindelCollectionSchema<BackupNode>(
  name: backupNodeSchema.name,
  dartName: backupNodeSchema.dartName,
  idField: backupNodeSchema.idField,
  fields: [
    ...backupNodeSchema.fields.where((field) => field.name != 'payload'),
    const CindelFieldSchema(
      name: 'text',
      dartType: 'String',
      binaryType: 'string',
      isId: false,
      isIndexed: false,
    ),
  ],
  links: backupNodeSchema.links,
  toDocument: (node) => {
    'dbId': node.dbId,
    'code': node.code,
    'text': node.payload,
  },
  fromDocument: (doc) => BackupNode(
    doc['dbId']! as int,
    code: doc['code']! as int,
    payload: doc['text']! as String,
  ),
  toBinaryDocument: backupNodeSchema.toBinaryDocument,
  fromBinaryDocument: backupNodeSchema.fromBinaryDocument,
  writeNativeDocument: backupNodeSchema.writeNativeDocument,
  readNativeDocument: backupNodeSchema.readNativeDocument,
  getId: backupNodeSchema.getId,
  setId: backupNodeSchema.setId,
  bindLinks: backupNodeSchema.bindLinks,
);

CindelCollectionSchema<BackupNode> _trackedSchema(void Function() onWrite) =>
    CindelCollectionSchema<BackupNode>(
      name: backupNodeSchema.name,
      dartName: backupNodeSchema.dartName,
      idField: backupNodeSchema.idField,
      fields: backupNodeSchema.fields,
      links: backupNodeSchema.links,
      toDocument: backupNodeSchema.toDocument,
      fromDocument: backupNodeSchema.fromDocument,
      toBinaryDocument: backupNodeSchema.toBinaryDocument,
      fromBinaryDocument: backupNodeSchema.fromBinaryDocument,
      readNativeDocument: backupNodeSchema.readNativeDocument,
      writeNativeDocument: (writer, object) {
        onWrite();
        backupNodeSchema.writeNativeDocument!(writer, object);
      },
      getId: backupNodeSchema.getId,
      setId: backupNodeSchema.setId,
      bindLinks: backupNodeSchema.bindLinks,
    );
