import 'database.dart';

abstract final class Cindel {
  static Future<CindelDatabase> open({required String directory}) {
    return CindelDatabase.open(directory: directory);
  }
}
