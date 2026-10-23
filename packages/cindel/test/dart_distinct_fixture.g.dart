// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dart_distinct_fixture.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names

final DistinctRecordSchema = CindelCollectionSchema<DistinctRecord>(
  name: "distinctRecords",
  dartName: "DistinctRecord",
  idField: "dbId",
  fields: <CindelFieldSchema>[
    CindelFieldSchema(
      name: "dbId",
      dartType: "int",
      binaryType: "int",
      isId: true,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "name",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "email",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "displayName",
      dartType: "String?",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "tags",
      dartType: "List<String>",
      binaryType: "list",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "primaryRecipient",
      dartType: "Recipient?",
      binaryType: "object",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "recipients",
      dartType: "List<Recipient>?",
      binaryType: "list",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
  ],
  links: <CindelLinkSchema>[],
  compositeIndexes: <CindelCompositeIndexSchema>[],
  toDocument: _$DistinctRecordToCindelDocument,
  fromDocument: _$DistinctRecordFromCindelDocument,
  toBinaryDocument: _$DistinctRecordToCindelBinaryDocument,
  fromBinaryDocument: _$DistinctRecordFromCindelBinaryDocument,
  writeNativeDocument: _$DistinctRecordWriteCindelNativeDocument,
  readNativeDocument: _$DistinctRecordReadCindelNativeDocument,
  getId: _$DistinctRecordGetCindelId,
  setId: _$DistinctRecordSetCindelId,
);

extension DistinctRecordCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<DistinctRecord> get distinctRecords =>
      typedCollection(DistinctRecordSchema);
}

extension DistinctRecordCindelQueryAccess
    on CindelTypedCollection<DistinctRecord> {
  DistinctRecordQueryFilter filter() => DistinctRecordQueryFilter(
    CindelQuery.all(database: database, schema: DistinctRecordSchema),
  );
}

extension DistinctRecordCindelQueryFilterAccess on CindelQuery<DistinctRecord> {
  DistinctRecordQueryFilter filter() => DistinctRecordQueryFilter(this);
}

extension DistinctRecordCindelQueryModifierAccess
    on CindelQuery<DistinctRecord> {
  CindelQuery<DistinctRecord> sortByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("dbId", order: order);
  }

  CindelQuery<DistinctRecord> sortByDbIdDesc() {
    return sortBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> thenByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("dbId", order: order);
  }

  CindelQuery<DistinctRecord> thenByDbIdDesc() {
    return thenBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> distinctByDbId() {
    return distinctBy("dbId");
  }

  CindelPropertyQuery<DistinctRecord, int> dbIdProperty() {
    return property<int>("dbId");
  }

  CindelQuery<DistinctRecord> sortByName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("name", order: order);
  }

  CindelQuery<DistinctRecord> sortByNameDesc() {
    return sortBy("name", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> thenByName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("name", order: order);
  }

  CindelQuery<DistinctRecord> thenByNameDesc() {
    return thenBy("name", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> distinctByName() {
    return distinctBy("name");
  }

  CindelPropertyQuery<DistinctRecord, String> nameProperty() {
    return property<String>("name");
  }

  CindelQuery<DistinctRecord> sortByEmail({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("email", order: order);
  }

  CindelQuery<DistinctRecord> sortByEmailDesc() {
    return sortBy("email", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> thenByEmail({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("email", order: order);
  }

  CindelQuery<DistinctRecord> thenByEmailDesc() {
    return thenBy("email", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> distinctByEmail() {
    return distinctBy("email");
  }

  CindelPropertyQuery<DistinctRecord, String> emailProperty() {
    return property<String>("email");
  }

  CindelQuery<DistinctRecord> sortByDisplayName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("displayName", order: order);
  }

  CindelQuery<DistinctRecord> sortByDisplayNameDesc() {
    return sortBy("displayName", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> thenByDisplayName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("displayName", order: order);
  }

  CindelQuery<DistinctRecord> thenByDisplayNameDesc() {
    return thenBy("displayName", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> distinctByDisplayName() {
    return distinctBy("displayName");
  }

  CindelPropertyQuery<DistinctRecord, String?> displayNameProperty() {
    return property<String?>("displayName");
  }

  CindelQuery<DistinctRecord> sortByTags({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("tags", order: order);
  }

  CindelQuery<DistinctRecord> sortByTagsDesc() {
    return sortBy("tags", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> thenByTags({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("tags", order: order);
  }

  CindelQuery<DistinctRecord> thenByTagsDesc() {
    return thenBy("tags", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> distinctByTags() {
    return distinctBy("tags");
  }

  CindelPropertyQuery<DistinctRecord, List<String>> tagsProperty() {
    return property<List<String>>(
      "tags",
      decode: (value) => (value as List<Object?>)
          .map((value) => value as String)
          .toList(growable: false),
    );
  }

  CindelQuery<DistinctRecord> sortByPrimaryRecipient({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("primaryRecipient", order: order);
  }

  CindelQuery<DistinctRecord> sortByPrimaryRecipientDesc() {
    return sortBy("primaryRecipient", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> thenByPrimaryRecipient({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("primaryRecipient", order: order);
  }

  CindelQuery<DistinctRecord> thenByPrimaryRecipientDesc() {
    return thenBy("primaryRecipient", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> distinctByPrimaryRecipient() {
    return distinctBy("primaryRecipient");
  }

  CindelPropertyQuery<DistinctRecord, Recipient?> primaryRecipientProperty() {
    return property<Recipient?>(
      "primaryRecipient",
      decode: (value) => value == null
          ? null
          : _$RecipientFromCindelEmbedded(
              (value as Map).cast<String, Object?>(),
            ),
    );
  }

  CindelQuery<DistinctRecord> sortByRecipients({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("recipients", order: order);
  }

  CindelQuery<DistinctRecord> sortByRecipientsDesc() {
    return sortBy("recipients", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> thenByRecipients({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("recipients", order: order);
  }

  CindelQuery<DistinctRecord> thenByRecipientsDesc() {
    return thenBy("recipients", order: CindelSortOrder.descending);
  }

  CindelQuery<DistinctRecord> distinctByRecipients() {
    return distinctBy("recipients");
  }

  CindelPropertyQuery<DistinctRecord, List<Recipient>?> recipientsProperty() {
    return property<List<Recipient>?>(
      "recipients",
      decode: (value) => value == null
          ? null
          : (value as List<Object?>)
                .map(
                  (value) => _$RecipientFromCindelEmbedded(
                    (value as Map).cast<String, Object?>(),
                  ),
                )
                .toList(growable: false),
    );
  }
}

final class DistinctRecordQueryFilter {
  const DistinctRecordQueryFilter(this._query);

  final CindelQuery<DistinctRecord> _query;

  CindelQuery<DistinctRecord> dbIdEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").equalTo(value));
  }

  CindelQuery<DistinctRecord> dbIdGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").greaterThan(value));
  }

  CindelQuery<DistinctRecord> dbIdGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<DistinctRecord> dbIdLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").lessThan(value));
  }

  CindelQuery<DistinctRecord> dbIdLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<DistinctRecord> dbIdBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("dbId").between(lower, upper),
    );
  }

  CindelQuery<DistinctRecord> nameEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("name").equalTo(value));
  }

  CindelQuery<DistinctRecord> nameContains(String value) {
    return _query.whereMatches(CindelFilter.field("name").contains(value));
  }

  CindelQuery<DistinctRecord> nameStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("name").startsWith(value));
  }

  CindelQuery<DistinctRecord> nameEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("name").endsWith(value));
  }

  CindelQuery<DistinctRecord> emailEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("email").equalTo(value));
  }

  CindelQuery<DistinctRecord> emailContains(String value) {
    return _query.whereMatches(CindelFilter.field("email").contains(value));
  }

  CindelQuery<DistinctRecord> emailStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("email").startsWith(value));
  }

  CindelQuery<DistinctRecord> emailEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("email").endsWith(value));
  }

  CindelQuery<DistinctRecord> displayNameEqualTo(String? value) {
    return _query.whereMatches(
      CindelFilter.field("displayName").equalTo(value),
    );
  }

  CindelQuery<DistinctRecord> displayNameContains(String value) {
    return _query.whereMatches(
      CindelFilter.field("displayName").contains(value),
    );
  }

  CindelQuery<DistinctRecord> displayNameStartsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("displayName").startsWith(value),
    );
  }

  CindelQuery<DistinctRecord> displayNameEndsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("displayName").endsWith(value),
    );
  }

  CindelQuery<DistinctRecord> tagsEqualTo(List<String> value) {
    return _query.whereMatches(
      CindelFilter.field(
        "tags",
      ).equalTo(value.map((value) => value).toList(growable: false)),
    );
  }

  CindelQuery<DistinctRecord> tagsElementEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("tags").contains(value));
  }

  CindelQuery<DistinctRecord> tagsIsEmpty() {
    return _query.whereMatches(CindelFilter.field("tags").isEmpty());
  }

  CindelQuery<DistinctRecord> tagsIsNotEmpty() {
    return _query.whereMatches(CindelFilter.field("tags").isNotEmpty());
  }

  CindelQuery<DistinctRecord> tagsLengthEqualTo(int length) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthEqualTo(length),
    );
  }

  CindelQuery<DistinctRecord> tagsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthLessThan(length, include: include),
    );
  }

  CindelQuery<DistinctRecord> tagsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthGreaterThan(length, include: include),
    );
  }

  CindelQuery<DistinctRecord> tagsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthBetween(
        lower,
        upper,
        includeLower: includeLower,
        includeUpper: includeUpper,
      ),
    );
  }

  CindelQuery<DistinctRecord> primaryRecipientEqualTo(Recipient? value) {
    return _query.whereMatches(
      CindelFilter.field(
        "primaryRecipient",
      ).equalTo(value == null ? null : _$RecipientToCindelEmbedded(value)),
    );
  }

  CindelQuery<DistinctRecord> primaryRecipient(
    CindelFilterPredicate Function(
      DistinctRecordRecipientCindelEmbeddedFilter q,
    )
    filter,
  ) {
    return _query.whereMatches(
      filter(
        const DistinctRecordRecipientCindelEmbeddedFilter._(<String>[
          "primaryRecipient",
        ]),
      ),
    );
  }

  CindelQuery<DistinctRecord> recipientsEqualTo(List<Recipient>? value) {
    return _query.whereMatches(
      CindelFilter.field("recipients").equalTo(
        value
            ?.map((value) => _$RecipientToCindelEmbedded(value))
            .toList(growable: false),
      ),
    );
  }

  CindelQuery<DistinctRecord> recipientsElementEqualTo(Recipient value) {
    return _query.whereMatches(
      CindelFilter.field(
        "recipients",
      ).contains(_$RecipientToCindelEmbedded(value)),
    );
  }

  CindelQuery<DistinctRecord> recipientsIsEmpty() {
    return _query.whereMatches(CindelFilter.field("recipients").isEmpty());
  }

  CindelQuery<DistinctRecord> recipientsIsNotEmpty() {
    return _query.whereMatches(CindelFilter.field("recipients").isNotEmpty());
  }

  CindelQuery<DistinctRecord> recipientsLengthEqualTo(int length) {
    return _query.whereMatches(
      CindelFilter.field("recipients").lengthEqualTo(length),
    );
  }

  CindelQuery<DistinctRecord> recipientsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return _query.whereMatches(
      CindelFilter.field("recipients").lengthLessThan(length, include: include),
    );
  }

  CindelQuery<DistinctRecord> recipientsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return _query.whereMatches(
      CindelFilter.field(
        "recipients",
      ).lengthGreaterThan(length, include: include),
    );
  }

  CindelQuery<DistinctRecord> recipientsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return _query.whereMatches(
      CindelFilter.field("recipients").lengthBetween(
        lower,
        upper,
        includeLower: includeLower,
        includeUpper: includeUpper,
      ),
    );
  }

  CindelQuery<DistinctRecord> recipientsElement(
    CindelFilterPredicate Function(
      DistinctRecordRecipientCindelEmbeddedFilter q,
    )
    filter,
  ) {
    return _query.whereMatches(
      filter(
        const DistinctRecordRecipientCindelEmbeddedFilter._(<String>[
          "recipients",
        ]),
      ),
    );
  }

  CindelQuery<DistinctRecord> optional(
    bool enabled,
    CindelQuery<DistinctRecord> Function(DistinctRecordQueryFilter q) option,
  ) {
    return _query.optional(
      enabled,
      (query) => option(DistinctRecordQueryFilter(query)),
    );
  }

  CindelQuery<DistinctRecord> anyOf<E>(
    Iterable<E> items,
    CindelQuery<DistinctRecord> Function(DistinctRecordQueryFilter q, E item)
    option,
  ) {
    return _query.anyOf(
      items,
      (query, item) => option(DistinctRecordQueryFilter(query), item),
    );
  }

  CindelQuery<DistinctRecord> allOf<E>(
    Iterable<E> items,
    CindelQuery<DistinctRecord> Function(DistinctRecordQueryFilter q, E item)
    option,
  ) {
    return _query.allOf(
      items,
      (query, item) => option(DistinctRecordQueryFilter(query), item),
    );
  }
}

final class DistinctRecordRecipientCindelEmbeddedFilter {
  const DistinctRecordRecipientCindelEmbeddedFilter._(this._path);

  final List<String> _path;

  CindelFilterPredicate nameEqualTo(String? value) {
    return CindelFilter.path(<String>[..._path, "name"]).equalTo(value);
  }

  CindelFilterPredicate nameContains(String value) {
    return CindelFilter.path(<String>[..._path, "name"]).contains(value);
  }

  CindelFilterPredicate nameStartsWith(String value) {
    return CindelFilter.path(<String>[..._path, "name"]).startsWith(value);
  }

  CindelFilterPredicate nameEndsWith(String value) {
    return CindelFilter.path(<String>[..._path, "name"]).endsWith(value);
  }

  CindelFilterPredicate addressEqualTo(String? value) {
    return CindelFilter.path(<String>[..._path, "address"]).equalTo(value);
  }

  CindelFilterPredicate addressContains(String value) {
    return CindelFilter.path(<String>[..._path, "address"]).contains(value);
  }

  CindelFilterPredicate addressStartsWith(String value) {
    return CindelFilter.path(<String>[..._path, "address"]).startsWith(value);
  }

  CindelFilterPredicate addressEndsWith(String value) {
    return CindelFilter.path(<String>[..._path, "address"]).endsWith(value);
  }

  CindelFilterPredicate metadataEqualTo(RecipientMetadata? value) {
    return CindelFilter.path(<String>[..._path, "metadata"]).equalTo(
      value == null ? null : _$RecipientMetadataToCindelEmbedded(value),
    );
  }

  CindelFilterPredicate metadata(
    CindelFilterPredicate Function(
      DistinctRecordRecipientMetadataCindelEmbeddedFilter q,
    )
    filter,
  ) {
    return filter(
      DistinctRecordRecipientMetadataCindelEmbeddedFilter._(<String>[
        ..._path,
        "metadata",
      ]),
    );
  }
}

final class DistinctRecordRecipientMetadataCindelEmbeddedFilter {
  const DistinctRecordRecipientMetadataCindelEmbeddedFilter._(this._path);

  final List<String> _path;

  CindelFilterPredicate labelEqualTo(String? value) {
    return CindelFilter.path(<String>[..._path, "label"]).equalTo(value);
  }

  CindelFilterPredicate labelContains(String value) {
    return CindelFilter.path(<String>[..._path, "label"]).contains(value);
  }

  CindelFilterPredicate labelStartsWith(String value) {
    return CindelFilter.path(<String>[..._path, "label"]).startsWith(value);
  }

  CindelFilterPredicate labelEndsWith(String value) {
    return CindelFilter.path(<String>[..._path, "label"]).endsWith(value);
  }
}

Map<String, Object?> _$DistinctRecordToCindelDocument(DistinctRecord object) {
  return <String, Object?>{
    "name": object.name,
    "email": object.email,
    "displayName": object.displayName,
    "tags": object.tags.map((value) => value).toList(growable: false),
    "primaryRecipient": object.primaryRecipient == null
        ? null
        : _$RecipientToCindelEmbedded(object.primaryRecipient as Recipient),
    "recipients": object.recipients
        ?.map((value) => _$RecipientToCindelEmbedded(value))
        .toList(growable: false),
  };
}

DistinctRecord _$DistinctRecordFromCindelDocument(
  Map<String, Object?> document,
) {
  final object = DistinctRecord();
  object.dbId = document["dbId"] as int;
  object.name = document["name"] as String;
  object.email = document["email"] as String;
  object.displayName = document["displayName"] == null
      ? null
      : document["displayName"] as String?;
  object.tags = (document["tags"] as List<Object?>)
      .map((value) => value as String)
      .toList(growable: false);
  object.primaryRecipient = document["primaryRecipient"] == null
      ? null
      : _$RecipientFromCindelEmbedded(
          (document["primaryRecipient"] as Map).cast<String, Object?>(),
        );
  object.recipients = document["recipients"] == null
      ? null
      : (document["recipients"] as List<Object?>)
            .map(
              (value) => _$RecipientFromCindelEmbedded(
                (value as Map).cast<String, Object?>(),
              ),
            )
            .toList(growable: false);
  return object;
}

CindelBinaryDocumentBytes _$DistinctRecordToCindelBinaryDocument(
  DistinctRecord object,
) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[
      object.displayName,
      object.email,
      object.name,
      object.primaryRecipient == null
          ? null
          : _$RecipientToCindelEmbedded(object.primaryRecipient as Recipient),
      object.recipients
          ?.map((value) => _$RecipientToCindelEmbedded(value))
          .toList(growable: false),
      object.tags.map((value) => value).toList(growable: false),
    ],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.objectValue,
      CindelBinaryFieldType.listValue,
      CindelBinaryFieldType.listValue,
    ],
  );
}

DistinctRecord _$DistinctRecordFromCindelBinaryDocument(
  CindelBinaryDocumentBytes bytes,
) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 18);
  final Object? field0 = reader.readString(0, 0);
  final Object? field1 = reader.readString(1, 3);
  final Object? field2 = reader.readString(2, 6);
  final Object? field3 = reader.readObject(3, 9);
  final Object? field4 = reader.readList(4, 12);
  final Object? field5 = reader.readList(5, 15);
  final object = DistinctRecord();
  object.dbId = autoIncrement;
  object.name = field2 as String;
  object.email = field1 as String;
  object.displayName = field0 == null ? null : field0 as String?;
  object.tags = (field5 as List<Object?>)
      .map((value) => value as String)
      .toList(growable: false);
  object.primaryRecipient = field3 == null
      ? null
      : _$RecipientFromCindelEmbedded((field3 as Map).cast<String, Object?>());
  object.recipients = field4 == null
      ? null
      : (field4 as List<Object?>)
            .map(
              (value) => _$RecipientFromCindelEmbedded(
                (value as Map).cast<String, Object?>(),
              ),
            )
            .toList(growable: false);
  return object;
}

void _$DistinctRecordWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  DistinctRecord object,
) {
  {
    final value = object.displayName;
    if (value == null) {
      writer.writeNull(0);
    } else {
      writer.writeString(0, value);
    }
  }
  writer.writeString(1, object.email);
  writer.writeString(2, object.name);
  {
    final value = object.primaryRecipient;
    if (value == null) {
      writer.writeNull(3);
    } else {
      cindelWriteNativeObject<Recipient>(
        writer,
        3,
        _$RecipientCindelNativeFieldNames,
        value,
        _$RecipientWriteCindelNativeEmbedded,
        _$RecipientToCindelEmbedded,
      );
    }
  }
  {
    final list = object.recipients;
    if (list == null) {
      writer.writeNull(4);
    } else {
      cindelWriteNativeObjectList<Recipient>(
        writer,
        4,
        _$RecipientCindelNativeFieldNames,
        list,
        _$RecipientWriteCindelNativeEmbedded,
        _$RecipientToCindelEmbedded,
      );
    }
  }
  cindelWriteNativeStringList(writer, 5, object.tags);
}

DistinctRecord _$DistinctRecordReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = DistinctRecord();
  object.dbId = reader.readId(documentIndex);
  object.name = reader.readString(documentIndex, 2) as String;
  object.email = reader.readString(documentIndex, 1) as String;
  object.displayName = reader.readString(documentIndex, 0);
  object.tags = reader.readStringList(documentIndex, 5) ?? const <String>[];
  object.primaryRecipient = cindelReadNativeObject<Recipient>(
    reader,
    documentIndex,
    3,
    _$RecipientCindelNativeFieldNames,
    _$RecipientReadCindelNativeEmbedded,
    _$RecipientFromCindelEmbedded,
  );
  object.recipients = (() {
    final value = cindelReadNativeObjectList<Recipient>(
      reader,
      documentIndex,
      4,
      _$RecipientCindelNativeFieldNames,
      _$RecipientReadCindelNativeEmbedded,
      _$RecipientFromCindelEmbedded,
    );
    return value == null ? null : value.cast<Recipient>();
  })();
  return object;
}

int _$DistinctRecordGetCindelId(DistinctRecord object) {
  return object.dbId;
}

void _$DistinctRecordSetCindelId(DistinctRecord object, int id) {
  object.dbId = id;
}

const _$RecipientCindelNativeFieldNames = <String>[
  "name",
  "address",
  "metadata",
];

Map<String, Object?> _$RecipientToCindelEmbedded(Recipient object) {
  return <String, Object?>{
    "name": object.name,
    "address": object.address,
    "metadata": object.metadata == null
        ? null
        : _$RecipientMetadataToCindelEmbedded(
            object.metadata as RecipientMetadata,
          ),
  };
}

Recipient _$RecipientFromCindelEmbedded(Map<String, Object?> document) {
  final object = Recipient();
  object.name = document["name"] == null ? null : document["name"] as String?;
  object.address = document["address"] == null
      ? null
      : document["address"] as String?;
  object.metadata = document["metadata"] == null
      ? null
      : _$RecipientMetadataFromCindelEmbedded(
          (document["metadata"] as Map).cast<String, Object?>(),
        );
  return object;
}

void _$RecipientWriteCindelNativeEmbedded(
  CindelNativeDocumentWriter writer,
  Recipient object,
) {
  {
    final value = object.name;
    if (value == null) {
      writer.writeNull(0);
    } else {
      writer.writeString(0, value);
    }
  }
  {
    final value = object.address;
    if (value == null) {
      writer.writeNull(1);
    } else {
      writer.writeString(1, value);
    }
  }
  {
    final value = object.metadata;
    if (value == null) {
      writer.writeNull(2);
    } else {
      cindelWriteNativeObject<RecipientMetadata>(
        writer,
        2,
        _$RecipientMetadataCindelNativeFieldNames,
        value,
        _$RecipientMetadataWriteCindelNativeEmbedded,
        _$RecipientMetadataToCindelEmbedded,
      );
    }
  }
}

Recipient _$RecipientReadCindelNativeEmbedded(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = Recipient();
  object.name = reader.readString(documentIndex, 0);
  object.address = reader.readString(documentIndex, 1);
  object.metadata = cindelReadNativeObject<RecipientMetadata>(
    reader,
    documentIndex,
    2,
    _$RecipientMetadataCindelNativeFieldNames,
    _$RecipientMetadataReadCindelNativeEmbedded,
    _$RecipientMetadataFromCindelEmbedded,
  );
  return object;
}

const _$RecipientMetadataCindelNativeFieldNames = <String>["label"];

Map<String, Object?> _$RecipientMetadataToCindelEmbedded(
  RecipientMetadata object,
) {
  return <String, Object?>{"label": object.label};
}

RecipientMetadata _$RecipientMetadataFromCindelEmbedded(
  Map<String, Object?> document,
) {
  final object = RecipientMetadata();
  object.label = document["label"] == null
      ? null
      : document["label"] as String?;
  return object;
}

void _$RecipientMetadataWriteCindelNativeEmbedded(
  CindelNativeDocumentWriter writer,
  RecipientMetadata object,
) {
  {
    final value = object.label;
    if (value == null) {
      writer.writeNull(0);
    } else {
      writer.writeString(0, value);
    }
  }
}

RecipientMetadata _$RecipientMetadataReadCindelNativeEmbedded(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = RecipientMetadata();
  object.label = reader.readString(documentIndex, 0);
  return object;
}
