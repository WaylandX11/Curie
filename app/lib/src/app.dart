import 'package:material_ui/material_ui.dart';

import 'l10n/app_localizations.dart';
import 'screens/main_shell.dart';
import 'services/app_log.dart';
import 'services/locale_controller.dart';
import 'services/store.dart';
import 'services/subscriptions.dart';
import 'services/theme_controller.dart';
import 'theme.dart';

class CurieApp extends StatefulWidget {
  const CurieApp({super.key});

  @override
  State<CurieApp> createState() => _CurieAppState();
}

class _CurieAppState extends State<CurieApp> {
  @override
  void initState() {
    super.initState();
    // Подписки обновляем после первого кадра: сеть не должна задерживать UI.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoUpdate());
  }

  Future<void> _autoUpdate() async {
    final state = Store.instance.state.value;
    if (!state.settings.autoUpdateSubscriptions) return;
    final due = state.subscriptions.where((s) => s.isStale).length;
    AppLog.add(
      'subscription',
      'запуск: автообновление подписок (по интервалу: $due из '
          '${state.subscriptions.length})',
    );
    // Интервал приходит вместе с подпиской (profile-update-interval) и
    // хранится в зашифрованном состоянии; при запуске обновляем просроченные.
    await Subscriptions.refreshAll(onlyStale: true);
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
