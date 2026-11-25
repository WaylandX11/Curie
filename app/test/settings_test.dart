import 'package:curie/src/models/app_state.dart';
import 'package:curie/src/models/profile.dart';
import 'package:curie/src/models/settings.dart';
import 'package:curie/src/models/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routing mode has a stable wire name for the platform channel', () {
    expect(RoutingMode.all.wireName, 'all');
    expect(RoutingMode.onlySelected.wireName, 'only');
    expect(RoutingMode.bypassSelected.wireName, 'bypass');
    expect(RoutingMode.fromName('only'), RoutingMode.onlySelected);
    expect(RoutingMode.fromName(null), RoutingMode.all);
  });

  test('DNS comes from the subscription by default', () {
    const settings = Settings();
    expect(settings.dnsUsePanel, isTrue);
    expect(settings.dns, '77.88.8.8', reason: 'адрес на случай пустой подписки');
  });

  test('old DNS default migrates once, a custom address is kept', () {
    final oldDefault = Settings.fromJson({
      'dns': '77.88.8.8',
      'dnsUsePanel': false,
    });
    expect(oldDefault.dnsUsePanel, isTrue);

    final legacy = Settings.fromJson({'dns': '1.1.1.1', 'dnsUsePanel': false});
    expect(legacy.dns, '77.88.8.8');
    expect(legacy.dnsUsePanel, isTrue);

    final custom = Settings.fromJson({'dns': '9.9.9.9', 'dnsUsePanel': false});
    expect(custom.dns, '9.9.9.9');
    expect(custom.dnsUsePanel, isFalse);

    // После миграции ручной выбор фиксированного адреса не перетирается.
    final manual = Settings.fromJson(
      Settings(dns: '9.9.9.9', dnsUsePanel: false).toJson(),
    );
    expect(manual.dnsUsePanel, isFalse);
  });

  test('selected apps depend on the mode', () {
    const settings = Settings(
      routingMode: RoutingMode.onlySelected,
      allowedApps: ['a', 'b'],
      bypassedApps: ['c'],
    );
    expect(settings.selectedApps, ['a', 'b']);
    expect(
      settings.copyWith(routingMode: RoutingMode.bypassSelected).selectedApps,
      ['c'],
    );
  });

  test('settings survive a storage round trip', () {
    const settings = Settings(
      routingMode: RoutingMode.bypassSelected,
      bypassedApps: ['ru.bank.app'],
      dns: '9.9.9.9',
      bypassLan: false,
      mtu: 1400,
    );
    final restored = Settings.fromJson(settings.toJson());

    expect(restored.routingMode, settings.routingMode);
    expect(restored.bypassedApps, settings.bypassedApps);
    expect(restored.dns, '9.9.9.9');
    expect(restored.bypassLan, isFalse);
    expect(restored.mtu, 1400);
  });

  test('new scheduler and log settings survive a storage round trip', () {
    const settings = Settings(
      subscriptionUpdateHours: 6,
      xrayLogEnabled: false,
      xrayLogLevel: XrayLogLevel.error,
      xrayLogRetentionHours: 72,
      lastNotifiedCoreVersion: '26.11.9',
      pendingUpdate: '{"version":"26.11.25.0900"}',
    );
    final restored = Settings.fromJson(settings.toJson());

    expect(restored.subscriptionUpdateHours, 6);
    expect(restored.xrayLogEnabled, isFalse);
    expect(restored.xrayLogLevel, XrayLogLevel.error);
    expect(restored.xrayLogRetentionHours, 72);
    expect(restored.lastNotifiedCoreVersion, '26.11.9');
    expect(restored.pendingUpdate, '{"version":"26.11.25.0900"}');
  });

  test('manual hours are clamped to a sane range', () {
    final low = Settings.fromJson({'subscriptionUpdateHours': 0, 'xrayLogRetentionHours': 0});
    expect(low.subscriptionUpdateHours, Settings.minSubscriptionUpdateHours);
    expect(low.xrayLogRetentionHours, Settings.minLogRetentionHours);

    final high = Settings.fromJson({
      'subscriptionUpdateHours': 9999,
      'xrayLogRetentionHours': 9999,
    });
    expect(high.subscriptionUpdateHours, Settings.maxSubscriptionUpdateHours);
    expect(high.xrayLogRetentionHours, Settings.maxLogRetentionHours);
  });

  test('clearPendingUpdate removes the saved banner', () {
    const settings = Settings(pendingUpdate: 'stale');
    expect(settings.copyWith(clearPendingUpdate: true).pendingUpdate, isNull);
    expect(settings.copyWith(pendingUpdate: 'fresh').pendingUpdate, 'fresh');
  });

  test('ping mode survives storage and old ICMP migrates to TCP', () {
    expect(PingMode.fromName('icmp'), PingMode.tcp);
    expect(PingMode.fromName('tcp'), PingMode.tcp);
    expect(PingMode.fromName('http'), PingMode.proxy);
    expect(PingMode.fromName(null), PingMode.proxy);

    final restored = Settings.fromJson(
      const Settings(pingMode: PingMode.tcp).toJson(),
    );
    expect(restored.pingMode, PingMode.tcp);
  });

  test('selected node falls back when the subscription loses it', () {
    const node = Profile(link: 'vless://a', name: 'A');
    const other = Profile(link: 'vless://b', name: 'B');
    final state = AppState(
      subscriptions: [
        Subscription(url: 'https://panel/sub', title: 'Panel', nodes: [node, other]),
      ],
      selectedId: node.id,
    );
    expect(state.selected!.id, node.id);

    final updated = AppState(
      subscriptions: [
        Subscription(url: 'https://panel/sub', title: 'Panel', nodes: [other]),
      ],
      selectedId: node.id,
    );
    expect(updated.selected!.id, other.id);
  });

  test('state survives a storage round trip', () {
    const state = AppState(
      profiles: [Profile(link: 'vless://x', name: 'X')],
      selectedId: 'vless://x',
    );
    final restored = AppState.fromJson(state.toJson());

    expect(restored.profiles.single.name, 'X');
    expect(restored.selectedId, 'vless://x');
    expect(restored.settings.routingMode, RoutingMode.all);
  });
}
