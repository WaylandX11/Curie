import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'l10n/app_localizations.dart';
import 'screens/main_shell.dart';
import 'services/locale_controller.dart';
import 'services/schedulers.dart';
import 'services/theme_controller.dart';
import 'theme.dart';

class CurieApp extends StatefulWidget {
  const CurieApp({super.key});

  @override
  State<CurieApp> createState() => _CurieAppState();
}

class _CurieAppState extends State<CurieApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Сеть не должна задерживать первый кадр. На iOS/в тестах планировщик
    // не поднимаем: приложение пока Android-only.
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(CurieSchedulers.start());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      // Догоняем подписки и проверку обновлений, пока приложение было в фоне.
      unawaited(CurieSchedulers.resume());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleController.locale,
      builder: (context, locale, _) => ValueListenableBuilder<AppTheme>(
        valueListenable: ThemeController.theme,
        builder: (context, selectedTheme, _) => MaterialApp(
          title: 'Curie',
          debugShowCheckedModeBanner: false,
          // Оба слота заданы одной и той же темой: пользователь выбирает
          // конкретную палитру, а не «светлую/тёмную» для системного режима.
          theme: curieTheme(selectedTheme),
          darkTheme: curieTheme(selectedTheme),
          themeMode: selectedTheme.brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: const MainShell(),
        ),
      ),
    );
  }
}
