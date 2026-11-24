import 'package:curie/src/l10n/app_localizations.dart';
import 'package:curie/src/models/settings.dart';
import 'package:curie/src/services/device_identity.dart';
import 'package:curie/src/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('HWID', () {
    test('derived id has the requested grouped format', () async {
      for (var i = 0; i < 20; i++) {
        final id = await DeviceIdentity.derive('device-$i');
        expect(id.length, 36);
        expect(id, matches(r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$'));
        expect(DeviceIdentity.isValid(id), isTrue);
      }
    });

    test('same device gets the same id, different phones get different ids', () async {
      final first = await DeviceIdentity.derive('phone-a');
      final again = await DeviceIdentity.derive('phone-a');
      final second = await DeviceIdentity.derive('phone-b');
      expect(again, first);
      expect(second, isNot(first));
    });

    test('an old 32-character id is migrated without changing its bytes', () {
      expect(
        DeviceIdentity.normalize('6b625e5a26fd9875e216bbfb088fd1ae'),
        '6B625E5A-26FD-9875-E216-BBFB088FD1AE',
      );
      expect(
        DeviceIdentity.normalize('6B625E5A-26FD-9875-E216-BBFB088FD1AE'),
        '6B625E5A-26FD-9875-E216-BBFB088FD1AE',
      );
      expect(DeviceIdentity.isValid('6b625e5a26fd9875e216bbfb088fd1ae'), isFalse);
    });

    test('foreign formats are rejected', () {
      expect(DeviceIdentity.isValid('short'), isFalse);
      expect(DeviceIdentity.isValid('a' * 65), isFalse);
      expect(DeviceIdentity.isValid('has space inside 1234'), isFalse);
      expect(DeviceIdentity.normalize('подпись-устройства'), isNull);
    });

    test('sending HWID is off by default and survives a round trip', () {
      expect(const Settings().sendHwid, isFalse);
      const enabled = Settings(sendHwid: true);
      expect(Settings.fromJson(enabled.toJson()).sendHwid, isTrue);
      expect(Settings.fromJson(const Settings().toJson()).sendHwid, isFalse);
    });
  });

  group('subscription errors', () {
    const l10n = AppLocalizations(Locale('en'), AppLocalizations.en);

    test('panel codes become readable text', () {
      expect(subscriptionErrorText(l10n, 'http', '404'), contains('404'));
      expect(subscriptionErrorText(l10n, 'hwidLimit'), contains('device limit'));
      expect(subscriptionErrorText(l10n, 'hwidRequired'), contains('HWID'));
      expect(subscriptionErrorText(l10n, 'noLinks'), contains('no links'));
      expect(subscriptionErrorText(l10n, 'network', 'SocketException'),
          contains('SocketException'));
    });
  });
}
