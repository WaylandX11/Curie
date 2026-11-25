import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/update.dart';
import '../version.dart';
import 'common.dart';

/// Окно обновления. Используется и кнопкой в настройках, и баннером на главной.
Future<void> showUpdateDialog(
  BuildContext context,
  GithubRelease release, {
  bool coreUpdated = false,
}) async {
  final l10n = AppLocalizations.of(context);

  Future<void> open(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        throw 'cannot launch';
      }
    } on Object catch (_) {
      if (context.mounted) showMessage(context, l10n.tr('updateError'));
    }
  }

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        coreUpdated ? l10n.tr('updateCoreTitle') : l10n.tr('updateAvailable'),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.fmt('updateFound', {'version': release.version})),
            const SizedBox(height: 4),
            Text(
              l10n.fmt('updateCurrent', {'version': displayVersion}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (coreUpdated && release.coreVersion != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.fmt('updateCoreBody', {
                  'version': release.version,
                  'core': release.coreVersion,
                }),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (release.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                release.notes,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.tr('cancel')),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(open(release.htmlUrl));
          },
          child: Text(l10n.tr('updateOpenRelease')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(open(release.downloadUrl));
          },
          child: Text(l10n.tr('updateDownload')),
        ),
      ],
    ),
  );
}
