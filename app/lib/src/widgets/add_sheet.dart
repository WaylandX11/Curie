import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_localizations.dart';
import '../screens/qr_scan_screen.dart';
import '../services/importer.dart';
import 'common.dart';

/// Один вход для всех способов добавить сервер: буфер, QR, ручной ввод, подписка.
Future<void> showAddSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context);

  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.content_paste_go),
            title: Text(l10n.tr('pasteFromClipboard')),
            onTap: () => Navigator.of(context).pop('clipboard'),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: Text(l10n.tr('scanQr')),
            onTap: () => Navigator.of(context).pop('qr'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(l10n.tr('qrFromImage')),
            onTap: () => Navigator.of(context).pop('qrImage'),
          ),
          ListTile(
            leading: const Icon(Icons.keyboard_outlined),
            title: Text(l10n.tr('enterManually')),
            onTap: () => Navigator.of(context).pop('manual'),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: Text(l10n.tr('addSubscription')),
            onTap: () => Navigator.of(context).pop('subscription'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case 'clipboard':
      await importFromClipboard(context);
    case 'qr':
      final value = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(builder: (_) => const QrScanScreen()),
      );
      if (value == null || !context.mounted) return;
      await importAndReport(context, value);
    case 'qrImage':
      await importFromImage(context);
    case 'manual':
      final value = await promptText(
        context,
        title: l10n.tr('pasteTitle'),
        hint: l10n.tr('pasteHint'),
        keyboardType: TextInputType.url,
      );
      if (value == null || value.trim().isEmpty || !context.mounted) return;
      await importAndReport(context, value);
    case 'subscription':
      final value = await promptText(
        context,
        title: l10n.tr('addSubscription'),
        hint: 'https://…',
        keyboardType: TextInputType.url,
      );
      if (value == null || value.trim().isEmpty || !context.mounted) return;
      await importAndReport(context, value);
  }
}

Future<void> importFromClipboard(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text?.trim() ?? '';
  if (!context.mounted) return;

  if (text.isEmpty) {
    showMessage(context, l10n.tr('clipboardEmpty'));
    return;
  }
  await importAndReport(context, text);
}

Future<void> importAndReport(BuildContext context, String text) async {
  final l10n = AppLocalizations.of(context);
  final result = await Importer.importText(text);
  if (!context.mounted) return;

  final failure = result.failure;
  if (failure != null) {
    showMessage(
      context,
      l10n.fmt('subscriptionFailed', {
        'error': subscriptionErrorText(l10n, failure.code, failure.detail),
      }),
    );
    return;
  }

  switch (result.kind) {
    case ImportKind.link:
      showMessage(
        context,
        result.count == 1
            ? l10n.fmt('importedNode', {'name': result.name ?? ''})
            : l10n.fmt('importedNodes', {'count': result.count}),
      );
    case ImportKind.subscription:
      showMessage(
        context,
        l10n.fmt('importedSubscription', {
          'name': result.name ?? '',
          'count': result.count,
        }),
      );
    case ImportKind.none:
      showMessage(context, l10n.tr('nothingToImport'));
  }
}

/// QR с картинки из галереи: сканер умеет разбирать файл без запуска камеры.
Future<void> importFromImage(BuildContext context) async {
  final l10n = AppLocalizations.of(context);

  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null || !context.mounted) return;

  final controller = MobileScannerController(autoStart: false);
  String? value;
  try {
    final capture = await controller.analyzeImage(picked.path);
    for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        value = raw;
        break;
      }
    }
  } on Object {
    value = null;
  } finally {
    await controller.dispose();
  }

  if (!context.mounted) return;
  if (value == null) {
    showMessage(context, l10n.tr('qrImageEmpty'));
    return;
  }
  await importAndReport(context, value);
}

