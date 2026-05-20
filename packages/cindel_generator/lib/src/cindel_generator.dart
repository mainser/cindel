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
    ..writeln(');')
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
    ..writeln('}');

  return buffer.toString();
}

String _stringLiteral(String value) => jsonEncode(value);

final class _CollectionInfo {
  _CollectionInfo({
    required this.dartName,
    required this.name,
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
      schemaName: '${dartName}Schema',
      idField: idFields.single,
      fields: fields,
    );
  }

  final String dartName;
  final String name;
  final String schemaName;
  final _FieldInfo idField;
  final List<_FieldInfo> fields;
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

String _lowerFirst(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toLowerCase() + value.substring(1);
}
