import 'package:cindel/cindel.dart';

import 'app_setting.dart';
import 'category.dart';
import 'customer.dart';
import 'inventory_movement.dart';
import 'order.dart';
import 'payment.dart';
import 'product.dart';

final cindelRealworldSchemas = <CindelCollectionSchema<dynamic>>[
  CustomerSchema,
  CategorySchema,
  ProductSchema,
  PaymentSchema,
  CustomerOrderSchema,
  InventoryMovementSchema,
  AppSettingSchema,
];
