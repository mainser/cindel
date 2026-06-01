import 'package:cindel_shop_lite/app/app.dart';
import 'package:cindel_shop_lite/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
