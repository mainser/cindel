import 'package:cindel/cindel.dart';

part 'app_setting.g.dart';

@Collection(name: 'appSettings')
class AppSetting {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String key;

  late String value;

  bool enabled = true;

  DateTime updatedAt = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
}
