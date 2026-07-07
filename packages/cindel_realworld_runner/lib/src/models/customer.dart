import 'package:cindel/cindel.dart';

import 'customer_address.dart';
import 'enums.dart';
import 'order.dart';

part 'customer.g.dart';

@Collection(
  name: 'customers',
  indexes: [
    CompositeIndex(['email', 'active']),
  ],
)
class Customer {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true, caseSensitive: false)
  late String email;

  late String name;

  bool active = true;

  int loyaltyPoints = 0;

  double lifetimeValue = 0;

  @index
  DateTime signedUpAt = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);

  Duration? preferredResponseTime;

  CustomerStatus status = CustomerStatus.active;

  @Enumerated(CindelEnumType.value, valueField: 'code')
  CustomerTier tier = CustomerTier.standard;

  @Index(type: CindelIndexType.multiEntry, caseSensitive: false)
  List<String> tags = const [];

  CustomerAddress? defaultShippingAddress;

  List<CustomerAddress> savedAddresses = const [];

  @Backlink(to: 'customer')
  final orders = CindelLinks<CustomerOrder>();
}
