import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:cindel_annotations/cindel_annotations.dart';
import 'package:source_gen/source_gen.dart';

const _indexChecker = TypeChecker.typeNamed(
  Index,
  inPackage: 'cindel_annotations',
);

const _ignoreChecker = TypeChecker.typeNamed(
  Ignore,
  inPackage: 'cindel_annotations',
);

const _enumeratedChecker = TypeChecker.typeNamed(
  Enumerated,
  inPackage: 'cindel_annotations',
);

const _embeddedChecker = TypeChecker.typeNamed(
  Embedded,
  inPackage: 'cindel_annotations',
);

/// Generates schemas and serializers for classes annotated with `@collection`.
final class CindelGenerator extends GeneratorForAnnotation<Collection> {
  /// Creates a Cindel generator.
  const CindelGenerator() : super(inPackage: 'cindel_annotations');

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@collection can only be used on classes.',
        element: element,
      );
    }
    if (element.isAbstract) {
      throw InvalidGenerationSourceError(
        '@collection classes must be concrete.',
        element: element,
      );
    }

    final collection = _CollectionInfo.from(element, annotation);
    return _emitCollection(collection);
  }
}

String _emitCollection(_CollectionInfo collection) {
  final buffer = StringBuffer()
    ..writeln('// ignore_for_file: non_constant_identifier_names')
    ..writeln()
    ..writeln(
      'final ${collection.schemaName} = '
      'CindelCollectionSchema<${collection.dartName}>(',
    )
    ..writeln('  name: ${_stringLiteral(collection.name)},')
    ..writeln('  dartName: ${_stringLiteral(collection.dartName)},')
    ..writeln('  idField: ${_stringLiteral(collection.idField.name)},')
    ..writeln('  fields: <CindelFieldSchema>[');

  for (final field in collection.fields) {
    buffer
      ..writeln('    CindelFieldSchema(')
      ..writeln('      name: ${_stringLiteral(field.name)},')
      ..writeln('      dartType: ${_stringLiteral(field.dartType)},')
      ..writeln('      isId: ${field.isId},')
      ..writeln('      isIndexed: ${field.isIndexed},')
      ..writeln('      isIndexUnique: ${field.isIndexUnique},')
      ..writeln('      indexCaseSensitive: ${field.indexCaseSensitive},')
      ..writeln('      indexType: CindelIndexType.${field.indexType.name},')
      ..writeln('    ),');
  }

  buffer
    ..writeln('  ],')
    ..writeln('  toDocument: _\$${collection.dartName}ToCindelDocument,')
    ..writeln('  fromDocument: _\$${collection.dartName}FromCindelDocument,')
    ..writeln(
      '  toBinaryDocument: _\$${collection.dartName}ToCindelBinaryDocument,',
    )
    ..writeln(
      '  fromBinaryDocument: '
      '_\$${collection.dartName}FromCindelBinaryDocument,',
    )
    ..writeln('  setId: _\$${collection.dartName}SetCindelId,')
    ..writeln(');')
    ..writeln()
    ..writeln(
      'extension ${collection.dartName}CindelCollectionAccess '
      'on CindelDatabase {',
    )
    ..writeln(
      '  CindelTypedCollection<${collection.dartName}> '
      'get ${collection.accessorName} => '
      'typedCollection(${collection.schemaName});',
    )
    ..writeln('}')
    ..writeln()
    ..writeln(
      'extension ${collection.dartName}CindelQueryAccess '
      'on CindelTypedCollection<${collection.dartName}> {',
    )
    ..writeln(
      '  ${collection.queryWhereName} where() => '
      '${collection.queryWhereName}(this);',
    )
    ..writeln()
    ..writeln(
      '  ${collection.queryFilterName} filter() => '
      '${collection.queryFilterName}(',
    )
    ..writeln('    CindelQuery.all(')
    ..writeln('      database: database,')
    ..writeln('      schema: ${collection.schemaName},')
    ..writeln('    ),')
    ..writeln('  );')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'extension ${collection.dartName}CindelQueryFilterAccess '
      'on CindelQuery<${collection.dartName}> {',
    )
    ..writeln(
      '  ${collection.queryFilterName} filter() => '
      '${collection.queryFilterName}(this);',
    )
    ..writeln('}')
    ..writeln()
    ..writeln(
      'extension ${collection.dartName}CindelQueryModifierAccess '
      'on CindelQuery<${collection.dartName}> {',
    );

  for (final field in collection.fields) {
    _emitQueryModifierMethods(buffer, collection, field);
  }

  buffer
    ..writeln('}')
    ..writeln()
    ..writeln('final class ${collection.queryWhereName} {')
    ..writeln('  const ${collection.queryWhereName}(this._collection);')
    ..writeln()
    ..writeln(
      '  final CindelTypedCollection<${collection.dartName}> _collection;',
    );

  for (final field in collection.indexedFields) {
    _emitIndexedWhereMethods(buffer, collection, field);
  }

  buffer
    ..writeln('}')
    ..writeln()
    ..writeln('final class ${collection.queryFilterName} {')
    ..writeln('  const ${collection.queryFilterName}(this._query);')
    ..writeln()
    ..writeln('  final CindelQuery<${collection.dartName}> _query;');

  for (final field in collection.fields) {
    _emitFilterMethods(buffer, collection, field);
  }

  buffer
    ..writeln('}')
    ..writeln()
    ..writeln('Map<String, Object?> _\$${collection.dartName}ToCindelDocument(')
    ..writeln('  ${collection.dartName} object,')
    ..writeln(') {')
    ..writeln('  return <String, Object?>{');

  for (final field in collection.fields) {
    buffer.writeln(
      '    ${_stringLiteral(field.name)}: ${field.toDocumentExpression},',
    );
  }

  buffer
    ..writeln('  };')
    ..writeln('}')
    ..writeln()
    ..writeln(
      '${collection.dartName} _\$${collection.dartName}'
      'FromCindelDocument(',
    )
    ..writeln('  Map<String, Object?> document,')
    ..writeln(') {')
    ..writeln('  final object = ${collection.dartName}();');

  for (final field in collection.fields) {
    buffer.writeln(
      '  object.${field.name} = '
      '${field.fromDocumentExpression(_stringLiteral(field.name))};',
    );
  }

  buffer
    ..writeln('  return object;')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'CindelBinaryDocumentBytes '
      '_\$${collection.dartName}ToCindelBinaryDocument('
      '${collection.dartName} object) {',
    )
    ..writeln('  return cindelEncodeBinaryDocument(<Object?>[');

  for (final field in collection.binaryFields) {
    buffer.writeln('    ${field.toDocumentExpression},');
  }

  buffer
    ..writeln('  ]);')
    ..writeln('}')
    ..writeln()
    ..writeln(
      '${collection.dartName} _\$${collection.dartName}'
      'FromCindelBinaryDocument(CindelBinaryDocumentBytes bytes) {',
    )
    ..writeln('  final fields = cindelDecodeBinaryDocument(bytes);')
    ..writeln('  final object = ${collection.dartName}();');

  for (var index = 0; index < collection.binaryFields.length; index += 1) {
    final field = collection.binaryFields[index];
    buffer.writeln(
      '  object.${field.name} = '
      '${field.fromStoredValueExpression('fields[$index]')};',
    );
  }

  buffer
    ..writeln('  return object;')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'void _\$${collection.dartName}SetCindelId('
      '${collection.dartName} object, int id) {',
    )
    ..writeln('  object.${collection.idField.name} = id;')
    ..writeln('}');

  for (final embedded in collection.embeddedTypes) {
    _emitEmbeddedHelpers(buffer, embedded);
  }

  return buffer.toString();
}

void _emitEmbeddedHelpers(StringBuffer buffer, _EmbeddedInfo embedded) {
  buffer
    ..writeln()
    ..writeln('Map<String, Object?> _\$${embedded.dartName}ToCindelEmbedded(')
    ..writeln('  ${embedded.dartName} object,')
    ..writeln(') {')
    ..writeln('  return <String, Object?>{');

  for (final field in embedded.fields) {
    buffer.writeln(
      '    ${_stringLiteral(field.name)}: ${field.toDocumentExpression},',
    );
  }

  buffer
    ..writeln('  };')
    ..writeln('}')
    ..writeln()
    ..writeln('${embedded.dartName} _\$${embedded.dartName}FromCindelEmbedded(')
    ..writeln('  Map<String, Object?> document,')
    ..writeln(') {')
    ..writeln('  final object = ${embedded.dartName}();');

  for (final field in embedded.fields) {
    buffer.writeln(
      '  object.${field.name} = '
      '${field.fromDocumentExpression(_stringLiteral(field.name))};',
    );
  }

  buffer
    ..writeln('  return object;')
    ..writeln('}');
}

void _emitQueryModifierMethods(
  StringBuffer buffer,
  _CollectionInfo collection,
  _FieldInfo field,
) {
  final queryType = 'CindelQuery<${collection.dartName}>';
  final fieldLiteral = _stringLiteral(field.name);
  final suffix = _upperFirst(field.name);

  buffer
    ..writeln()
    ..writeln(
      '  $queryType sortBy$suffix({'
      'CindelSortOrder order = CindelSortOrder.ascending}) {',
    )
    ..writeln('    return sortBy($fieldLiteral, order: order);')
    ..writeln('  }')
    ..writeln()
    ..writeln('  $queryType sortBy${suffix}Desc() {')
    ..writeln(
      '    return sortBy($fieldLiteral, order: CindelSortOrder.descending);',
    )
    ..writeln('  }')
    ..writeln()
    ..writeln(
      '  $queryType thenBy$suffix({'
      'CindelSortOrder order = CindelSortOrder.ascending}) {',
    )
    ..writeln('    return thenBy($fieldLiteral, order: order);')
    ..writeln('  }')
    ..writeln()
    ..writeln('  $queryType thenBy${suffix}Desc() {')
    ..writeln(
      '    return thenBy($fieldLiteral, order: CindelSortOrder.descending);',
    )
    ..writeln('  }')
    ..writeln()
    ..writeln('  $queryType distinctBy$suffix() {')
    ..writeln('    return distinctBy($fieldLiteral);')
    ..writeln('  }')
    ..writeln()
    ..writeln(
      '  CindelPropertyQuery<${collection.dartName}, ${field.dartType}> '
      '${field.name}Property() {',
    )
    ..writeln(
      '    return property<${field.dartType}>('
      '$fieldLiteral${field.propertyDecodeArgument});',
    )
    ..writeln('  }');
}

String _stringLiteral(String value) => jsonEncode(value);

final class _CollectionInfo {
  _CollectionInfo({
    required this.dartName,
    required this.name,
    required this.accessorName,
    required this.schemaName,
    required this.idField,
    required this.fields,
    required this.embeddedTypes,
  });

  factory _CollectionInfo.from(
    ClassElement element,
    ConstantReader annotation,
  ) {
    final dartName = element.name ?? element.displayName;
    final fields = element.fields
        .where(_isPersistedFieldCandidate)
        .map(_FieldInfo.from)
        .whereType<_FieldInfo>()
        .toList(growable: false);

    if (fields.isEmpty) {
      throw InvalidGenerationSourceError(
        '@collection classes must declare at least one persisted field.',
        element: element,
      );
    }

    final idFields = fields.where((field) => field.isId).toList();
    if (idFields.length != 1) {
      throw InvalidGenerationSourceError(
        '@collection classes must declare exactly one field named `id`.',
        element: element,
      );
    }

    final hasDefaultConstructor = element.constructors.any(
      (constructor) =>
          constructor.name == 'new' && constructor.formalParameters.isEmpty,
    );
    if (!hasDefaultConstructor) {
      throw InvalidGenerationSourceError(
        '@collection classes need an unnamed constructor with no parameters.',
        element: element,
      );
    }

    final configuredName = annotation.peek('name')?.stringValue;
    final collectionName = configuredName == null || configuredName.isEmpty
        ? _lowerFirst(dartName)
        : configuredName;

    return _CollectionInfo(
      dartName: dartName,
      name: collectionName,
      accessorName: _accessorName(collectionName, dartName),
      schemaName: '${dartName}Schema',
      idField: idFields.single,
      fields: fields,
      embeddedTypes: _collectEmbeddedTypes(fields),
    );
  }

  final String dartName;
  final String name;
  final String accessorName;
  final String schemaName;
  final _FieldInfo idField;
  final List<_FieldInfo> fields;
  final List<_EmbeddedInfo> embeddedTypes;

  String get queryWhereName => '${dartName}QueryWhere';

  String get queryFilterName => '${dartName}QueryFilter';

  Iterable<_FieldInfo> get indexedFields {
    return fields.where((field) => field.isIndexed);
  }

  List<_FieldInfo> get binaryFields {
    return fields.toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));
  }
}

void _emitFilterMethods(
  StringBuffer buffer,
  _CollectionInfo collection,
  _FieldInfo field,
) {
  final queryType = 'CindelQuery<${collection.dartName}>';
  final fieldLiteral = _stringLiteral(field.name);
  final methodPrefix = field.name;

  buffer
    ..writeln()
    ..writeln('  $queryType ${methodPrefix}EqualTo(${field.dartType} value) {')
    ..writeln('    return _query.whereMatches(')
    ..writeln(
      '      CindelFilter.field($fieldLiteral).equalTo('
      '${field.toStoredValueExpression('value', nullableInput: field.isNullable)}),',
    )
    ..writeln('    );')
    ..writeln('  }');

  if (field.supportsComparableFilters) {
    final valueType = field.nonNullableDartType;
    final lower = field.toStoredValueExpression('lower', nullableInput: true);
    final upper = field.toStoredValueExpression('upper', nullableInput: true);
    buffer
      ..writeln()
      ..writeln('  $queryType ${methodPrefix}GreaterThan($valueType value) {')
      ..writeln('    return _query.whereMatches(')
      ..writeln(
        '      CindelFilter.field($fieldLiteral).greaterThan('
        '${field.toStoredValueExpression('value')}),',
      )
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln(
        '  $queryType ${methodPrefix}GreaterThanOrEqualTo($valueType value) {',
      )
      ..writeln('    return _query.whereMatches(')
      ..writeln(
        '      CindelFilter.field($fieldLiteral).greaterThanOrEqualTo('
        '${field.toStoredValueExpression('value')}),',
      )
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $queryType ${methodPrefix}LessThan($valueType value) {')
      ..writeln('    return _query.whereMatches(')
      ..writeln(
        '      CindelFilter.field($fieldLiteral).lessThan('
        '${field.toStoredValueExpression('value')}),',
      )
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln(
        '  $queryType ${methodPrefix}LessThanOrEqualTo($valueType value) {',
      )
      ..writeln('    return _query.whereMatches(')
      ..writeln(
        '      CindelFilter.field($fieldLiteral).lessThanOrEqualTo('
        '${field.toStoredValueExpression('value')}),',
      )
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln(
        '  $queryType ${methodPrefix}Between('
        '$valueType? lower, $valueType? upper) {',
      )
      ..writeln('    return _query.whereMatches(')
      ..writeln(
        '      CindelFilter.field($fieldLiteral).between($lower, $upper),',
      )
      ..writeln('    );')
      ..writeln('  }');
  }

  if (field.nonNullableDartType == 'String' &&
      field.indexType == CindelIndexType.value) {
    buffer
      ..writeln()
      ..writeln('  $queryType ${methodPrefix}Contains(String value) {')
      ..writeln('    return _query.whereMatches(')
      ..writeln('      CindelFilter.field($fieldLiteral).contains(value),')
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $queryType ${methodPrefix}StartsWith(String value) {')
      ..writeln('    return _query.whereMatches(')
      ..writeln('      CindelFilter.field($fieldLiteral).startsWith(value),')
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $queryType ${methodPrefix}EndsWith(String value) {')
      ..writeln('    return _query.whereMatches(')
      ..writeln('      CindelFilter.field($fieldLiteral).endsWith(value),')
      ..writeln('    );')
      ..writeln('  }');
  }
}

final class _FieldInfo {
  _FieldInfo({
    required this.name,
    required this.dartType,
    required this.type,
    required this.isId,
    required this.isIndexed,
    required this.isIndexUnique,
    required this.indexCaseSensitive,
    required this.indexType,
  });

  static _FieldInfo? from(FieldElement element) {
    if (_ignoreChecker.hasAnnotationOf(element)) {
      return null;
    }

    final name = element.name ?? element.displayName;
    final dartType = element.type.getDisplayString();
    final type = _PersistedType.from(element, name, dartType);

    final index = _IndexInfo.from(element);
    if (index != null && type.isList) {
      throw InvalidGenerationSourceError(
        'Field `$name` uses @Index, but list indexes are not supported yet. '
        'Primitive lists can be persisted without an index.',
        element: element,
      );
    }
    if (index != null &&
        !type.supportsCaseInsensitiveIndex &&
        !index.caseSensitive) {
      throw InvalidGenerationSourceError(
        'Field `$name` uses caseSensitive: false, but only String indexes '
        'support case-insensitive lookup.',
        element: element,
      );
    }
    if (index?.type == CindelIndexType.words && !type.supportsWordIndex) {
      throw InvalidGenerationSourceError(
        'Field `$name` uses a word index, but word indexes require String '
        'fields.',
        element: element,
      );
    }

    return _FieldInfo(
      name: name,
      dartType: dartType,
      type: type,
      isId: name == 'id',
      isIndexed: index != null,
      isIndexUnique: index?.unique ?? false,
      indexCaseSensitive: index?.caseSensitive ?? true,
      indexType: index?.type ?? CindelIndexType.value,
    );
  }

  final String name;
  final String dartType;
  final _PersistedType type;
  final bool isId;
  final bool isIndexed;
  final bool isIndexUnique;
  final bool indexCaseSensitive;
  final CindelIndexType indexType;

  String get nonNullableDartType {
    return dartType.endsWith('?')
        ? dartType.substring(0, dartType.length - 1)
        : dartType;
  }

  String get toDocumentExpression {
    return type.toStoredExpression('object.$name');
  }

  String fromDocumentExpression(String fieldLiteral) {
    return type.fromStoredExpression('document[$fieldLiteral]');
  }

  String fromStoredValueExpression(String expression) {
    return type.fromStoredExpression(expression);
  }

  String toStoredValueExpression(
    String variable, {
    bool nullableInput = false,
  }) {
    return type.toStoredExpression(
      variable,
      nullableInput: nullableInput,
      nullableCast: false,
    );
  }

  String get propertyDecodeArgument {
    final decoder = type.decodeClosure;
    return decoder == null ? '' : ', decode: $decoder';
  }

  bool get supportsRangeQueries {
    return indexType == CindelIndexType.value && type.supportsRangeQueries;
  }

  bool get supportsComparableFilters {
    return type.supportsComparableFilters;
  }

  bool get isNullable => dartType.endsWith('?');
}

final class _IndexInfo {
  const _IndexInfo({
    required this.unique,
    required this.caseSensitive,
    required this.type,
  });

  static _IndexInfo? from(FieldElement element) {
    final annotation = _indexChecker.firstAnnotationOf(
      element,
      throwOnUnresolved: false,
    );
    if (annotation == null) {
      return null;
    }
    final reader = ConstantReader(annotation);
    final typeIndex = reader
        .peek('type')
        ?.objectValue
        .getField('index')
        ?.toIntValue();
    final type = switch (typeIndex) {
      1 => CindelIndexType.hash,
      2 => CindelIndexType.words,
      _ => CindelIndexType.value,
    };
    final caseSensitive = reader.peek('caseSensitive')?.boolValue ?? true;
    return _IndexInfo(
      unique: reader.peek('unique')?.boolValue ?? false,
      caseSensitive: caseSensitive,
      type: type,
    );
  }

  final bool unique;
  final bool caseSensitive;
  final CindelIndexType type;
}

final class _EmbeddedInfo {
  const _EmbeddedInfo({required this.dartName, required this.fields});

  factory _EmbeddedInfo.from(ClassElement element) {
    if (element.isAbstract) {
      throw InvalidGenerationSourceError(
        '@Embedded classes must be concrete.',
        element: element,
      );
    }

    final hasDefaultConstructor = element.constructors.any(
      (constructor) =>
          constructor.name == 'new' && constructor.formalParameters.isEmpty,
    );
    if (!hasDefaultConstructor) {
      throw InvalidGenerationSourceError(
        '@Embedded classes need an unnamed constructor with no parameters.',
        element: element,
      );
    }

    return _EmbeddedInfo(
      dartName: element.name ?? element.displayName,
      fields: element.fields
          .where(_isPersistedFieldCandidate)
          .map(_EmbeddedFieldInfo.from)
          .whereType<_EmbeddedFieldInfo>()
          .toList(growable: false),
    );
  }

  static _EmbeddedInfo? fromType(DartType type) {
    final element = _embeddedElement(type);
    return element == null ? null : _EmbeddedInfo.from(element);
  }

  final String dartName;
  final List<_EmbeddedFieldInfo> fields;
}

final class _EmbeddedFieldInfo {
  const _EmbeddedFieldInfo({required this.name, required this.type});

  static _EmbeddedFieldInfo? from(FieldElement element) {
    if (_ignoreChecker.hasAnnotationOf(element)) {
      return null;
    }
    if (_indexChecker.hasAnnotationOf(element)) {
      throw InvalidGenerationSourceError(
        'Embedded field `${element.name}` uses @Index, but embedded indexes '
        'are not supported yet. Index the parent collection field instead.',
        element: element,
      );
    }

    final name = element.name ?? element.displayName;
    return _EmbeddedFieldInfo(
      name: name,
      type: _PersistedType.from(element, name, element.type.getDisplayString()),
    );
  }

  final String name;
  final _PersistedType type;

  String get toDocumentExpression {
    return type.toStoredExpression('object.$name');
  }

  String fromDocumentExpression(String fieldLiteral) {
    return type.fromStoredExpression('document[$fieldLiteral]');
  }
}

final class _PersistedType {
  const _PersistedType._({
    required this.dartType,
    required this.isNullable,
    required this.kind,
    this.enumInfo,
    this.embeddedInfo,
    this.elementType,
  });

  factory _PersistedType.from(
    FieldElement element,
    String fieldName,
    String dartType,
  ) {
    final enumInfo = _EnumInfo.from(element);
    final type = _PersistedType._fromDartType(
      type: element.type,
      dartType: dartType,
      isNullable: dartType.endsWith('?'),
      enumInfo: enumInfo,
    );
    if (type == null) {
      throw InvalidGenerationSourceError(
        'Field `$fieldName` has unsupported type `$dartType`. '
        'Cindel supports int, double, String, bool, DateTime, Duration, '
        'enums, embedded objects, nullable variants, and lists of those '
        'supported shapes.',
        element: element,
      );
    }
    return type;
  }

  static _PersistedType? _fromDartType({
    required DartType type,
    required String dartType,
    required bool isNullable,
    _EnumInfo? enumInfo,
  }) {
    final normalized = _normalizeDartType(dartType);
    final listElement = _listElementType(type);
    if (listElement != null) {
      final elementDisplay = listElement.getDisplayString();
      final elementEnumInfo = _EnumInfo.fromType(listElement, enumInfo);
      final elementType = _PersistedType._fromDartType(
        type: listElement,
        dartType: elementDisplay,
        isNullable: elementDisplay.endsWith('?'),
        enumInfo: elementEnumInfo,
      );
      if (elementType == null || elementType.isList) {
        return null;
      }
      return _PersistedType._(
        dartType: dartType,
        isNullable: isNullable,
        kind: _PersistedTypeKind.list,
        elementType: elementType,
      );
    }

    if (_primitiveTypes.contains(normalized)) {
      return _PersistedType._(
        dartType: dartType,
        isNullable: isNullable,
        kind: _PersistedTypeKind.primitive,
      );
    }
    if (normalized == 'DateTime') {
      return _PersistedType._(
        dartType: dartType,
        isNullable: isNullable,
        kind: _PersistedTypeKind.dateTime,
      );
    }
    if (normalized == 'Duration') {
      return _PersistedType._(
        dartType: dartType,
        isNullable: isNullable,
        kind: _PersistedTypeKind.duration,
      );
    }

    final resolvedEnum = enumInfo ?? _EnumInfo.fromType(type, null);
    if (resolvedEnum != null) {
      return _PersistedType._(
        dartType: dartType,
        isNullable: isNullable,
        kind: _PersistedTypeKind.enumeration,
        enumInfo: resolvedEnum,
      );
    }

    final embeddedInfo = _EmbeddedInfo.fromType(type);
    if (embeddedInfo != null) {
      return _PersistedType._(
        dartType: dartType,
        isNullable: isNullable,
        kind: _PersistedTypeKind.embedded,
        embeddedInfo: embeddedInfo,
      );
    }

    return null;
  }

  final String dartType;
  final bool isNullable;
  final _PersistedTypeKind kind;
  final _EnumInfo? enumInfo;
  final _EmbeddedInfo? embeddedInfo;
  final _PersistedType? elementType;

  bool get isList => kind == _PersistedTypeKind.list;

  bool get supportsCaseInsensitiveIndex {
    return kind == _PersistedTypeKind.primitive &&
        _normalizeDartType(dartType) == 'String';
  }

  bool get supportsWordIndex => supportsCaseInsensitiveIndex;

  bool get supportsRangeQueries {
    final normalized = _normalizeDartType(dartType);
    return kind == _PersistedTypeKind.primitive &&
            (normalized == 'int' ||
                normalized == 'double' ||
                normalized == 'String') ||
        kind == _PersistedTypeKind.dateTime ||
        kind == _PersistedTypeKind.duration;
  }

  bool get supportsComparableFilters {
    final normalized = _normalizeDartType(dartType);
    return kind == _PersistedTypeKind.primitive &&
            (normalized == 'int' || normalized == 'double') ||
        kind == _PersistedTypeKind.dateTime ||
        kind == _PersistedTypeKind.duration;
  }

  String? get decodeClosure {
    if (!needsDecode) {
      return null;
    }
    return '(value) => ${fromStoredExpression('value')}';
  }

  bool get needsDecode {
    return switch (kind) {
      _PersistedTypeKind.primitive => false,
      _PersistedTypeKind.dateTime ||
      _PersistedTypeKind.duration ||
      _PersistedTypeKind.enumeration ||
      _PersistedTypeKind.embedded ||
      _PersistedTypeKind.list => true,
    };
  }

  String toStoredExpression(
    String expression, {
    bool? nullableInput,
    bool nullableCast = true,
  }) {
    final allowsNull = nullableInput ?? isNullable;
    if (!allowsNull) {
      return _toStoredExpressionNonNull(expression);
    }
    if (kind == _PersistedTypeKind.primitive) {
      return expression;
    }
    return _toStoredExpressionNullable(expression, nullableCast: nullableCast);
  }

  String _toStoredExpressionNonNull(String expression) {
    return switch (kind) {
      _PersistedTypeKind.primitive => expression,
      _PersistedTypeKind.dateTime => '$expression.microsecondsSinceEpoch',
      _PersistedTypeKind.duration => '$expression.inMicroseconds',
      _PersistedTypeKind.enumeration => enumInfo!._toStoredExpression(
        expression,
      ),
      _PersistedTypeKind.embedded =>
        '_\$${embeddedInfo!.dartName}ToCindelEmbedded($expression)',
      _PersistedTypeKind.list =>
        '$expression.map((value) => '
            '${elementType!._toStoredExpressionNonNull('value')})'
            '.toList(growable: false)',
    };
  }

  String _toStoredExpressionNullable(
    String expression, {
    required bool nullableCast,
  }) {
    final embeddedExpression = nullableCast
        ? '$expression as ${embeddedInfo?.dartName}'
        : expression;
    return switch (kind) {
      _PersistedTypeKind.primitive => expression,
      _PersistedTypeKind.dateTime => '$expression?.microsecondsSinceEpoch',
      _PersistedTypeKind.duration => '$expression?.inMicroseconds',
      _PersistedTypeKind.enumeration => enumInfo!._toStoredExpressionNullable(
        expression,
      ),
      _PersistedTypeKind.embedded =>
        '$expression == null ? null : '
            '_\$${embeddedInfo!.dartName}ToCindelEmbedded('
            '$embeddedExpression)',
      _PersistedTypeKind.list =>
        '$expression?.map((value) => '
            '${elementType!._toStoredExpressionNonNull('value')})'
            '.toList(growable: false)',
    };
  }

  String fromStoredExpression(String expression) {
    final decoded = _fromStoredExpressionNonNull(expression);
    if (!isNullable) {
      return decoded;
    }
    return '$expression == null ? null : $decoded';
  }

  String _fromStoredExpressionNonNull(String expression) {
    return switch (kind) {
      _PersistedTypeKind.primitive => '$expression as $dartType',
      _PersistedTypeKind.dateTime =>
        'DateTime.fromMicrosecondsSinceEpoch($expression as int, isUtc: true)',
      _PersistedTypeKind.duration =>
        'Duration(microseconds: $expression as int)',
      _PersistedTypeKind.enumeration => enumInfo!._fromStoredExpression(
        expression,
      ),
      _PersistedTypeKind.embedded =>
        '_\$${embeddedInfo!.dartName}FromCindelEmbedded('
            '($expression as Map).cast<String, Object?>())',
      _PersistedTypeKind.list =>
        '($expression as List<Object?>)'
            '.map((value) => '
            '${elementType!._fromStoredExpressionNonNull('value')})'
            '.toList(growable: false)',
    };
  }
}

enum _PersistedTypeKind {
  primitive,
  dateTime,
  duration,
  enumeration,
  embedded,
  list,
}

final class _EnumInfo {
  const _EnumInfo({
    required this.enumType,
    required this.strategy,
    this.valueField,
  });

  static _EnumInfo? from(FieldElement element) {
    final enumElement = _enumElement(element.type);
    if (enumElement == null) {
      final annotation = _enumeratedChecker.firstAnnotationOf(
        element,
        throwOnUnresolved: false,
      );
      if (annotation != null) {
        throw InvalidGenerationSourceError(
          '@Enumerated can only be used on enum fields.',
          element: element,
        );
      }
      return null;
    }
    final annotation = _enumeratedChecker.firstAnnotationOf(
      element,
      throwOnUnresolved: false,
    );
    return _fromAnnotation(enumElement, annotation, element);
  }

  static _EnumInfo? fromType(DartType type, _EnumInfo? fallback) {
    final enumElement = _enumElement(type);
    if (enumElement == null) {
      return null;
    }
    if (fallback != null && fallback.enumType == enumElement.name) {
      return fallback;
    }
    return _EnumInfo(
      enumType: enumElement.name ?? enumElement.displayName,
      strategy: CindelEnumType.name,
    );
  }

  static _EnumInfo _fromAnnotation(
    EnumElement enumElement,
    DartObject? annotation,
    FieldElement field,
  ) {
    if (annotation == null) {
      return _EnumInfo(
        enumType: enumElement.name ?? enumElement.displayName,
        strategy: CindelEnumType.name,
      );
    }
    final reader = ConstantReader(annotation);
    final typeIndex = reader
        .peek('type')
        ?.objectValue
        .getField('index')
        ?.toIntValue();
    final strategy = switch (typeIndex) {
      1 => CindelEnumType.ordinal,
      2 => CindelEnumType.value,
      _ => CindelEnumType.name,
    };
    final valueField = reader.peek('valueField')?.stringValue;
    if (strategy == CindelEnumType.value) {
      if (valueField == null || valueField.trim().isEmpty) {
        throw InvalidGenerationSourceError(
          'Enum field `${field.name}` uses CindelEnumType.value but does not '
          'declare valueField.',
          element: field,
        );
      }
      final enumField = enumElement.fields
          .where((candidate) => candidate.name == valueField)
          .firstOrNull;
      if (enumField == null) {
        throw InvalidGenerationSourceError(
          'Enum `${enumElement.name}` does not declare a `$valueField` field.',
          element: field,
        );
      }
      final storedType = _normalizeDartType(enumField.type.getDisplayString());
      if (!_primitiveTypes.contains(storedType)) {
        throw InvalidGenerationSourceError(
          'Enum custom value `${enumElement.name}.$valueField` must be int, '
          'double, String, or bool.',
          element: field,
        );
      }
    }
    return _EnumInfo(
      enumType: enumElement.name ?? enumElement.displayName,
      strategy: strategy,
      valueField: valueField,
    );
  }

  final String enumType;
  final CindelEnumType strategy;
  final String? valueField;

  String _toStoredExpression(String expression) {
    return switch (strategy) {
      CindelEnumType.name => '$expression.name',
      CindelEnumType.ordinal => '$expression.index',
      CindelEnumType.value => '$expression.$valueField',
    };
  }

  String _toStoredExpressionNullable(String expression) {
    return switch (strategy) {
      CindelEnumType.name => '$expression?.name',
      CindelEnumType.ordinal => '$expression?.index',
      CindelEnumType.value => '$expression?.$valueField',
    };
  }

  String _fromStoredExpression(String expression) {
    return switch (strategy) {
      CindelEnumType.name => '$enumType.values.byName($expression as String)',
      CindelEnumType.ordinal => '$enumType.values[$expression as int]',
      CindelEnumType.value =>
        '$enumType.values.firstWhere((enumValue) => '
            'enumValue.$valueField == $expression)',
    };
  }
}

const _primitiveTypes = {'int', 'double', 'String', 'bool'};

DartType? _listElementType(DartType type) {
  if (type is! InterfaceType) {
    return null;
  }
  final elementName = type.element.name ?? type.element.displayName;
  if (elementName != 'List' || type.typeArguments.length != 1) {
    return null;
  }
  return type.typeArguments.single;
}

EnumElement? _enumElement(DartType type) {
  if (type is InterfaceType && type.element is EnumElement) {
    return type.element as EnumElement;
  }
  return null;
}

ClassElement? _embeddedElement(DartType type) {
  if (type is! InterfaceType || type.element is! ClassElement) {
    return null;
  }
  final element = type.element as ClassElement;
  return _embeddedChecker.hasAnnotationOf(element) ? element : null;
}

bool _isPersistedFieldCandidate(FieldElement field) {
  return !field.isStatic &&
      (field.isOriginDeclaration || field.isOriginDeclaringFormalParameter);
}

List<_EmbeddedInfo> _collectEmbeddedTypes(List<_FieldInfo> fields) {
  final embeddedTypes = <String, _EmbeddedInfo>{};
  for (final field in fields) {
    _collectEmbeddedTypesFrom(field.type, embeddedTypes);
  }
  return embeddedTypes.values.toList(growable: false);
}

void _collectEmbeddedTypesFrom(
  _PersistedType type,
  Map<String, _EmbeddedInfo> embeddedTypes,
) {
  if (type.kind == _PersistedTypeKind.list) {
    _collectEmbeddedTypesFrom(type.elementType!, embeddedTypes);
    return;
  }
  if (type.kind != _PersistedTypeKind.embedded) {
    return;
  }
  final embedded = type.embeddedInfo!;
  if (embeddedTypes.containsKey(embedded.dartName)) {
    return;
  }
  embeddedTypes[embedded.dartName] = embedded;
  for (final field in embedded.fields) {
    _collectEmbeddedTypesFrom(field.type, embeddedTypes);
  }
}

String _normalizeDartType(String dartType) {
  return dartType.endsWith('?')
      ? dartType.substring(0, dartType.length - 1)
      : dartType;
}

void _emitIndexedWhereMethods(
  StringBuffer buffer,
  _CollectionInfo collection,
  _FieldInfo field,
) {
  final queryType = 'CindelQuery<${collection.dartName}>';
  final valueType = field.nonNullableDartType;
  final fieldLiteral = _stringLiteral(field.name);

  if (field.indexType == CindelIndexType.words) {
    buffer
      ..writeln()
      ..writeln('  $queryType ${field.name}EqualTo(String word) {')
      ..writeln('    return ${field.name}WordEqualTo(word);')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $queryType ${field.name}StartsWith(String prefix) {')
      ..writeln('    return ${field.name}WordStartsWith(prefix);')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $queryType ${field.name}WordEqualTo(String word) {')
      ..writeln('    return CindelQuery.wordsContain(')
      ..writeln('      database: _collection.database,')
      ..writeln('      schema: ${collection.schemaName},')
      ..writeln('      field: $fieldLiteral,')
      ..writeln('      word: word,')
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $queryType ${field.name}WordStartsWith(String prefix) {')
      ..writeln('    return CindelQuery.wordsStartWith(')
      ..writeln('      database: _collection.database,')
      ..writeln('      schema: ${collection.schemaName},')
      ..writeln('      field: $fieldLiteral,')
      ..writeln('      prefix: prefix,')
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $queryType ${field.name}WordsContain(String word) {')
      ..writeln('    return ${field.name}WordEqualTo(word);')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $queryType ${field.name}WordsStartWith(String prefix) {')
      ..writeln('    return ${field.name}WordStartsWith(prefix);')
      ..writeln('  }');
    return;
  }

  buffer
    ..writeln()
    ..writeln('  $queryType ${field.name}EqualTo($valueType value) {')
    ..writeln('    return CindelQuery.equal(')
    ..writeln('      database: _collection.database,')
    ..writeln('      schema: ${collection.schemaName},')
    ..writeln('      field: $fieldLiteral,')
    ..writeln('      value: ${field.toStoredValueExpression('value')},')
    ..writeln('    );')
    ..writeln('  }');

  if (field.nonNullableDartType == 'String' &&
      field.indexType == CindelIndexType.value) {
    buffer
      ..writeln()
      ..writeln('  $queryType ${field.name}StartsWith(String prefix) {')
      ..writeln('    return CindelQuery.stringStartsWith(')
      ..writeln('      database: _collection.database,')
      ..writeln('      schema: ${collection.schemaName},')
      ..writeln('      field: $fieldLiteral,')
      ..writeln('      prefix: prefix,')
      ..writeln('    );')
      ..writeln('  }');
  }

  if (field.supportsRangeQueries) {
    buffer
      ..writeln()
      ..writeln(
        '  $queryType ${field.name}Between('
        '$valueType? lower, $valueType? upper) {',
      )
      ..writeln('    return CindelQuery.range(')
      ..writeln('      database: _collection.database,')
      ..writeln('      schema: ${collection.schemaName},')
      ..writeln('      field: $fieldLiteral,')
      ..writeln(
        '      lower: ${field.toStoredValueExpression('lower', nullableInput: true)},',
      )
      ..writeln(
        '      upper: ${field.toStoredValueExpression('upper', nullableInput: true)},',
      )
      ..writeln('    );')
      ..writeln('  }');
  }
}

String _lowerFirst(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toLowerCase() + value.substring(1);
}

String _upperFirst(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}

String _accessorName(String collectionName, String dartName) {
  return _isDartIdentifier(collectionName)
      ? collectionName
      : _lowerFirst(dartName);
}

bool _isDartIdentifier(String value) {
  return RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(value);
}
