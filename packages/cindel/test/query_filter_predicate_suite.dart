import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel filter predicates', () {
    // Scenario: Public predicate builders receive invalid field names or paths.
    // Covers:
    // - [CindelFilter.field] rejecting empty field names.
    // - [CindelFilter.path] rejecting empty paths and empty path parts.
    // Expected: Invalid predicate builders fail before a query can be built.
    test('rejects empty field names and path parts.', () {
      // Act / Assert.
      expect(() => CindelFilter.field(''), throwsA(isA<ArgumentError>()));
      expect(() => CindelFilter.field('   '), throwsA(isA<ArgumentError>()));
      expect(
        () => CindelFilter.path(const <String>[]),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CindelFilter.path(const ['profile', '']),
        throwsA(isA<ArgumentError>()),
      );
    });

    // Scenario: A predicate targets values inside embedded objects and lists of
    // embedded objects.
    // Covers:
    // - Recursive map traversal.
    // - Recursive list traversal without consuming the next path part.
    // - Missing nested keys returning no values.
    // Expected: Nested paths match any embedded value at the requested path and
    // return false when no value exists.
    test('matches nested object paths through maps and lists.', () {
      // Arrange.
      final document = <String, Object?>{
        'profile': {
          'name': 'Ana',
          'labels': [
            {'value': 'admin'},
            {'value': 'owner'},
          ],
        },
      };

      // Act / Assert.
      expect(
        CindelFilter.path(const [
          'profile',
          'name',
        ]).equalTo('Ana').matches(document),
        isTrue,
      );
      expect(
        CindelFilter.path(const [
          'profile',
          'labels',
          'value',
        ]).equalTo('owner').matches(document),
        isTrue,
      );
      expect(
        CindelFilter.path(const [
          'profile',
          'labels',
          'missing',
        ]).equalTo('owner').matches(document),
        isFalse,
      );
    });

    // Scenario: Scalar field predicates compare numbers and strings directly.
    // Covers:
    // - Greater/less comparisons and inclusive variants.
    // - Invalid numeric comparisons returning false.
    // - String contains, startsWith, and endsWith over non-string values.
    // Expected: Scalar predicates match only compatible stored value types.
    test('matches scalar numeric and string operations.', () {
      // Arrange.
      final document = <String, Object?>{
        'count': 4,
        'title': 'release notes',
        'flag': true,
      };

      // Act / Assert.
      expect(
        CindelFilter.field('count').greaterThan(3).matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field('count').greaterThanOrEqualTo(4).matches(document),
        isTrue,
      );
      expect(CindelFilter.field('count').lessThan(5).matches(document), isTrue);
      expect(
        CindelFilter.field('count').lessThanOrEqualTo(4).matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field('title').greaterThan(1).matches(document),
        isFalse,
      );
      expect(
        CindelFilter.field('title').contains('notes').matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field('title').startsWith('release').matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field('title').endsWith('notes').matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field('flag').contains('true').matches(document),
        isFalse,
      );
    });

    // Scenario: List predicates evaluate membership and length constraints.
    // Covers:
    // - List contains using deep equality.
    // - Empty and non-empty checks.
    // - Exact, inclusive, and exclusive length comparisons.
    // - [CindelFilterField.between] requiring at least one bound.
    // Expected: List predicates match list values and reject non-list values.
    test('matches list membership and length operations.', () {
      // Arrange.
      final document = <String, Object?>{
        'tags': ['dart', 'flutter'],
        'empty': <String>[],
        'objects': [
          {
            'name': 'primary',
            'values': [1, 2],
          },
        ],
        'title': 'not a list',
      };

      // Act / Assert.
      expect(
        CindelFilter.field('tags').contains('dart').matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field('objects')
            .contains({
              'name': 'primary',
              'values': [1, 2],
            })
            .matches(document),
        isTrue,
      );
      expect(CindelFilter.field('empty').isEmpty().matches(document), isTrue);
      expect(CindelFilter.field('tags').isNotEmpty().matches(document), isTrue);
      expect(
        CindelFilter.field('tags').lengthEqualTo(2).matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field(
          'tags',
        ).lengthGreaterThan(2, include: true).matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field(
          'tags',
        ).lengthLessThan(2, include: true).matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field('tags')
            .lengthBetween(1, 3, includeLower: false, includeUpper: false)
            .matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field('title').lengthEqualTo(10).matches(document),
        isFalse,
      );
      expect(
        () => CindelFilter.field('count').between(null, null),
        throwsA(isA<ArgumentError>()),
      );
    });

    // Scenario: Field equality receives nested values instead of primitive
    // scalar values.
    // Covers:
    // - Deep map equality.
    // - Deep iterable equality.
    // - Map key mismatch and iterable length mismatch.
    // Expected: Equality is structural for document-shaped values.
    test('matches structural equality for maps and lists.', () {
      // Arrange.
      final document = <String, Object?>{
        'profile': {
          'name': 'Ana',
          'scores': [1, 2, 3],
        },
        'scores': [1, 2, 3],
      };

      // Act / Assert.
      expect(
        CindelFilter.field('profile')
            .equalTo({
              'name': 'Ana',
              'scores': [1, 2, 3],
            })
            .matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field('profile')
            .equalTo({
              'name': 'Ana',
              'missing': [1, 2, 3],
            })
            .matches(document),
        isFalse,
      );
      expect(
        CindelFilter.field('scores').equalTo([1, 2, 3]).matches(document),
        isTrue,
      );
      expect(
        CindelFilter.field('scores').equalTo([1, 2]).matches(document),
        isFalse,
      );
    });

    // Scenario: Predicate groups are evaluated without a database.
    // Covers:
    // - Empty [CindelFilter.all] semantics.
    // - Empty [CindelFilter.any] semantics.
    // - [CindelFilter.not] negating another predicate.
    // Expected: Boolean groups follow Dart every/any semantics.
    test('matches boolean composition semantics.', () {
      // Arrange.
      final document = <String, Object?>{'active': true};

      // Act / Assert.
      expect(CindelFilter.all(const []).matches(document), isTrue);
      expect(CindelFilter.any(const []).matches(document), isFalse);
      expect(
        CindelFilter.not(
          CindelFilter.field('active').equalTo(false),
        ).matches(document),
        isTrue,
      );
    });
  });
}
