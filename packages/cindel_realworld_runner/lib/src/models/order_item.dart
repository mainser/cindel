import 'package:cindel/cindel.dart';

@embedded
class OrderItem {
  late String sku;

  late String productName;

  int quantity = 0;

  double unitPrice = 0;

  List<String> appliedCoupons = const [];
}
