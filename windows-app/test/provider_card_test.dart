import 'package:curie_windows/src/l10n/app_localizations.dart';
import 'package:curie_windows/src/models/subscription.dart';
import 'package:curie_windows/src/widgets/provider_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _card({required int configuredHours, required int panelHours}) {
  return MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(
      body: ProviderCard(
        profiles: const [],
        selectedId: null,
        onSelect: (_) {},
        updateHours: configuredHours,
        subscription: Subscription(
          url: 'https://example.com/sub',
          title: 'Test provider',
          updateIntervalHours: panelHours,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('card shows the configured interval, not the panel hint',
      (tester) async {
    await tester.pumpWidget(_card(configuredHours: 3, panelHours: 12));
    await tester.pumpAndSettle();

    expect(find.text('Updated every 3 h'), findsOneWidget);
    expect(find.text('Updated every 12 h'), findsNothing);
  });
}
