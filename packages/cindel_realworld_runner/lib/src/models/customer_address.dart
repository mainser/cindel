import 'package:cindel/cindel.dart';

@embedded
class CustomerAddress {
  String? line1;

  String? city;

  String? country;

  String? postalCode;

  CustomerGeoPoint? location;
}

@embedded
class CustomerGeoPoint {
  double latitude = 0;

  double longitude = 0;
}
