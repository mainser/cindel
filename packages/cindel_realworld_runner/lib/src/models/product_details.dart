import 'package:cindel/cindel.dart';

@embedded
class ProductDetails {
  String? manufacturer;

  double weight = 0;

  List<String> materials = const [];

  Warranty? warranty;
}

@embedded
class Warranty {
  int months = 0;

  String? provider;
}
