import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:cindel_annotations/cindel_annotations.dart';
import 'package:source_gen/source_gen.dart';

const _indexChecker = TypeChecker.typeNamed(
  Index,
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
      ..writeln('    ),');
  }

  buffer
    ..writeln('  ],')
    ..writeln('  toDocument: _\$${collection.dartName}ToCindelDocument,')
    ..writeln('  fromDocument: _\$${collection.dartName}FromCindelDocument,')
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
    buffer.writeln('    ${_stringLiteral(field.name)}: object.${field.name},');
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
      'document[${_stringLiteral(field.name)}] as ${field.dartType};',
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

  return buffer.toString();
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
  });

  factory _CollectionInfo.from(
    ClassElement element,
    ConstantReader annotation,
  ) {
    final dartName = element.name ?? element.displayName;
    final fields = element.fields
        .where((field) => !field.isSynthetic && !field.isStatic)
        .map(_FieldInfo.from)
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
    );
  }

  final String dartName;
  final String name;
  final String accessorName;
  final String schemaName;
  final _FieldInfo idField;
  final List<_FieldInfo> fields;

  String get queryWhereName => '${dartName}QueryWhere';

  String get queryFilterName => '${dartName}QueryFilter';

  Iterable<_FieldInfo> get indexedFields {
    return fields.where((field) => field.isIndexed);
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
    ..writeln('      CindelFilter.field($fieldLiteral).equalTo(value),')
    ..writeln('    );')
    ..writeln('  }');

  if (field.supportsNumericFilters) {
    final valueType = field.nonNullableDartType;
    buffer
      ..writeln()
      ..writeln('  $queryType ${methodPrefix}GreaterThan($valueType value) {')
      ..writeln('    return _query.whereMatches(')
      ..writeln('      CindelFilter.field($fieldLiteral).greaterThan(value),')
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln(
        '  $queryType ${methodPrefix}GreaterThanOrEqualTo($valueType value) {',
      )
      ..writeln('    return _query.whereMatches(')
      ..writeln(
        '      CindelFilter.field($fieldLiteral).greaterThanOrEqualTo(value),',
      )
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $queryType ${methodPrefix}LessThan($valueType value) {')
      ..writeln('    return _query.whereMatches(')
      ..writeln('      CindelFilter.field($fieldLiteral).lessThan(value),')
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln(
        '  $queryType ${methodPrefix}LessThanOrEqualTo($valueType value) {',
      )
      ..writeln('    return _query.whereMatches(')
      ..writeln(
        '      CindelFilter.field($fieldLiteral).lessThanOrEqualTo(value),',
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
        '      CindelFilter.field($fieldLiteral).between(lower, upper),',
      )
      ..writeln('    );')
      ..writeln('  }');
  }

  if (field.nonNullableDartType == 'String') {
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
    required this.isId,
    required this.isIndexed,
  });

  factory _FieldInfo.from(FieldElement element) {
    final name = element.name ?? element.displayName;
    final dartType = element.type.getDisplayString();
    if (!_isSupportedType(element.type)) {
      throw InvalidGenerationSourceError(
        'Field `$name` has unsupported type `$dartType`. '
        'Fase 4 supports int, double, String, bool, and nullable variants.',
        element: element,
      );
    }

    return _FieldInfo(
      name: name,
      dartType: dartType,
      isId: name == 'id',
      isIndexed: _indexChecker.hasAnnotationOf(
        element,
        throwOnUnresolved: false,
      ),
    );
  }

  final String name;
  final String dartType;
  final bool isId;
  final bool isIndexed;

  String get nonNullableDartType {
    return dartType.endsWith('?')
        ? dartType.substring(0, dartType.length - 1)
        : dartType;
  }

  bool get supportsRangeQueries {
    return nonNullableDartType == 'int' ||
        nonNullableDartType == 'double' ||
        nonNullableDartType == 'String';
  }

  bool get supportsNumericFilters {
    return nonNullableDartType == 'int' || nonNullableDartType == 'double';
  }
}

bool _isSupportedType(DartType type) {
  final display = type.getDisplayString();
  final normalized = display.endsWith('?')
      ? display.substring(0, display.length - 1)
      : display;
  return normalized == 'int' ||
      normalized == 'double' ||
      normalized == 'String' ||
      normalized == 'bool';
}

void _emitIndexedWhereMethods(
  StringBuffer buffer,
  _CollectionInfo collection,
  _FieldInfo field,
) {
  final queryType = 'CindelQuery<${collection.dartName}>';
  final valueType = field.nonNullableDartType;
  final fieldLiteral = _stringLiteral(field.name);

  buffer
    ..writeln()
    ..writeln('  $queryType ${field.name}EqualTo($valueType value) {')
    ..writeln('    return CindelQuery.equal(')
    ..writeln('      database: _collection.database,')
    ..writeln('      schema: ${collection.schemaName},')
    ..writeln('      field: $fieldLiteral,')
    ..writeln('      value: value,')
    ..writeln('    );')
    ..writeln('  }');

  if (field.nonNullableDartType == 'String') {
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
      ..writeln('      lower: lower,')
      ..writeln('      upper: upper,')
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

String _accessorName(String collectionName, String dartName) {
  return _isDartIdentifier(collectionName)
      ? collectionName
      : _lowerFirst(dartName);
}

bool _isDartIdentifier(String value) {
  return RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(value);
}
