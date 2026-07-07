import 'package:cindel/cindel.dart';

import 'enums.dart';
import 'product.dart';

part 'inventory_movement.g.dart';

@Collection(name: 'inventoryMovements')
class InventoryMovement {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String reference;

  @index
  DateTime createdAt = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);

  int quantity = 0;

  MovementType type = MovementType.sale;

  String? reason;

  final product = CindelLink<Product>();
}
