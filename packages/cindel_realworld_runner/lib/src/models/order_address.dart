import 'package:cindel/cindel.dart';

@embedded
class OrderAddress {
  String? line1;

  String? city;

  String? country;

  String? postalCode;

  OrderGeoPoint? location;
}

@embedded
class OrderGeoPoint {
  double latitude = 0;

  double longitude = 0;
}
