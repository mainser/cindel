import 'package:cindel/cindel.dart';

import 'customer.dart';
import 'enums.dart';
import 'order_address.dart';
import 'order_item.dart';
import 'payment.dart';

part 'order.g.dart';

@Collection(
  name: 'orders',
  indexes: [
    CompositeIndex(['status', 'createdAt']),
  ],
)
class CustomerOrder {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String orderNumber;

  @index
  OrderStatus status = OrderStatus.draft;

  @index
  DateTime createdAt = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);

  @index
  double total = 0;

  bool priority = false;

  OrderAddress? shippingAddress;

  List<OrderItem> items = const [];

  String? note;

  final customer = CindelLink<Customer>();

  final payment = CindelLink<Payment>();
}
