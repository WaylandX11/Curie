import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../services/qr_decoder.dart';

/// Выбор QR-кода из файла. Возвращает содержимое кода строкой или null.
///
/// На Android здесь была живая камера (`mobile_scanner`), но этот плагин
/// не поддерживает Windows. Экран сохраняет прежний контракт и
/// возвращает то же значение в `Navigator.pop`.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _busy = false;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final value = await QrDecoder.decodeFile(picked.path);
      if (value != null && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(value);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('scanQr'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.qr_code_scanner,
                size: 96,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.tr('qrFileHint'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                label: Text(l10n.tr('qrPickFile')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
