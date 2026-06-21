import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel change sets', () {
    // Scenario: A remote handle changes a collection and exact ids are unknown.
    // Covers:
    // - [CindelChangeSet.external] unknown-id metadata.
    // - [CindelChangeSet.mayAffectDocument] unknown-id branch.
    // Expected: The change is external and may affect any document id.
    test('represents external collection changes with unknown ids.', () {
      // Act.
      final change = CindelChangeSet.external('users');

      // Assert.
      expect(change.collection, 'users');
      expect(change.documentIds, isNull);
      expect(change.documents, isEmpty);
      expect(change.hasUnknownDocuments, isTrue);
      expect(change.isExternal, isTrue);
      expect(change.revision, isNull);
      expect(change.mayAffectDocument(1), isTrue);
      expect(change.mayAffectDocument(999), isTrue);
    });

    // Scenario: A local upsert can include the written document snapshot.
    // Covers:
    // - [CindelChangeSet.upsert] document-copy branch.
    // - [CindelChangeSet.mayAffectDocument] exact-id branch.
    // Expected: Metadata keeps an immutable copy of the original document.
    test('copies local upsert document snapshots.', () {
      // Arrange.
      final document = <String, Object?>{'name': 'Ana'};

      // Act.
      final change = CindelChangeSet.upsert('users', 7, document);
      document['name'] = 'Changed';

      // Assert.
      expect(change.collection, 'users');
      expect(change.documentIds, {7});
      expect(change.documents, {
        7: {'name': 'Ana'},
      });
      expect(change.hasUnknownDocuments, isFalse);
      expect(change.isExternal, isFalse);
      expect(change.revision, isNull);
      expect(change.mayAffectDocument(7), isTrue);
      expect(change.mayAffectDocument(8), isFalse);
    });

    // Scenario: A local upsert knows the id but not the document value.
    // Covers:
    // - [CindelChangeSet.upsert] missing-document branch.
    // Expected: The id is exact, while document materialization is marked
    // unknown for watchers that need a fresh read.
    test('marks local upserts without snapshots as unknown documents.', () {
      // Act.
      final change = CindelChangeSet.upsert('users', 9, null);

      // Assert.
      expect(change.documentIds, {9});
      expect(change.documents, isEmpty);
      expect(change.hasUnknownDocuments, isTrue);
      expect(change.mayAffectDocument(9), isTrue);
      expect(change.mayAffectDocument(10), isFalse);
    });

    // Scenario: A batched local upsert can merge explicit ids and snapshots.
    // Covers:
    // - [CindelChangeSet.upserts] document copy loop.
    // - Merging [ids] with ids from [documents].
    // Expected: All affected ids are tracked and source maps are defensively
    // copied.
    test('copies batched upsert snapshots and merges affected ids.', () {
      // Arrange.
      final documents = <int, CindelDocument>{
        2: {'name': 'Ben'},
        3: {'name': 'Cam'},
      };

      // Act.
      final change = CindelChangeSet.upserts(
        'users',
        documents,
        ids: const [1, 2],
      );
      documents[2]!['name'] = 'Changed';

      // Assert.
      expect(change.documentIds, {1, 2, 3});
      expect(change.documents, {
        2: {'name': 'Ben'},
        3: {'name': 'Cam'},
      });
      expect(change.hasUnknownDocuments, isFalse);
      expect(change.isExternal, isFalse);
      expect(change.mayAffectDocument(1), isTrue);
      expect(change.mayAffectDocument(4), isFalse);
    });

    // Scenario: A batched local upsert reports only ids.
    // Covers:
    // - [CindelChangeSet.upserts] null-document branch.
    // Expected: Watchers know the affected ids but must read values if needed.
    test('marks batched upserts without snapshots as unknown documents.', () {
      // Act.
      final change = CindelChangeSet.upserts('users', null, ids: const [4, 5]);

      // Assert.
      expect(change.documentIds, {4, 5});
      expect(change.documents, isEmpty);
      expect(change.hasUnknownDocuments, isTrue);
      expect(change.isExternal, isFalse);
    });

    // Scenario: A batched local upsert reports unknown document values but no
    // exact ids.
    // Covers:
    // - [CindelChangeSet.upserts] null-document branch without explicit ids.
    // - [CindelChangeSet.mayAffectDocument] exact empty-id branch.
    // Expected: The change records no affected ids, still marks document values
    // as unknown, and does not claim unrelated ids may be affected.
    test('supports batched upserts with unknown documents and no ids.', () {
      // Act.
      final change = CindelChangeSet.upserts('users', null);

      // Assert.
      expect(change.collection, 'users');
      expect(change.documentIds, isEmpty);
      expect(change.documents, isEmpty);
      expect(change.hasUnknownDocuments, isTrue);
      expect(change.isExternal, isFalse);
      expect(change.revision, isNull);
      expect(change.mayAffectDocument(1), isFalse);
    });

    // Scenario: Deletion changes only need exact ids.
    // Covers:
    // - [CindelChangeSet.delete].
    // - [CindelChangeSet.deletes].
    // Expected: Deleted ids are exact and no document snapshots are attached.
    test('represents delete changes with exact ids.', () {
      // Act.
      final single = CindelChangeSet.delete('users', 6);
      final many = CindelChangeSet.deletes('users', const [6, 7, 7]);

      // Assert.
      expect(single.documentIds, {6});
      expect(single.documents, isEmpty);
      expect(single.hasUnknownDocuments, isFalse);
      expect(many.documentIds, {6, 7});
      expect(many.documents, isEmpty);
      expect(many.hasUnknownDocuments, isFalse);
    });

    // Scenario: Native post-commit change sets include collection revisions.
    // Covers:
    // - [CindelChangeSet.native] document copy loop.
    // - Native revision metadata.
    // Expected: Documents are copied, ids are exact, and the native revision is
    // retained.
    test('copies native change snapshots and retains revision metadata.', () {
      // Arrange.
      final documents = <int, CindelDocument>{
        11: {'name': 'Dee'},
      };

      // Act.
      final change = CindelChangeSet.native(
        collection: 'users',
        revision: 42,
        ids: const [11, 12],
        documents: documents,
        hasUnknownDocuments: true,
      );
      documents[11]!['name'] = 'Changed';

      // Assert.
      expect(change.collection, 'users');
      expect(change.documentIds, {11, 12});
      expect(change.documents, {
        11: {'name': 'Dee'},
      });
      expect(change.hasUnknownDocuments, isTrue);
      expect(change.isExternal, isFalse);
      expect(change.revision, 42);
      expect(change.mayAffectDocument(11), isTrue);
      expect(change.mayAffectDocument(13), isFalse);
      expect(
        () => change.documents[13] = {'name': 'Eli'},
        throwsUnsupportedError,
      );
    });

    // Scenario: Native post-commit changes can carry only revision and ids.
    // Covers:
    // - [CindelChangeSet.native] default document and unknown-document options.
    // - Native id de-duplication.
    // Expected: Defaults represent an exact native change with no attached
    // snapshots and no unknown document payloads.
    test('represents native change metadata with default options.', () {
      // Act.
      final change = CindelChangeSet.native(
        collection: 'users',
        revision: 43,
        ids: const [1, 1, 2],
      );

      // Assert.
      expect(change.collection, 'users');
      expect(change.documentIds, {1, 2});
      expect(change.documents, isEmpty);
      expect(change.hasUnknownDocuments, isFalse);
      expect(change.isExternal, isFalse);
      expect(change.revision, 43);
      expect(change.mayAffectDocument(2), isTrue);
      expect(change.mayAffectDocument(3), isFalse);
    });
  });
}
