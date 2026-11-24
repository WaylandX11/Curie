import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/profile.dart';
import '../models/subscription.dart';
import '../services/ping.dart';
import 'common.dart';
import 'node_tile.dart';
import 'subscription_actions.dart';

/// Карточка провайдера: свёрнутая показывает трафик и объявление,
/// развёрнутая — список узлов с задержкой.
class ProviderCard extends StatefulWidget {
  const ProviderCard({
    super.key,
    required this.profiles,
    required this.selectedId,
    required this.onSelect,
    this.subscription,
    this.onRefresh,
    this.onPing,
    this.onManage,
    this.onEdit,
    this.expanded,
    this.onExpandedChanged,
  });

  final List<Profile> profiles;
  final String? selectedId;
  final ValueChanged<Profile> onSelect;
  final Subscription? subscription;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onPing;
  final VoidCallback? onManage;
  final ValueChanged<Profile>? onEdit;

  /// Для подписок состояние приходит из Store. Для вручную добавленных ссылок
  /// карточка живёт локально.
  final bool? expanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<ProviderCard> {
  bool _localExpanded = false;
  bool _refreshing = false;

  bool get _isExpanded => widget.expanded ?? _localExpanded;

  void _toggleExpanded() {
    final next = !_isExpanded;
    final callback = widget.onExpandedChanged;
    if (callback != null) {
      callback(next);
      return;
    }
    setState(() => _localExpanded = next);
  }

  Future<void> _refresh() async {
    final callback = widget.onRefresh;
    if (callback == null) return;
    setState(() => _refreshing = true);
    try {
      await callback();
    } finally {
      // Индикатор гасим по факту прихода новых данных (или ошибки).
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final subscription = widget.subscription;
    final info = subscription?.info;
    final title = subscription?.title ?? l10n.tr('manualLinks');

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Порядок: название → обновление → пинг → шестерёнка.
            // Обновление и пинг всегда на виду; в меню остаются только ссылка
            // и управление подписками. Раньше пинг был спрятан в шторке и без
            // индикатора казался неработающим.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: _isExpanded
                      ? l10n.tr('collapse')
                      : l10n.tr('expand'),
                  icon: Icon(
                    _isExpanded ? Icons.expand_less : Icons.chevron_right,
                  ),
                  onPressed: _toggleExpanded,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subscription != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            l10n.fmt('updateEvery', {
                              'hours': subscription.updateIntervalHours,
                            }),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (subscription != null)
                  IconButton(
                    tooltip: l10n.tr('update'),
                    icon: _refreshing
                        ? const _CardSpinner(tooltip: '…')
                        : const Icon(Icons.cloud_download_outlined),
                    onPressed: _refreshing ? null : _refresh,
                  ),
                ValueListenableBuilder<bool>(
                  valueListenable: Ping.running,
                  builder: (context, running, _) => IconButton(
                    tooltip: l10n.tr('ping'),
                    icon: running
                        ? const _CardSpinner(tooltip: '…')
                        : const Icon(Icons.radar_outlined),
                    onPressed: running ? null : widget.onPing,
                  ),
                ),
                if (subscription != null)
                  IconButton(
                    tooltip: l10n.tr('subscriptionActions'),
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => showSubscriptionActions(
                      context,
                      subscription,
                      onManage: widget.onManage,
                    ),
                  ),
              ],
            ),
            if (info != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: info.usageRatio ?? 0,
                              minHeight: 6,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              color: (info.usageRatio ?? 0) > 0.9
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          info.total > 0
                              ? '${formatBytes(info.used)} / ${formatBytes(info.total)}'
                              : '${formatBytes(info.used)} / ∞',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                    if (info.expire != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          info.isExpired
                              ? l10n.tr('expired')
                              : l10n.fmt('expires', {
                                  'date': formatDate(info.expire!),
                                }),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: info.isExpired
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (subscription?.announce != null &&
                subscription!.announce!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Text(
                  subscription.announce!,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      subscription?.lastError != null
                          ? l10n.fmt('subscriptionFailed', {
                              'error': subscriptionErrorText(
                                l10n,
                                subscription!.lastError!,
                                subscription.lastErrorDetail,
                              ),
                            })
                          : (subscription?.updatedAt == null
                                ? l10n.tr('neverUpdated')
                                : l10n.fmt('updated', {
                                    'time': formatDateTime(
                                      subscription!.updatedAt!,
                                    ),
                                  })),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: subscription?.lastError != null
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.fmt('nodesCount', {'count': widget.profiles.length}),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_isExpanded) ...[
              const SizedBox(height: 8),
              for (final profile in widget.profiles)
                NodeTile(
                  profile: profile,
                  selected: profile.id == widget.selectedId,
                  onTap: () => widget.onSelect(profile),
                  onLongPress: widget.onEdit == null
                      ? null
                      : () => widget.onEdit!(profile),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Небольшой индикатор поверх шестерёнки, пока подписка обновляется.
class _CardSpinner extends StatelessWidget {
  const _CardSpinner({required this.tooltip});

  final String tooltip;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 36,
    child: Center(
      child: Tooltip(
        message: tooltip,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );
}
