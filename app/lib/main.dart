import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'src/app.dart';
import 'src/generated/build_info.dart';
import 'src/generated/core_info.dart';
import 'src/services/app_log.dart';
import 'src/services/locale_controller.dart';
import 'src/services/store.dart';
import 'src/services/theme_controller.dart';
import 'src/services/tunnel_monitor.dart';
import 'src/services/user_agent.dart';
import 'src/services/vpn.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.load();
  await LocaleController.load();
  await ThemeController.load();
  await Vpn.init();
  TunnelMonitor.start();
  // Версия берётся из одного источника — build_info, который пишет set-version.ps1.
  // Так журнал всегда показывает ту же сборку, что и экран «О приложении».
  AppLog.add('app', 'запуск Curie $buildStamp, ядро $libXrayVersion');
  // Точный заголовок виден в журнале сразу после запуска — так про проверить,
  // что панель получает версию ОС, а не просто «android».
  unawaited(currentUserAgent());
  runApp(const CurieApp());
}
