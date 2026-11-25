import 'package:curie/src/app.dart';
import 'package:curie/src/services/locale_controller.dart';
import 'package:curie/src/services/theme_controller.dart';
import 'package:curie/src/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  tearDown(() {
    LocaleController.locale.value = null;
    ThemeController.theme.value = AppTheme.dark;
  });

  testWidgets('empty state and navigation are shown in English', (tester) async {
    await tester.pumpWidget(const CurieApp());
    await tester.pumpAndSettle();

    expect(find.text('No server yet'), findsOneWidget);
    expect(find.text('Tap to connect'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Servers'), findsNothing,
        reason: 'список узлов находится в карточке на главной');
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('interface switches to Russian', (tester) async {
    LocaleController.locale.value = const Locale('ru');
    await tester.pumpWidget(const CurieApp());
    await tester.pumpAndSettle();

    expect(find.text('Сервер не добавлен'), findsOneWidget);
    expect(find.text('Нажмите для подключения'), findsOneWidget);
    expect(find.text('Главная'), findsOneWidget);
    expect(find.text('Серверы'), findsNothing);
  });

  testWidgets('theme switches between all palettes', (tester) async {
    ThemeController.theme.value = AppTheme.dark;
    await tester.pumpWidget(const CurieApp());
    await tester.pumpAndSettle();

    ThemeData visibleTheme() =>
        Theme.of(tester.element(find.text('Curie')));
    expect(visibleTheme().brightness, Brightness.dark);
    expect(visibleTheme().colorScheme.primary, const Color(0xFF2FE3D0));

    ThemeController.theme.value = AppTheme.light;
    await tester.pumpAndSettle();
    expect(visibleTheme().brightness, Brightness.light);

    ThemeController.theme.value = AppTheme.amber;
    await tester.pumpAndSettle();
    expect(visibleTheme().brightness, Brightness.dark);
    expect(visibleTheme().colorScheme.primary, const Color(0xFFFFC44D));

    ThemeController.theme.value = AppTheme.ocean;
    await tester.pumpAndSettle();
    expect(visibleTheme().colorScheme.primary, const Color(0xFF4FC3F7));

    ThemeController.theme.value = AppTheme.forest;
    await tester.pumpAndSettle();
    expect(visibleTheme().brightness, Brightness.light);
    expect(visibleTheme().colorScheme.primary, const Color(0xFF2E7D32));

    ThemeController.theme.value = AppTheme.vanilla;
    await tester.pumpAndSettle();
    expect(visibleTheme().brightness, Brightness.light);
    expect(visibleTheme().colorScheme.primary, const Color(0xFF7A4700));
    expect(visibleTheme().scaffoldBackgroundColor, const Color(0xFFF8EDD2));

    ThemeController.theme.value = AppTheme.pink;
    await tester.pumpAndSettle();
    expect(visibleTheme().brightness, Brightness.light);
    expect(visibleTheme().colorScheme.primary, const Color(0xFFA8134E));
    expect(visibleTheme().scaffoldBackgroundColor, const Color(0xFFF8DFE9));
  });
}
