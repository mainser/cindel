import 'package:cindel/cindel.dart';

// Small schema with the same serializers/bindings emitted by the generator.
final class BackupNode {
  BackupNode(this.dbId, {int? code, this.payload = ''}) : code = code ?? dbId;
  int dbId;
  int code;
  String payload;
  final children = CindelLinks<BackupNode>();
  final parent = CindelLink<BackupNode>();
  final owners = CindelLinks<BackupNode>();
}

final backupNodeSchema = CindelCollectionSchema<BackupNode>(
  name: 'backup_nodes',
  dartName: 'BackupNode',
  idField: 'dbId',
  fields: const [
    CindelFieldSchema(
      name: 'dbId',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'code',
      dartType: 'int',
      binaryType: 'int',
      isId: false,
      isIndexed: true,
      isIndexUnique: true,
    ),
    CindelFieldSchema(
      name: 'payload',
      dartType: 'String',
      binaryType: 'string',
      isId: false,
      isIndexed: false,
    ),
  ],
  links: const [
    CindelLinkSchema(
      name: 'children',
      dartName: 'children',
      targetCollection: 'backup_nodes',
      isToMany: true,
      isBacklink: false,
    ),
    CindelLinkSchema(
      name: 'parent',
      dartName: 'parent',
      targetCollection: 'backup_nodes',
      isToMany: false,
      isBacklink: false,
    ),
    CindelLinkSchema(
      name: 'owners',
      dartName: 'owners',
      targetCollection: 'backup_nodes',
      isToMany: true,
      isBacklink: true,
      backlinkTo: 'children',
    ),
  ],
  toDocument: (node) => {
    'dbId': node.dbId,
    'code': node.code,
    'payload': node.payload,
  },
  fromDocument: (document) => BackupNode(
    document['dbId']! as int,
    code: document['code']! as int,
    payload: document['payload']! as String,
  ),
  toBinaryDocument: (node) => cindelEncodeSchemaBinaryDocument(
    [node.code, node.payload],
    [CindelBinaryFieldType.intValue, CindelBinaryFieldType.stringValue],
  ),
  fromBinaryDocument: (bytes) {
    final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 11);
    return BackupNode(
      0,
      code: reader.readInt(0, 0)!,
      payload: reader.readString(1, 8)!,
    );
  },
  writeNativeDocument: (writer, node) {
    writer.writeInt(0, node.code);
    writer.writeString(1, node.payload);
  },
  readNativeDocument: (reader, index) => BackupNode(
    reader.readId(index),
    code: reader.readInt(index, 0)!,
    payload: reader.readString(index, 1)!,
  ),
  getId: (node) => node.dbId,
  setId: (node, id) => node.dbId = id,
  bindLinks: (database, schema, node) {
    node.children.bind(
      database as CindelDatabase,
      schema as dynamic,
      node,
      schema.links[0],
    );
    node.parent.bind(database, schema as dynamic, node, schema.links[1]);
    node.owners.bind(database, schema as dynamic, node, schema.links[2]);
  },
);

final backupLeafSchema = CindelCollectionSchema<BackupNode>(
  name: 'backup_leaves',
  dartName: 'BackupLeaf',
  idField: 'dbId',
  fields: backupNodeSchema.fields,
  links: backupNodeSchema.links,
  toDocument: backupNodeSchema.toDocument,
  fromDocument: backupNodeSchema.fromDocument,
  toBinaryDocument: backupNodeSchema.toBinaryDocument,
  fromBinaryDocument: backupNodeSchema.fromBinaryDocument,
  writeNativeDocument: backupNodeSchema.writeNativeDocument,
  readNativeDocument: backupNodeSchema.readNativeDocument,
  getId: backupNodeSchema.getId,
  setId: backupNodeSchema.setId,
  bindLinks: backupNodeSchema.bindLinks,
);
