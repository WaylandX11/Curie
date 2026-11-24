import 'package:material_ui/material_ui.dart';

import 'src/app.dart';
import 'src/services/locale_controller.dart';
import 'src/services/store.dart';
import 'src/services/theme_controller.dart';
import 'src/services/vpn.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.load();
  await LocaleController.load();
  await ThemeController.load();
  await Vpn.init();
  runApp(const CurieApp());
}
