import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/app_state.dart';
import '../models/subscription.dart';
import '../services/store.dart';
import '../services/subscriptions.dart';
import '../widgets/common.dart';
import '../widgets/subscription_actions.dart';

/// Подписки: добавить, обновить, удалить. Панель (Remnawave и совместимые)
/// отдаёт узлы и метаданные — трафик и срок действия показываем сразу.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final Set<String> _updating = {};
  bool _busy = false;

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final url = await promptText(
      context,
      title: l10n.tr('addSubscription'),
      hint: 'https://…',
      keyboardType: TextInputType.url,
    );
    if (url == null || url.trim().isEmpty || !mounted) return;

    final title = await promptText(
      context,
      title: l10n.tr('subscriptionName'),
      hint: Uri.tryParse(url.trim())?.host ?? '',
    );
    if (!mounted) return;

    setState(() => _busy = true);
    final failure = await Subscriptions.add(url, title ?? '');
    if (!mounted) return;
    setState(() => _busy = false);
    showMessage(
      context,
      failure == null
          ? l10n.tr('subscriptionAdded')
          : l10n.fmt('subscriptionFailed', {
              'error': subscriptionErrorText(l10n, failure.code, failure.detail),
            }),
    );
  }

  Future<void> _refresh(Subscription subscription) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _updating.add(subscription.url));
    final failure = await Subscriptions.refresh(subscription);
    if (!mounted) return;
    setState(() => _updating.remove(subscription.url));
    if (failure == null) {
      showMessage(context, l10n.tr('subscriptionUpdated'));
      return;
    }
    showMessage(
      context,
      l10n.fmt('subscriptionFailed', {
        'error': subscriptionErrorText(l10n, failure.code, failure.detail),
      }),
    );
  }

  Future<void> _refreshAll() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final errors = await Subscriptions.refreshAll();
    if (!mounted) return;
    setState(() => _busy = false);
    if (errors.isNotEmpty) {
      showMessage(
        context,
        l10n.fmt('subscriptionFailed', {
          'error': subscriptionErrorText(l10n, errors.first.code, errors.first.detail),
        }),
      );
    } else if (Store.instance.state.value.subscriptions.isNotEmpty) {
      showMessage(context, l10n.tr('subscriptionUpdated'));
    }
  }

  Future<void> _delete(Subscription subscription) async {
    if (!await confirmDelete(context, subscription.title)) return;
    await Subscriptions.remove(subscription.url);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('subscriptions')),
        actions: [
          IconButton(
            tooltip: l10n.tr('updateAll'),
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: _busy ? null : _refreshAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.add),
        label: Text(l10n.tr('add')),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<AppState>(
          valueListenable: Store.instance.state,
          builder: (context, state, _) {
            if (state.subscriptions.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    l10n.tr('emptyBody'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final subscription in state.subscriptions)
                  _card(
                    context,
                    subscription,
                    state.settings.subscriptionUpdateHours,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    Subscription subscription,
    int updateHours,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final info = subscription.info;
    final updating = _updating.contains(subscription.url);

    final subtitle = <String>[
      l10n.fmt('nodesCount', {'count': subscription.nodes.length}),
      l10n.fmt('updateEvery', {'hours': updateHours}),
      if (subscription.updatedAt != null)
        l10n.fmt('updated', {'time': formatDateTime(subscription.updatedAt!)})
      else
        l10n.tr('neverUpdated'),
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Название — главное: рядом только шестерёнка, остальные действия
            // перенесены в нижний ряд, чтобы длинное имя не обрезалось.
            Row(
              children: [
                Expanded(
                  child: Text(
                    subscription.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: l10n.tr('subscriptionActions'),
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => showSubscriptionActions(context, subscription),
                ),
              ],
            ),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (info != null) ...[
              const SizedBox(height: 10),
              if (info.usageRatio != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: info.usageRatio,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: info.usageRatio! > 0.9
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                [
                  if (info.total > 0)
                    l10n.fmt('traffic', {
                      'used': formatBytes(info.used),
                      'total': formatBytes(info.total),
                    })
                  else
                    l10n.fmt('trafficUnlimited', {'used': formatBytes(info.used)}),
                  if (info.expire != null)
                    info.isExpired
                        ? l10n.tr('expired')
                        : l10n.fmt('expires', {'date': formatDate(info.expire!)}),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: info.isExpired
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (subscription.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.fmt('subscriptionFailed', {
                  'error': subscriptionErrorText(
                    l10n,
                    subscription.lastError!,
                    subscription.lastErrorDetail,
                  ),
                }),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (updating)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _refresh(subscription),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: Text(l10n.tr('update')),
                  ),
                TextButton.icon(
                  onPressed: () => _delete(subscription),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(l10n.tr('delete')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
