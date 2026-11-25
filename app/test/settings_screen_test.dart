import 'package:curie/src/l10n/app_localizations.dart';
import 'package:curie/src/models/app_state.dart';
import 'package:curie/src/screens/settings_screen.dart';
import 'package:curie/src/services/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app() => MaterialApp(
      home: const SettingsScreen(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
    );

void main() {
  tearDown(() => Store.instance.state.value = const AppState());

  testWidgets('settings open as separate sections', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    for (final title in [
      'Routing',
      'Connection',
      'Appearance',
      'Logs',
      'About app',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(
      find.text('Update subscriptions automatically'),
      findsNothing,
      reason: 'элементы управления живут внутри разделов, а не в меню',
    );
    expect(find.text('Updated every 1 h'), findsOneWidget,
        reason: 'подпись раздела понятна, а не «Вкл 1»');

    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();
    expect(find.text('Update subscriptions automatically'), findsOneWidget);
    expect(find.text('Device ID (HWID)'), findsOneWidget);
  });

  testWidgets('per-app routing lives in the Routing section', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Providers'), findsNothing);
    expect(find.text('App proxy'), findsNothing);
    await tester.tap(find.text('Routing'));
    await tester.pumpAndSettle();
    // На рабочем столе выбор приложений недоступен — проверяем, что заглушка
    // единственна в разделе маршрутизации.
    expect(find.text('Available on Android only'), findsOneWidget);
    for (final label in [
      'DNS server',
      'MTU',
      'Do not proxy the local network',
      'Resolve DNS through the tunnel',
    ]) {
      expect(find.text(label), findsNothing,
          reason: 'сетевые настройки переехали в «Подключение»');
    }
  });

  testWidgets('network settings live in the Connection section', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();
    // Вторая карточка с сетевыми настройками ниже первого экрана — ListView создаёт
    // её только при прокрутке, поэтому подводим к каждому пункту.
    for (final label in [
      'Network',
      'DNS server',
      'From subscription',
      'Resolve DNS through the tunnel',
      'Do not proxy the local network',
      'MTU',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 300);
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('HWID value is not displayed at all', (tester) async {
    Store.instance.state.value = const AppState(deviceId: 'abc-123');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();
    expect(find.text('Device ID (HWID)'), findsOneWidget);
    expect(find.text('ID: abc-123'), findsNothing);
    expect(
      find.text('ID will be created on the first subscription update'),
      findsNothing,
    );
  });

  testWidgets('log settings live in their own section', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.text('Write Xray logs'), findsOneWidget);
    expect(find.text('Open log'), findsOneWidget);
  });
}
