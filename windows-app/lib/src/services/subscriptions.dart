import '../models/subscription.dart';
import 'app_log.dart';
import 'device_identity.dart';
import 'geo_assets.dart';
import 'store.dart';
import 'subscription_service.dart';
import 'user_agent.dart';
import 'vpn.dart';

/// Операции над подписками: сеть + сохранение состояния.
class Subscriptions {
  static const SubscriptionService _service = SubscriptionService();

  /// Добавляет подписку и сразу её загружает. При ошибке подписка не сохраняется.
  static Future<SubscriptionException?> add(String url, String title) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return const SubscriptionException('noLinks');

    final exists = Store.instance.state.value.subscriptions.any(
      (s) => s.url == trimmed,
    );
    if (exists) return null;

    final draft = Subscription(
      url: trimmed,
      title: title.trim().isEmpty
          ? (Uri.tryParse(trimmed)?.host ?? trimmed)
          : title.trim(),
    );

    try {
      final loaded = await _service.refresh(
        draft,
        headers: await DeviceIdentity.headers(),
        userAgent: await currentUserAgent(),
        proxyPort: Vpn.tunnelProxyPort,
      );
      await Store.instance.update(
        (state) =>
            state.copyWith(subscriptions: [...state.subscriptions, loaded]),
      );
      await GeoAssets.noteSubscription(loaded);
      return null;
    } on SubscriptionException catch (e) {
      return e;
    } on Object catch (e) {
      return SubscriptionException('network', e.toString());
    }
  }

  static Future<SubscriptionException?> refresh(
    Subscription subscription,
  ) async {
    try {
      final loaded = await _service.refresh(
        subscription,
        headers: await DeviceIdentity.headers(),
        userAgent: await currentUserAgent(),
        proxyPort: Vpn.tunnelProxyPort,
      );
      await _replace(loaded);
      await GeoAssets.noteSubscription(loaded);
      AppLog.add(
        'subscription',
        'обновлена: ${loaded.title} (узлов: ${loaded.nodes.length})',
      );
      return null;
    } on SubscriptionException catch (e) {
      AppLog.add('subscription', 'ошибка ${e.code}: ${e.detail ?? ''}');
      await _replace(
        subscription.copyWith(lastError: e.code, lastErrorDetail: e.detail),
      );
      return e;
    } on Object catch (e) {
      final failure = SubscriptionException('network', e.toString());
      AppLog.add('subscription', 'ошибка обновления: $e');
      await _replace(
        subscription.copyWith(
          lastError: failure.code,
          lastErrorDetail: failure.detail,
        ),
      );
      return failure;
    }
  }

  static Future<List<SubscriptionException>> refreshAll({
    bool onlyStale = false,
    int? intervalHours,
  }) async {
    final errors = <SubscriptionException>[];
    for (final subscription in Store.instance.state.value.subscriptions) {
      if (onlyStale && !subscription.isStale(overrideHours: intervalHours)) {
        continue;
      }
      final error = await refresh(subscription);
      if (error != null) errors.add(error);
    }
    return errors;
  }

  static Future<void> remove(String url) async {
    await Store.instance.update(
      (state) => state.copyWith(
        subscriptions: state.subscriptions.where((s) => s.url != url).toList(),
      ),
    );
  }

  /// Развёрнутость списка узлов сохраняется рядом с подпиской.
  static Future<void> setExpanded(String url, bool expanded) async {
    await Store.instance.update(
      (state) => state.copyWith(
        subscriptions: state.subscriptions
            .map((s) => s.url == url ? s.copyWith(expanded: expanded) : s)
            .toList(),
      ),
    );
  }

  static Future<void> _replace(Subscription subscription) async {
    await Store.instance.update(
      (state) => state.copyWith(
        subscriptions: state.subscriptions
            .map((s) => s.url == subscription.url ? subscription : s)
            .toList(),
      ),
    );
  }
}
