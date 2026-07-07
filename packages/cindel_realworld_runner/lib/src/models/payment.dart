import 'package:cindel/cindel.dart';

import 'enums.dart';
import 'order.dart';

part 'payment.g.dart';

@Collection(name: 'payments')
class Payment {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String transactionId;

  PaymentMethod method = PaymentMethod.card;

  @index
  PaymentStatus status = PaymentStatus.authorized;

  double amount = 0;

  DateTime authorizedAt = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);

  @Backlink(to: 'payment')
  final orders = CindelLinks<CustomerOrder>();
}
