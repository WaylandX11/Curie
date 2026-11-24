import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/profile.dart';

/// Долгое нажатие на узел: посмотреть и поправить конфиг/ссылку.
/// Изменения сохраняются в зашифрованном хранилище и переживают обновление
/// подписки (см. `Subscription.edits`).
///
/// Редактор занимает весь экран: конфиг JSON неудобно править в половинчатом
/// bottom sheet, а кнопки в нём уезжали за системную панель навигации.
Future<Profile?> showProfileEditor(BuildContext context, Profile profile) =>
    Navigator.of(context).push<Profile>(
          MaterialPageRoute<Profile>(
            fullscreenDialog: true,
            builder: (context) => _ProfileEditorPage(profile: profile),
          ),
        );

class _ProfileEditorPage extends StatefulWidget {
  const _ProfileEditorPage({required this.profile});

  final Profile profile;

  @override
  State<_ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<_ProfileEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _body;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
    _body = TextEditingController(
      text: widget.profile.isJson
          ? _pretty(widget.profile.configJson!)
          : (widget.profile.link ?? ''),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final result = _validate(
      profile: widget.profile,
      name: _name.text.trim(),
      body: _body.text.trim(),
      l10n: l10n,
    );
    if (result.updated != null) {
      Navigator.of(context).pop(result.updated);
      return;
    }
    setState(() => _error = result.error ?? l10n.tr('invalidConfig'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('editServer')),
        leading: IconButton(
          tooltip: l10n.tr('cancel'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.tr('server'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.profile.isJson
                    ? l10n.tr('serverConfig')
                    : l10n.tr('serverLink'),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 6),
            // Expanded отдаёт конфигу всё свободное место: раньше поле было
            // фиксированной высоты в половинчатом bottom sheet и почти не читалось.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _body,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: widget.profile.isJson
                      ? TextInputType.multiline
                      : TextInputType.url,
                  textInputAction: widget.profile.isJson
                      ? TextInputAction.newline
                      : TextInputAction.done,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            // SafeArea выше уже добавил отступ системной панели навигации —
            // кнопки больше не уезжают за неё.
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.tr('cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: Text(l10n.tr('save')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

({Profile? updated, String? error}) _validate({
  required Profile profile,
  required String name,
  required String body,
  required AppLocalizations l10n,
}) {
  if (name.isEmpty) return (updated: null, error: l10n.tr('unnamedServer'));

  if (!profile.isJson) {
    final uri = Uri.tryParse(body);
    if (uri == null || uri.scheme.isEmpty) {
      return (updated: null, error: l10n.tr('invalidLink'));
    }
    return (updated: profile.copyWith(name: name, link: body), error: null);
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on Object {
    return (updated: null, error: l10n.tr('invalidConfig'));
  }
  if (decoded is! Map ||
      decoded['outbounds'] is! List ||
      (decoded['outbounds'] as List).isEmpty) {
    return (updated: null, error: l10n.tr('invalidConfig'));
  }

  final outbounds = (decoded['outbounds'] as List)
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
  final proxy = outbounds.firstWhere(
    (outbound) => outbound['protocol'] != 'balancer',
    orElse: () => outbounds.first,
  );
  final details = outboundDetails(proxy);

  final updated = profile.copyWith(
    name: name,
    configJson: jsonEncode(decoded),
    address: details.address,
    port: details.port,
    protocol: details.protocol,
    network: details.network,
    security: details.security,
    hasBalancer: outbounds.any((outbound) => outbound['protocol'] == 'balancer'),
  );
  return (updated: updated, error: null);
}

String _pretty(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } on Object {
    return raw;
  }
}
