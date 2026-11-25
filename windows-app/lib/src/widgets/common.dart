import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
}

/// Человеческий текст ошибки подписки: код переводим, подробности — как есть.
String subscriptionErrorText(AppLocalizations l10n, String code, [String? detail]) =>
    switch (code) {
      'http' => l10n.fmt('errorHttp', {'code': detail ?? ''}),
      'hwidLimit' => l10n.tr('errorHwidLimit'),
      'hwidRequired' => l10n.tr('errorHwidRequired'),
      'noLinks' => l10n.tr('errorNoLinks'),
      'noNodes' => l10n.tr('errorNoNodes'),
      _ => l10n.fmt('errorNetwork', {'detail': detail ?? code}),
    };

/// Текст из буфера обмена, если он там есть.
Future<String?> clipboardText() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

class ClipboardCopy {
  static Future<void> copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      showMessage(context, AppLocalizations.of(context).tr('copied'));
    }
  }
}

/// Одно поле ввода в диалоге. Возвращает null, если пользователь отменил.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
  TextInputType keyboardType = TextInputType.text,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PromptDialog(
      title: title,
      hint: hint,
      initial: initial,
      keyboardType: keyboardType,
    ),
  );
}

/// Контроллер живёт в состоянии диалога: иначе перестроение (например, при
/// появлении клавиатуры) сбрасывало бы набранный текст.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.keyboardType,
  });

  final String title;
  final String hint;
  final String initial;
  final TextInputType keyboardType;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        autofocus: true,
        controller: _controller,
        minLines: 1,
        maxLines: 4,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixIcon: IconButton(
            tooltip: l10n.tr('paste'),
            icon: const Icon(Icons.content_paste),
            onPressed: () async {
              final text = await clipboardText();
              if (text != null && mounted) {
                _controller.text = text;
                _controller.selection = TextSelection.collapsed(offset: text.length);
              }
            },
          ),
        ),
        onSubmitted: (text) => Navigator.of(context).pop(text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.tr('save')),
        ),
      ],
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String name) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(l10n.fmt('confirmDelete', {'name': name})),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.tr('delete')),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 1.2 ГБ / 340 МБ — коротко и без локальных сюрпризов.
String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatDateTime(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.day)}.${two(time.month)}.${time.year} ${two(time.hour)}:${two(time.minute)}';
}

String formatDate(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.day)}.${two(time.month)}.${time.year}';
}
