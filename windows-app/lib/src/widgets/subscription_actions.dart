import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/subscription.dart';
import 'common.dart';

/// Меню по шестерёнке: ссылка и управление подписками.
/// Обновление и пинг вынесены в отдельные кнопки рядом с названием.
Future<void> showSubscriptionActions(
  BuildContext context,
  Subscription subscription, {
  VoidCallback? onManage,
}) async {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final link = subscription.shareUrl;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                l10n.tr('subscriptionActions'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                subscription.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: Text(l10n.tr('copySubscriptionLink')),
              subtitle: Text(
                link,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.of(context).pop();
                ClipboardCopy.copy(context, link);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(l10n.tr('shareSubscription')),
              onTap: () {
                Navigator.of(context).pop();
                final uri = Uri.tryParse(link);
                SharePlus.instance.share(
                  ShareParams(
                    uri: uri,
                    text: uri == null ? link : null,
                    subject: subscription.title.isEmpty
                        ? 'Curie'
                        : subscription.title,
                  ),
                );
              },
            ),
            if (onManage != null)
              ListTile(
                leading: const Icon(Icons.subscriptions_outlined),
                title: Text(l10n.tr('openSubscriptions')),
                onTap: () {
                  Navigator.of(context).pop();
                  onManage();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
