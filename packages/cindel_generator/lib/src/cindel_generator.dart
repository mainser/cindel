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
      ..writeln('      binaryType: ${_stringLiteral(field.binaryType)},')
      ..writeln('      isId: ${field.isId},')
      ..writeln('      isIndexed: ${field.isIndexed},')
      ..writeln('      isIndexUnique: ${field.isIndexUnique},')
      ..writeln('      indexCaseSensitive: ${field.indexCaseSensitive},')
      ..writeln('      indexType: CindelIndexType.${field.indexType.name},')
      ..writeln('    ),');
  }

  buffer
    ..writeln('  ],')
    ..writeln('  compositeIndexes: <CindelCompositeIndexSchema>[');

  for (final index in collection.compositeIndexes) {
    buffer
      ..writeln('    CindelCompositeIndexSchema(')
      ..writeln('      name: ${_stringLiteral(index.name)},')
      ..writeln('      fields: <String>[')
      ..writeln(
        '        ${index.fields.map((field) => _stringLiteral(field.name)).join(', ')},',
      )
      ..writeln('      ],')
      ..writeln('      isUnique: ${index.isUnique},')
      ..writeln('      caseSensitive: ${index.caseSensitive},')
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
    );
  if (collection.supportsNativeWriter) {
    buffer.writeln(
      '  writeNativeDocument: '
      '_\$${collection.dartName}WriteCindelNativeDocument,',
    );
  }
  if (collection.supportsNativeReader) {
    buffer.writeln(
      '  readNativeDocument: '
      '_\$${collection.dartName}ReadCindelNativeDocument,',
    );
  }
  buffer.writeln('  getId: _\$${collection.dartName}GetCindelId,');
  if (collection.canSetId) {
    buffer.writeln('  setId: _\$${collection.dartName}SetCindelId,');
  }
  buffer
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
  for (final index in collection.compositeIndexes) {
    _emitCompositeWhereMethod(buffer, collection, index);
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

  for (final field in collection.documentFields) {
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
    ..writeln(') {');
  _emitObjectHydration(
    buffer,
    collection,
    (field) => field.fromDocumentExpression(_stringLiteral(field.name)),
  );
  buffer
    ..writeln('}')
    ..writeln()
    ..writeln(
      'CindelBinaryDocumentBytes '
      '_\$${collection.dartName}ToCindelBinaryDocument('
      '${collection.dartName} object) {',
    )
    ..writeln('  return cindelEncodeSchemaBinaryDocument(')
    ..writeln('    <Object?>[');

  for (final field in collection.binaryFields) {
    buffer.writeln('    ${field.toDocumentExpression},');
  }

  buffer
    ..writeln('    ],')
    ..writeln('    const <CindelBinaryFieldType>[');

  for (final field in collection.binaryFields) {
    buffer.writeln('      CindelBinaryFieldType.${field.binaryFieldType},');
  }

  buffer
    ..writeln('    ],')
    ..writeln('  );')
    ..writeln('}')
    ..writeln()
    ..writeln(
      '${collection.dartName} _\$${collection.dartName}'
      'FromCindelBinaryDocument(CindelBinaryDocumentBytes bytes) {',
    )
    ..writeln('  final reader = CindelSchemaBinaryDocumentReader(')
    ..writeln('    bytes,')
    ..writeln('    staticSize: ${collection.binaryStaticSize},')
    ..writeln('  );');

  var staticOffset = 0;
  final binaryReadValues = <_FieldInfo, String>{};
  for (var index = 0; index < collection.binaryFields.length; index += 1) {
    final field = collection.binaryFields[index];
    final storedValue = 'field$index';
    buffer.writeln(
      '  final Object? $storedValue = '
      '${field.directBinaryReadExpression(index, staticOffset)};',
    );
    binaryReadValues[field] = field.fromStoredValueExpression(storedValue);
    staticOffset += field.binaryStaticSize;
  }

  _emitObjectHydration(
    buffer,
    collection,
    (field) => field.isId ? 'autoIncrement' : binaryReadValues[field]!,
  );
  buffer
    ..writeln('}')
    ..writeln();

  if (collection.supportsNativeWriter) {
    buffer
      ..writeln('void _\$${collection.dartName}WriteCindelNativeDocument(')
      ..writeln('  CindelNativeDocumentWriter writer,')
      ..writeln('  ${collection.dartName} object,')
      ..writeln(') {');
    for (
      var index = 0;
      index < collection.nativeBinaryFields.length;
      index += 1
    ) {
      buffer.write(
        collection.nativeBinaryFields[index].nativeWriteStatement(index),
      );
    }
    buffer
      ..writeln('}')
      ..writeln();
  }

  if (collection.supportsNativeReader) {
    buffer
      ..writeln(
        '${collection.dartName} _\$${collection.dartName}'
        'ReadCindelNativeDocument(',
      )
      ..writeln('  CindelNativeDocumentReader reader,')
      ..writeln('  int documentIndex,')
      ..writeln(') {');
    final nativeReadValues = <_FieldInfo, String>{};
    nativeReadValues[collection.idField] = 'reader.readId(documentIndex)';
    for (
      var index = 0;
      index < collection.nativeBinaryFields.length;
      index += 1
    ) {
      final field = collection.nativeBinaryFields[index];
      nativeReadValues[field] = field.nativeReadExpression(index);
    }
    _emitObjectHydration(
      buffer,
      collection,
      (field) => nativeReadValues[field]!,
    );
    buffer
      ..writeln('}')
      ..writeln();
  }

  buffer
    ..writeln(
      'int _\$${collection.dartName}GetCindelId('
      '${collection.dartName} object) {',
    )
    ..writeln('  return object.${collection.idField.name};')
    ..writeln('}');
  if (collection.canSetId) {
    buffer
      ..writeln()
      ..writeln(
        'void _\$${collection.dartName}SetCindelId('
        '${collection.dartName} object, int id) {',
      )
      ..writeln('  object.${collection.idField.name} = id;')
      ..writeln('}');
  }

  for (final embedded in collection.embeddedTypes) {
    _emitEmbeddedHelpers(buffer, embedded);
  }

  return buffer.toString();
}

void _emitObjectHydration(
  StringBuffer buffer,
  _CollectionInfo collection,
  String Function(_FieldInfo field) expressionFor,
) {
  final constructor = collection.constructor;
  if (constructor != null) {
    buffer..writeln('  return ${collection.dartName}(');
    for (final parameter in constructor.parameters) {
      final expression = expressionFor(parameter.field);
      if (parameter.isNamed) {
        buffer.writeln('    ${parameter.name}: $expression,');
      } else {
        buffer.writeln('    $expression,');
      }
    }
    buffer.writeln('  );');
    return;
  }

  buffer.writeln('  final object = ${collection.dartName}();');
  for (final field in collection.fields) {
    buffer.writeln('  object.${field.name} = ${expressionFor(field)};');
  }
  buffer.writeln('  return object;');
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
    required this.compositeIndexes,
    required this.embeddedTypes,
    required this.constructor,
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
    final fieldConstructor = _ConstructorInfo.from(element, fields);
    final needsConstructor = fields.any((field) => !field.isAssignable);
    if (!hasDefaultConstructor && fieldConstructor == null) {
      throw InvalidGenerationSourceError(
        '@collection classes need an unnamed constructor with no parameters '
        'or parameters for every persisted field.',
        element: element,
      );
    }
    if (needsConstructor && fieldConstructor == null) {
      throw InvalidGenerationSourceError(
        '@collection classes with final persisted fields need an unnamed '
        'constructor parameter for every persisted field.',
        element: element,
      );
    }

    final configuredName = annotation.peek('name')?.stringValue;
    final collectionName = configuredName == null || configuredName.isEmpty
        ? _lowerFirst(dartName)
        : configuredName;
    final compositeIndexes = _CompositeIndexInfo.fromAnnotation(
      annotation,
      fields,
      element,
    );

    return _CollectionInfo(
      dartName: dartName,
      name: collectionName,
      accessorName: _accessorName(collectionName, dartName),
      schemaName: '${dartName}Schema',
      idField: idFields.single,
      fields: fields,
      compositeIndexes: compositeIndexes,
      embeddedTypes: _collectEmbeddedTypes(fields),
      constructor: needsConstructor || !hasDefaultConstructor
          ? fieldConstructor
          : null,
    );
  }

  final String dartName;
  final String name;
  final String accessorName;
  final String schemaName;
  final _FieldInfo idField;
  final List<_FieldInfo> fields;
  final List<_CompositeIndexInfo> compositeIndexes;
  final List<_EmbeddedInfo> embeddedTypes;
  final _ConstructorInfo? constructor;

  String get queryWhereName => '${dartName}QueryWhere';

  String get queryFilterName => '${dartName}QueryFilter';

  Iterable<_FieldInfo> get indexedFields {
    return fields.where((field) => field.isIndexed);
  }

  List<_FieldInfo> get binaryFields {
    return fields.where((field) => !field.isId).toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));
  }

  List<_FieldInfo> get documentFields {
    return fields.where((field) => !field.isId).toList(growable: false);
  }

  List<_FieldInfo> get nativeBinaryFields {
    return binaryFields;
  }

  bool get supportsNativeWriter {
    return nativeBinaryFields.every((field) => field.supportsNativeWriter);
  }

  bool get supportsNativeReader {
    return nativeBinaryFields.every((field) => field.supportsNativeReader);
  }

  int get binaryStaticSize {
    return binaryFields.fold<int>(
      0,
      (size, field) => size + field.binaryStaticSize,
    );
  }

  bool get canSetId => idField.isAssignable;
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

final class _ConstructorInfo {
  const _ConstructorInfo(this.parameters);

  static _ConstructorInfo? from(ClassElement element, List<_FieldInfo> fields) {
    final constructors = element.constructors
        .where(
          (constructor) =>
              constructor.name == 'new' &&
              constructor.formalParameters.isNotEmpty,
        )
        .toList(growable: false);
    if (constructors.isEmpty) {
      return null;
    }
    final constructor = constructors.single;

    final fieldsByName = {for (final field in fields) field.name: field};
    final parameters = <_ConstructorParameterInfo>[];
    final seenFields = <String>{};
    for (final parameter in constructor.formalParameters) {
      final name = parameter.name ?? parameter.displayName;
      final field = fieldsByName[name];
      if (field == null) {
        throw InvalidGenerationSourceError(
          'Constructor parameter `$name` does not match a persisted field.',
          element: parameter,
        );
      }
      if (!seenFields.add(field.name)) {
        throw InvalidGenerationSourceError(
          'Constructor field `${field.name}` is declared more than once.',
          element: parameter,
        );
      }
      final parameterType = parameter.type.getDisplayString();
      if (parameterType != field.dartType) {
        throw InvalidGenerationSourceError(
          'Constructor parameter `$name` must have type `${field.dartType}`.',
          element: parameter,
        );
      }
      parameters.add(
        _ConstructorParameterInfo(
          name: name,
          field: field,
          isNamed: parameter.isNamed,
        ),
      );
    }

    final missingFields = fields
        .where((field) => !seenFields.contains(field.name))
        .map((field) => field.name)
        .toList(growable: false);
    if (missingFields.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'Constructor is missing persisted fields: ${missingFields.join(', ')}.',
        element: constructor,
      );
    }

    return _ConstructorInfo(parameters);
  }

  final List<_ConstructorParameterInfo> parameters;
}

final class _ConstructorParameterInfo {
  const _ConstructorParameterInfo({
    required this.name,
    required this.field,
    required this.isNamed,
  });

  final String name;
  final _FieldInfo field;
  final bool isNamed;
}

final class _FieldInfo {
  _FieldInfo({
    required this.name,
    required this.dartType,
    required this.type,
    required this.isAssignable,
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
    if (index != null &&
        type.isList &&
        index.type != CindelIndexType.multiEntry) {
      throw InvalidGenerationSourceError(
        'Field `$name` uses @Index, but list fields require '
        'CindelIndexType.multiEntry.',
        element: element,
      );
    }
    if (index?.type == CindelIndexType.multiEntry &&
        !type.supportsMultiEntryIndex) {
      throw InvalidGenerationSourceError(
        'Field `$name` uses a multi-entry index, but multi-entry indexes '
        'require primitive list fields.',
        element: element,
      );
    }
    if (index != null &&
        !type.supportsCaseInsensitiveIndex &&
        !(index.type == CindelIndexType.multiEntry &&
            type.supportsCaseInsensitiveMultiEntryIndex) &&
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
      isAssignable: !element.isFinal && !element.isConst,
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
  final bool isAssignable;
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

  String get binaryType => type.binaryType;

  String get binaryFieldType => type.binaryFieldType;

  bool get supportsNativeWriter {
    if (binaryType != 'list') {
      return supportsNativeReader;
    }
    return type.elementType?.supportsNativeWriterValue ?? false;
  }

  bool get supportsNativeReader {
    if (binaryType == 'list') {
      final element = type.elementType;
      return element != null &&
          element.kind == _PersistedTypeKind.primitive &&
          element.supportsNativeWriterValue;
    }
    return switch (binaryType) {
      'bool' || 'int' || 'double' || 'string' => true,
      _ => false,
    };
  }

  String nativeWriteStatement(int index) {
    if (binaryType == 'list') {
      return _nativeListWriteStatement(index);
    }
    final method = switch (binaryType) {
      'bool' => 'writeBool',
      'int' => 'writeInt',
      'double' => 'writeDouble',
      'string' => 'writeString',
      final type => throw StateError('Unsupported native writer type `$type`.'),
    };
    final castType = switch (binaryType) {
      'bool' => 'bool',
      'int' => 'int',
      'double' => 'double',
      'string' => 'String',
      final type => throw StateError('Unsupported native writer type `$type`.'),
    };
    final expression = 'object.$name';
    if (!isNullable) {
      return '  writer.$method($index, $expression);\n';
    }
    return '''
  {
    final value = $expression;
    if (value == null) {
      writer.writeNull($index);
    } else {
      writer.$method($index, value as $castType);
    }
  }
''';
  }

  String _nativeListWriteStatement(int index) {
    final element = type.elementType!;
    final method = switch (element.binaryType) {
      'bool' => 'writeBool',
      'int' => 'writeInt',
      'double' => 'writeDouble',
      'string' => 'writeString',
      final type => throw StateError(
        'Unsupported native list writer element type `$type`.',
      ),
    };
    final value = element.toStoredExpression('list[i]');
    final writeValue = element.isNullable
        ? '''
        final value = $value;
        if (value == null) {
          listWriter.writeNull(i);
        } else {
          listWriter.$method(i, value);
        }
'''
        : '        listWriter.$method(i, $value);\n';
    final expression = 'object.$name';
    if (!isNullable) {
      return '''
  {
    final list = $expression;
    final listWriter = writer.beginList($index, list.length);
    for (var i = 0; i < list.length; i += 1) {
$writeValue    }
    writer.endList(listWriter);
  }
''';
    }
    return '''
  {
    final list = $expression;
    if (list == null) {
      writer.writeNull($index);
    } else {
      final listWriter = writer.beginList($index, list.length);
      for (var i = 0; i < list.length; i += 1) {
$writeValue      }
      writer.endList(listWriter);
    }
  }
''';
  }

  String nativeReadExpression(int index) {
    if (binaryType == 'list') {
      return _nativeListReadExpression(index);
    }
    final method = switch (binaryType) {
      'bool' => 'readBool',
      'int' => 'readInt',
      'double' => 'readDouble',
      'string' => 'readString',
      final type => throw StateError('Unsupported native reader type `$type`.'),
    };
    return fromStoredValueExpression('reader.$method(documentIndex, $index)');
  }

  String _nativeListReadExpression(int index) {
    final element = type.elementType!;
    if (element.binaryType == 'string' && !element.isNullable) {
      if (isNullable) {
        return '''
reader.readStringList(documentIndex, $index)
''';
      }
      return '''
reader.readStringList(documentIndex, $index) ?? const <String>[]
''';
    }
    final method = switch (element.binaryType) {
      'bool' => 'readBool',
      'int' => 'readInt',
      'double' => 'readDouble',
      'string' => 'readString',
      final type => throw StateError(
        'Unsupported native list reader element type `$type`.',
      ),
    };
    final storedDefault = switch (element.binaryType) {
      'bool' => 'false',
      'int' => '0',
      'double' => '0.0',
      'string' => "''",
      final type => throw StateError(
        'Unsupported native list reader element type `$type`.',
      ),
    };
    final fillValue = element.isNullable ? 'null' : storedDefault;
    final storedValue = element.isNullable
        ? 'listReader.$method(0, i)'
        : 'listReader.$method(0, i) ?? $storedDefault';
    final readValue = element.fromStoredExpression(storedValue);
    if (isNullable) {
      return '''
(() {
  final listReader = reader.readList(documentIndex, $index);
  if (listReader == null) {
    return null;
  }
  try {
    final length = listReader.length;
    final list = List<${element.dartType}>.filled(
      length,
      $fillValue,
      growable: true,
    );
    for (var i = 0; i < length; i += 1) {
      list[i] = $readValue;
    }
    return list;
  } finally {
    listReader.release();
  }
})()
''';
    }
    return '''
(() {
  final listReader = reader.readList(documentIndex, $index);
  if (listReader == null) {
    return const <${element.dartType}>[];
  }
  try {
    final length = listReader.length;
    final list = List<${element.dartType}>.filled(
      length,
      $fillValue,
      growable: true,
    );
    for (var i = 0; i < length; i += 1) {
      list[i] = $readValue;
    }
    return list;
  } finally {
    listReader.release();
  }
})()
''';
  }

  int get binaryStaticSize {
    return switch (binaryType) {
      'bool' => 1,
      'int' || 'double' => 8,
      'string' || 'list' || 'object' => 3,
      final type => throw StateError('Unsupported binary type `$type`.'),
    };
  }

  String directBinaryReadExpression(int index, int staticOffset) {
    final method = switch (binaryType) {
      'bool' => 'readBool',
      'int' => 'readInt',
      'double' => 'readDouble',
      'string' => 'readString',
      'list' => 'readList',
      'object' => 'readObject',
      final type => throw StateError('Unsupported binary type `$type`.'),
    };
    return 'reader.$method($index, $staticOffset)';
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
      3 => CindelIndexType.multiEntry,
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

final class _CompositeIndexInfo {
  const _CompositeIndexInfo({
    required this.name,
    required this.fields,
    required this.isUnique,
    required this.caseSensitive,
  });

  static List<_CompositeIndexInfo> fromAnnotation(
    ConstantReader annotation,
    List<_FieldInfo> fields,
    ClassElement element,
  ) {
    final values =
        annotation.peek('indexes')?.listValue ?? const <DartObject>[];
    final byName = {for (final field in fields) field.name: field};
    final indexes = <_CompositeIndexInfo>[];
    final names = <String>{};
    for (final value in values) {
      final reader = ConstantReader(value);
      final fieldNames = reader
          .peek('fields')
          ?.listValue
          .map((value) => value.toStringValue())
          .whereType<String>()
          .toList(growable: false);
      if (fieldNames == null || fieldNames.length < 2) {
        throw InvalidGenerationSourceError(
          'Composite indexes require at least two fields.',
          element: element,
        );
      }
      final indexFields = <_FieldInfo>[];
      for (final fieldName in fieldNames) {
        final field = byName[fieldName];
        if (field == null) {
          throw InvalidGenerationSourceError(
            'Composite index references unknown field `$fieldName`.',
            element: element,
          );
        }
        if (field.type.isList) {
          throw InvalidGenerationSourceError(
            'Composite index field `$fieldName` cannot be a list.',
            element: element,
          );
        }
        indexFields.add(field);
      }
      final name = fieldNames.join('_');
      if (!names.add(name)) {
        throw InvalidGenerationSourceError(
          'Composite index `$name` is duplicated.',
          element: element,
        );
      }
      indexes.add(
        _CompositeIndexInfo(
          name: name,
          fields: indexFields,
          isUnique: reader.peek('unique')?.boolValue ?? false,
          caseSensitive: reader.peek('caseSensitive')?.boolValue ?? true,
        ),
      );
    }
    return indexes;
  }

  final String name;
  final List<_FieldInfo> fields;
  final bool isUnique;
  final bool caseSensitive;

  String get methodPrefix {
    return fields
        .map((field) => _upperFirst(field.name))
        .join()
        .replaceFirstMapped(
          RegExp(r'^[A-Z]'),
          (match) => match[0]!.toLowerCase(),
        );
  }
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

  bool get supportsMultiEntryIndex {
    final element = elementType;
    if (kind != _PersistedTypeKind.list || element == null) {
      return false;
    }
    return element.kind == _PersistedTypeKind.primitive ||
        element.kind == _PersistedTypeKind.dateTime ||
        element.kind == _PersistedTypeKind.duration ||
        element.kind == _PersistedTypeKind.enumeration;
  }

  bool get supportsCaseInsensitiveMultiEntryIndex {
    final element = elementType;
    return kind == _PersistedTypeKind.list &&
        element?.kind == _PersistedTypeKind.primitive &&
        _normalizeDartType(element!.dartType) == 'String';
  }

  String get listElementDartType {
    final element = elementType;
    if (element == null) {
      throw StateError('Not a list type.');
    }
    return element.dartType;
  }

  String listElementToStoredExpression(String expression) {
    final element = elementType;
    if (element == null) {
      throw StateError('Not a list type.');
    }
    return element.toStoredExpression(expression);
  }

  bool get supportsCaseInsensitiveIndex {
    return kind == _PersistedTypeKind.primitive &&
        _normalizeDartType(dartType) == 'String';
  }

  bool get supportsWordIndex => supportsCaseInsensitiveIndex;

  String get binaryType {
    return switch (kind) {
      _PersistedTypeKind.primitive => switch (_normalizeDartType(dartType)) {
        'bool' => 'bool',
        'int' => 'int',
        'double' => 'double',
        'String' => 'string',
        final type => throw StateError('Unsupported primitive `$type`.'),
      },
      _PersistedTypeKind.dateTime || _PersistedTypeKind.duration => 'int',
      _PersistedTypeKind.enumeration => enumInfo!.binaryType,
      _PersistedTypeKind.embedded => 'object',
      _PersistedTypeKind.list => 'list',
    };
  }

  String get binaryFieldType {
    return switch (binaryType) {
      'bool' => 'boolValue',
      'int' => 'intValue',
      'double' => 'doubleValue',
      'string' => 'stringValue',
      'list' => 'listValue',
      'object' => 'objectValue',
      final type => throw StateError('Unsupported binary type `$type`.'),
    };
  }

  bool get supportsNativeWriterValue {
    return switch (binaryType) {
      'bool' || 'int' || 'double' || 'string' => true,
      _ => false,
    };
  }

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
    this.valueFieldType,
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
    String? valueFieldType;
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
      valueFieldType = _normalizeDartType(enumField.type.getDisplayString());
      if (!_primitiveTypes.contains(valueFieldType)) {
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
      valueFieldType: valueFieldType,
    );
  }

  final String enumType;
  final CindelEnumType strategy;
  final String? valueField;
  final String? valueFieldType;

  String get binaryType {
    return switch (strategy) {
      CindelEnumType.name => 'string',
      CindelEnumType.ordinal => 'int',
      CindelEnumType.value => switch (valueFieldType) {
        'bool' => 'bool',
        'int' => 'int',
        'double' => 'double',
        'String' => 'string',
        final type => throw StateError('Unsupported enum value type `$type`.'),
      },
    };
  }

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
  if (field.isStatic) {
    return false;
  }
  final dynamic dynamicField = field;
  try {
    return dynamicField.isOriginDeclaration == true ||
        dynamicField.isOriginDeclaringFormalParameter == true;
  } on NoSuchMethodError {
    return dynamicField.isSynthetic != true;
  }
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

  if (field.indexType == CindelIndexType.multiEntry) {
    final elementType = field.type.listElementDartType;
    buffer
      ..writeln()
      ..writeln('  $queryType ${field.name}Contains($elementType value) {')
      ..writeln('    return CindelQuery.equal(')
      ..writeln('      database: _collection.database,')
      ..writeln('      schema: ${collection.schemaName},')
      ..writeln('      field: $fieldLiteral,')
      ..writeln(
        '      value: ${field.type.listElementToStoredExpression('value')},',
      )
      ..writeln('    );')
      ..writeln('  }');
    return;
  }

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

void _emitCompositeWhereMethod(
  StringBuffer buffer,
  _CollectionInfo collection,
  _CompositeIndexInfo index,
) {
  final queryType = 'CindelQuery<${collection.dartName}>';
  final parameters = index.fields
      .map((field) => '${field.nonNullableDartType} ${field.name}')
      .join(', ');
  final values = index.fields
      .map((field) => field.toStoredValueExpression(field.name))
      .join(', ');
  buffer
    ..writeln()
    ..writeln('  $queryType ${index.methodPrefix}EqualTo($parameters) {')
    ..writeln('    return CindelQuery.compositeEqual(')
    ..writeln('      database: _collection.database,')
    ..writeln('      schema: ${collection.schemaName},')
    ..writeln('      index: ${_stringLiteral(index.name)},')
    ..writeln('      values: <Object>[$values],')
    ..writeln('    );')
    ..writeln('  }');
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
