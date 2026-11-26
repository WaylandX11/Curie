import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../generated/core_info.dart';
import '../l10n/app_localizations.dart';
import '../models/app_state.dart';
import '../models/settings.dart';
import '../services/app_log.dart';
import '../services/apps.dart';
import '../services/device_identity.dart';
import '../services/geo_assets.dart';
import '../services/locale_controller.dart';
import '../services/store.dart';
import '../services/theme_controller.dart';
import '../services/update_checker.dart';
import '../services/update_notifier.dart';
import '../services/vpn.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../version.dart';
import '../widgets/update_dialog.dart';
import 'app_picker_screen.dart';
import 'log_screen.dart';

/// Настройки делятся на разделы: с главной страницы открывается только меню,
/// каждый раздел — отдельный экран со своей карточкой. Так длинный список не
/// приходится прокручивать целиком ради одной настройки.
const _dnsPresets = ['77.88.8.8', '1.1.1.1', '8.8.8.8', '9.9.9.9'];
const _dnsPanel = '__panel__';
const _dnsCustom = '__custom__';

Future<void> _change(Settings Function(Settings settings) change) => Store
    .instance
    .update((state) => state.copyWith(settings: change(state.settings)));

String _tunnelModeKey(TunnelMode mode) => switch (mode) {
  TunnelMode.tun => 'tunnelModeTun',
  TunnelMode.tunProxy => 'tunnelModeTunProxy',
  TunnelMode.proxy => 'tunnelModeProxy',
};

Future<void> _editSocksPort(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final current = Store.instance.state.value.settings.effectiveSocksPort;
  final value = await promptText(
    context,
    title: l10n.tr('socksPort'),
    hint: '1024–65535',
    initial: '$current',
    keyboardType: TextInputType.number,
  );
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed < 1024 || parsed > 65535) return;
  await _change((s) => s.copyWith(socksPort: parsed));
}

Future<void> _editSocksText(
  BuildContext context, {
  required String title,
  required String current,
  required Settings Function(Settings settings, String value) save,
  bool obscureText = false,
}) async {
  final value = await promptText(
    context,
    title: title,
    hint: obscureText ? '' : current,
    initial: current,
    obscureText: obscureText,
  );
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == current) return;
  await _change((s) => save(s, trimmed));
}

Future<void> _pickDns(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final settings = Store.instance.state.value.settings;

  final chosen = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              settings.dnsUsePanel
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: settings.dnsUsePanel
                  ? curieAccent(Theme.of(context))
                  : null,
            ),
            title: Text(l10n.tr('dnsFromSubscription')),
            onTap: () => Navigator.of(context).pop(_dnsPanel),
          ),
          for (final preset in _dnsPresets)
            ListTile(
              leading: Icon(
                !settings.dnsUsePanel && preset == settings.dns
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: !settings.dnsUsePanel && preset == settings.dns
                    ? curieAccent(Theme.of(context))
                    : null,
              ),
              title: Text(preset),
              onTap: () => Navigator.of(context).pop(preset),
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.tr('dnsCustom')),
            onTap: () => Navigator.of(context).pop(_dnsCustom),
          ),
        ],
      ),
    ),
  );
  if (chosen == null || !context.mounted) return;

  if (chosen == _dnsPanel) {
    await _change((settings) => settings.copyWith(dnsUsePanel: true));
    return;
  }
  if (chosen == _dnsCustom) {
    final value = await promptText(
      context,
      title: l10n.tr('dns'),
      hint: l10n.tr('dnsCustomHint'),
      initial: settings.dns,
      keyboardType: TextInputType.number,
    );
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await _change(
      (settings) => settings.copyWith(dns: trimmed, dnsUsePanel: false),
    );
    return;
  }
  await _change(
    (settings) => settings.copyWith(dns: chosen, dnsUsePanel: false),
  );
}

Future<void> _pickPingProfile(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final settings = Store.instance.state.value.settings;
  final chosen = await showModalBottomSheet<PingProfile>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final profile in PingProfile.values)
            ListTile(
              leading: Icon(
                profile == settings.pingProfile
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: profile == settings.pingProfile
                    ? curieAccent(Theme.of(context))
                    : null,
              ),
              title: Text(l10n.tr(_pingProfileKey(profile))),
              onTap: () => Navigator.of(context).pop(profile),
            ),
        ],
      ),
    ),
  );
  if (chosen == null || !context.mounted) return;
  await _change((s) => s.copyWith(pingProfile: chosen));
}

String _pingProfileKey(PingProfile profile) => switch (profile) {
  PingProfile.single => 'pingProfileSingle',
  PingProfile.double => 'pingProfileDouble',
  PingProfile.keepAlive => 'pingProfileKeepAlive',
};

String _logLevelKey(XrayLogLevel level) => switch (level) {
  XrayLogLevel.debug => 'logLevelDebug',
  XrayLogLevel.info => 'logLevelInfo',
  XrayLogLevel.warning => 'logLevelWarning',
  XrayLogLevel.error => 'logLevelError',
  XrayLogLevel.none => 'logLevelNone',
};

String _routingKey(RoutingMode mode) => switch (mode) {
  RoutingMode.all => 'routingAll',
  RoutingMode.onlySelected => 'routingOnly',
  RoutingMode.bypassSelected => 'routingBypass',
};

Future<void> _editPingUrl(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final current = Store.instance.state.value.settings.pingUrl;
  final value = await promptText(
    context,
    title: l10n.tr('pingUrl'),
    hint: l10n.tr('pingUrlHint'),
    initial: current,
    keyboardType: TextInputType.url,
  );
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == current) return;
  await _change((s) => s.copyWith(pingUrl: trimmed));
}

Future<void> _editHours(
  BuildContext context, {
  required String title,
  required int current,
  required int min,
  required int max,
  required Future<void> Function(int hours) save,
}) async {
  final value = await promptText(
    context,
    title: title,
    hint: '$min–$max',
    initial: '$current',
    keyboardType: TextInputType.number,
  );
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null) return;
  await save(parsed.clamp(min, max));
}

Future<void> _editMtu(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  await _editHours(
    context,
    title: l10n.tr('mtu'),
    current: Store.instance.state.value.settings.mtu,
    min: 576,
    max: 1500,
    save: (value) => _change((settings) => settings.copyWith(mtu: value)),
  );
}

Future<void> _editGeoUrl(BuildContext context, GeoAssetKind kind) async {
  final l10n = AppLocalizations.of(context);
  final settings = Store.instance.state.value.settings;
  final current = GeoAssets.urlFor(kind, settings);
  final value = await promptText(
    context,
    title: l10n.tr(
      kind == GeoAssetKind.geoip ? 'geoAssetsGeoipUrl' : 'geoAssetsGeositeUrl',
    ),
    hint: l10n.fmt('geoAssetsDefaultHint', {'url': GeoAssets.defaultUrl(kind)}),
    initial: current,
    keyboardType: TextInputType.url,
  );
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == current || !context.mounted) return;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) {
    showMessage(context, l10n.tr('geoAssetsBadUrl'));
    return;
  }
  await _change(
    (s) => s.copyWith(
      geoipUrl: kind == GeoAssetKind.geoip ? trimmed : null,
      geositeUrl: kind == GeoAssetKind.geosite ? trimmed : null,
    ),
  );
  await GeoAssets.refreshStatus();
}

Future<void> _downloadGeoAsset(BuildContext context, GeoAssetKind kind) async {
  final l10n = AppLocalizations.of(context);
  final proxyPort = Vpn.tunnelProxyPort;
  AppLog.add(
    'geo',
    'обновление ${kind.fileName}: начало'
        '${proxyPort > 0 ? ' (через туннель)' : ' (напрямую)'}',
  );
  try {
    final changed = await GeoAssets.download(kind, proxyPort: proxyPort);
    AppLog.add('geo', 'обновление ${kind.fileName}: успешно');
    if (!context.mounted) return;
    showMessage(context, l10n.fmt('geoAssetsUpdated', {'file': kind.fileName}));
    if (changed) unawaited(GeoAssets.refreshStatus());
  } on Object catch (e) {
    AppLog.add('geo', 'обновление ${kind.fileName}: ошибка — $e');
    if (!context.mounted) return;
    showMessage(
      context,
      l10n.fmt('geoAssetsFailed', {'file': kind.fileName, 'error': '$e'}),
    );
  }
}

Future<void> _pickGeoAsset(BuildContext context, GeoAssetKind kind) async {
  final l10n = AppLocalizations.of(context);
  try {
    final changed = await GeoAssets.pickAndImport(kind);
    if (!changed || !context.mounted) return;
    showMessage(context, l10n.fmt('geoAssetsUpdated', {'file': kind.fileName}));
  } on Object catch (_) {
    if (!context.mounted) return;
    showMessage(context, l10n.tr('geoAssetsInvalid'));
  }
}

String _geoStatusText(AppLocalizations l10n, GeoAssetInfo info) {
  if (!info.exists) return l10n.tr('geoAssetsStatusMissing');
  final date = info.updatedAt?.toLocal().toString().split('.').first ?? '';
  return l10n.fmt('geoAssetsStatusReady', {'date': date});
}

/// Карточка geo-баз внутри раздела «Маршрутизация». Состояние файлов прочитано
/// асинхронно, поэтому виджет сам обновляет его при открытии экрана.
class _GeoAssetsTiles extends StatefulWidget {
  const _GeoAssetsTiles();

  @override
  State<_GeoAssetsTiles> createState() => _GeoAssetsTilesState();
}

class _GeoAssetsTilesState extends State<_GeoAssetsTiles> {
  @override
  void initState() {
    super.initState();
    unawaited(GeoAssets.refreshStatus());
  }

  Widget _fileCard(
    BuildContext context,
    AppLocalizations l10n,
    GeoAssetInfo info,
    double? progress,
  ) {
    final downloading = progress != null;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.storage_outlined),
        title: Text(info.kind.fileName),
        subtitle: downloading
            ? Text(
                progress > 0
                    ? l10n.fmt('geoAssetsProgress', {
                        'percent': '${(progress * 100).round()}',
                      })
                    : l10n.fmt('geoAssetsUpdating', {
                        'file': info.kind.fileName,
                      }),
              )
            : Text(_geoStatusText(l10n, info)),
        trailing: downloading
            ? SizedBox(
                width: 112,
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                ),
              )
            : IconButton(
                tooltip: l10n.tr('geoAssetsDownload'),
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _downloadGeoAsset(context, info.kind),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<AppState>(
      valueListenable: Store.instance.state,
      builder: (context, state, _) {
        final settings = state.settings;
        return ValueListenableBuilder<List<GeoAssetInfo>>(
          valueListenable: GeoAssets.status,
          builder: (context, saved, _) {
            final infos = saved.isEmpty
                ? GeoAssetKind.values
                      .map(
                        (kind) => GeoAssetInfo(
                          kind: kind,
                          url: GeoAssets.urlFor(kind, settings),
                          exists: false,
                          size: 0,
                          updatedAt: GeoAssets.updatedAtFor(kind, settings),
                        ),
                      )
                      .toList()
                : saved;
            return ValueListenableBuilder<Map<GeoAssetKind, double>>(
              valueListenable: GeoAssets.progress,
              builder: (context, progress, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final info in infos)
                    _fileCard(context, l10n, info, progress[info.kind]),
                  for (final kind in GeoAssetKind.values)
                    ListTile(
                      leading: const Icon(Icons.link),
                      title: Text(
                        l10n.tr(
                          kind == GeoAssetKind.geoip
                              ? 'geoAssetsGeoipUrl'
                              : 'geoAssetsGeositeUrl',
                        ),
                      ),
                      subtitle: Text(GeoAssets.urlFor(kind, settings)),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editGeoUrl(context, kind),
                    ),
                  for (final kind in GeoAssetKind.values)
                    ListTile(
                      leading: const Icon(Icons.folder_open_outlined),
                      title: Text(
                        l10n.fmt('geoAssetsChoose', {'file': kind.fileName}),
                      ),
                      onTap: () => _pickGeoAsset(context, kind),
                    ),
                  SwitchListTile(
                    title: Text(l10n.tr('geoAssetsAutoUpdate')),
                    value: settings.geoAssetsAutoUpdate,
                    onChanged: (value) =>
                        _change((s) => s.copyWith(geoAssetsAutoUpdate: value)),
                  ),
                  if (settings.geoAssetsAutoUpdate)
                    SwitchListTile(
                      title: Text(l10n.tr('geoAssetsWifiOnly')),
                      value: settings.geoAssetsWifiOnly,
                      onChanged: (value) =>
                          _change((s) => s.copyWith(geoAssetsWifiOnly: value)),
                    ),
                  SwitchListTile(
                    title: Text(l10n.tr('geoAssetsRestart')),
                    value: settings.geoAssetsRestartXray,
                    onChanged: (value) =>
                        _change((s) => s.copyWith(geoAssetsRestartXray: value)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(l10n.tr('geoAssetsInterval')),
                    subtitle: Text('${settings.geoAssetsUpdateHours}'),
                    onTap: () => _editHours(
                      context,
                      title: l10n.tr('geoAssetsInterval'),
                      current: settings.geoAssetsUpdateHours,
                      min: Settings.minGeoAssetsUpdateHours,
                      max: Settings.maxGeoAssetsUpdateHours,
                      save: (hours) => _change(
                        (s) => s.copyWith(geoAssetsUpdateHours: hours),
                      ),
                    ),
                  ),
                  if (settings.geoAssetsAutoUpdate &&
                      settings.geoAssetsWifiOnly)
                    _hint(context, l10n.tr('geoAssetsSkipMobile')),
                  if (Vpn.status.value == VpnStatus.connected)
                    _hint(context, l10n.tr('reconnectHint')),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> _pickLogLevel(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final current = Store.instance.state.value.settings.xrayLogLevel;
  final chosen = await showModalBottomSheet<XrayLogLevel>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final level in XrayLogLevel.values)
            ListTile(
              leading: Icon(
                level == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: level == current ? curieAccent(Theme.of(context)) : null,
              ),
              title: Text(l10n.tr(_logLevelKey(level))),
              onTap: () => Navigator.of(context).pop(level),
            ),
        ],
      ),
    ),
  );
  if (chosen == null || !context.mounted) return;
  await _change((settings) => settings.copyWith(xrayLogLevel: chosen));
}

Widget _group(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  required List<Widget> children,
}) {
  final theme = Theme.of(context);
  return Card(
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: curieAccent(theme).withValues(alpha: 0.12),
                child: Icon(icon, color: curieAccent(theme), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ...children,
      ],
    ),
  );
}

Widget _hint(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
  child: Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  ),
);

class _Section {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.screen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;
}

/// Меню разделов. Здесь нет элементов управления — только переход внутрь.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('settings'))),
      body: SafeArea(
        child: ValueListenableBuilder<AppState>(
          valueListenable: Store.instance.state,
          builder: (context, state, _) {
            final settings = state.settings;
            final locale = LocaleController.locale.value;
            final languageKey = locale == null
                ? 'languageSystem'
                : locale.languageCode == 'ru'
                ? 'languageRussian'
                : 'languageEnglish';
            final sections = <_Section>[
              _Section(
                icon: Icons.vpn_key_outlined,
                title: l10n.tr('sectionRouting'),
                subtitle: l10n.tr(_routingKey(settings.routingMode)),
                screen: const RoutingSettingsScreen(),
              ),
              _Section(
                icon: Icons.cloud_sync_outlined,
                title: l10n.tr('sectionConnection'),
                subtitle: settings.autoUpdateSubscriptions
                    ? l10n.fmt('updateEvery', {
                        'hours': settings.subscriptionUpdateHours,
                      })
                    : l10n.tr('updateManual'),
                screen: const ConnectionSettingsScreen(),
              ),
              _Section(
                icon: Icons.palette_outlined,
                title: l10n.tr('sectionAppearance'),
                subtitle:
                    '${l10n.tr(ThemeController.theme.value.labelKey)} · '
                    '${l10n.tr(languageKey)}',
                screen: const AppearanceSettingsScreen(),
              ),
              _Section(
                icon: Icons.receipt_long_outlined,
                title: l10n.tr('sectionLogs'),
                subtitle: l10n.tr(_logLevelKey(settings.xrayLogLevel)),
                screen: const LogsSettingsScreen(),
              ),
              _Section(
                icon: Icons.science_outlined,
                title: l10n.tr('sectionExperimental'),
                subtitle: settings.useRustCore
                    ? l10n.tr('on')
                    : l10n.tr('off'),
                screen: const ExperimentalSettingsScreen(),
              ),
              _Section(
                icon: Icons.info_outline,
                title: l10n.tr('sectionAbout'),
                subtitle: displayVersion,
                screen: const AboutSettingsScreen(),
              ),
            ];

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              itemCount: sections.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final section = sections[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: curieAccent(theme)
                          .withValues(alpha: 0.12),
                      child: Icon(
                        section.icon,
                        color: curieAccent(theme),
                        size: 20,
                      ),
                    ),
                    title: Text(section.title),
                    subtitle: Text(section.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => section.screen),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class RoutingSettingsScreen extends StatelessWidget {
  const RoutingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('sectionRouting'))),
      body: SafeArea(
        child: ValueListenableBuilder<AppState>(
          valueListenable: Store.instance.state,
          builder: (context, state, _) {
            final settings = state.settings;
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _group(
                  context,
                  icon: Icons.vpn_key_outlined,
                  title: l10n.tr('sectionRouting'),
                  subtitle: l10n.tr('reconnectHint'),
                  children: [
                    if (!Apps.isSupported)
                      ListTile(title: Text(l10n.tr('appsUnavailable')))
                    else
                      RadioGroup<RoutingMode>(
                        groupValue: settings.routingMode,
                        onChanged: (value) {
                          if (value != null) {
                            _change((s) => s.copyWith(routingMode: value));
                          }
                        },
                        child: Column(
                          children: [
                            RadioListTile<RoutingMode>(
                              value: RoutingMode.all,
                              title: Text(l10n.tr('routingAll')),
                            ),
                            RadioListTile<RoutingMode>(
                              value: RoutingMode.onlySelected,
                              title: Text(l10n.tr('routingOnly')),
                            ),
                            RadioListTile<RoutingMode>(
                              value: RoutingMode.bypassSelected,
                              title: Text(l10n.tr('routingBypass')),
                            ),
                          ],
                        ),
                      ),
                    if (Apps.isSupported)
                      ListTile(
                        leading: const Icon(Icons.apps),
                        title: Text(l10n.tr('chooseApps')),
                        subtitle: Text(
                          l10n.fmt('appsSelected', {
                            'count': settings.selectedApps.length,
                          }),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: settings.routingMode == RoutingMode.all
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AppPickerScreen(
                                    mode: settings.routingMode,
                                  ),
                                ),
                              ),
                      ),
                  ],
                ),
                _group(
                  context,
                  icon: Icons.public_outlined,
                  title: l10n.tr('sectionGeoAssets'),
                  children: const [_GeoAssetsTiles()],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ConnectionSettingsScreen extends StatelessWidget {
  const ConnectionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('sectionConnection'))),
      body: SafeArea(
        child: ValueListenableBuilder<AppState>(
          valueListenable: Store.instance.state,
          builder: (context, state, _) {
            final settings = state.settings;
            final panelHours =
                state.subscriptions
                    .map((s) => s.updateIntervalHours)
                    .toSet()
                    .toList()
                  ..sort();
            final panelHint = panelHours.isEmpty
                ? '—'
                : panelHours.map((h) => '$h').join(', ');

            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _group(
                  context,
                  icon: Icons.cloud_sync_outlined,
                  title: l10n.tr('sectionConnection'),
                  children: [
                    SwitchListTile(
                      title: Text(l10n.tr('autoUpdate')),
                      value: settings.autoUpdateSubscriptions,
                      onChanged: (value) => _change(
                        (s) => s.copyWith(autoUpdateSubscriptions: value),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(l10n.tr('autoUpdateHours')),
                      subtitle: Text(
                        '${settings.subscriptionUpdateHours} · '
                        '${l10n.fmt('autoUpdateHoursHint', {'panel': panelHint})}',
                      ),
                      onTap: () => _editHours(
                        context,
                        title: l10n.tr('autoUpdateHours'),
                        current: settings.subscriptionUpdateHours,
                        min: Settings.minSubscriptionUpdateHours,
                        max: Settings.maxSubscriptionUpdateHours,
                        save: (hours) => _change(
                          (s) => s.copyWith(subscriptionUpdateHours: hours),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.fingerprint),
                      title: Text(l10n.tr('hwid')),
                      subtitle: Text(l10n.tr('hwidDescription')),
                      value: settings.sendHwid,
                      onChanged: (value) async {
                        await _change((s) => s.copyWith(sendHwid: value));
                        if (value) await DeviceIdentity.ensureId();
                      },
                    ),
                    RadioGroup<PingMode>(
                      groupValue: settings.pingMode,
                      onChanged: (value) {
                        if (value != null) {
                          _change((s) => s.copyWith(pingMode: value));
                        }
                      },
                      child: Column(
                        children: [
                          RadioListTile<PingMode>(
                            value: PingMode.tcp,
                            title: Text(l10n.tr('pingModeTcp')),
                          ),
                          RadioListTile<PingMode>(
                            value: PingMode.proxy,
                            title: Text(l10n.tr('pingModeProxy')),
                          ),
                        ],
                      ),
                    ),
                    if (settings.pingMode == PingMode.proxy)
                      ListTile(
                        title: Text(l10n.tr('pingProfile')),
                        trailing: Text(
                          l10n.tr(_pingProfileKey(settings.pingProfile)),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        onTap: () => _pickPingProfile(context),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.tr('pingTimeout'),
                            style: theme.textTheme.titleSmall,
                          ),
                          Slider(
                            value: settings.pingTimeoutSeconds.toDouble(),
                            min: Settings.minPingTimeout.toDouble(),
                            max: Settings.maxPingTimeout.toDouble(),
                            divisions:
                                Settings.maxPingTimeout -
                                Settings.minPingTimeout,
                            label:
                                '${settings.pingTimeoutSeconds} '
                                '${l10n.tr('secondsShort')}',
                            onChanged: (value) => _change(
                              (s) =>
                                  s.copyWith(pingTimeoutSeconds: value.round()),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${Settings.minPingTimeout} '
                                '${l10n.tr('secondsShort')}',
                                style: theme.textTheme.labelSmall,
                              ),
                              Text(
                                '${settings.pingTimeoutSeconds} '
                                '${l10n.tr('secondsShort')}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              Text(
                                '${Settings.maxPingTimeout} '
                                '${l10n.tr('secondsShort')}',
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (settings.pingMode == PingMode.proxy)
                      ListTile(
                        leading: const Icon(Icons.link),
                        title: Text(l10n.tr('pingUrl')),
                        subtitle: Text(settings.pingUrl),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editPingUrl(context),
                      ),
                  ],
                ),
                _group(
                  context,
                  icon: Icons.vpn_key_outlined,
                  title: l10n.tr('tunnelMode'),
                  children: [
                    RadioGroup<TunnelMode>(
                      groupValue: settings.tunnelMode,
                      onChanged: (value) {
                        if (value != null) {
                          _change((s) => s.copyWith(tunnelMode: value));
                        }
                      },
                      child: Column(
                        children: [
                          for (final mode in TunnelMode.values)
                            RadioListTile<TunnelMode>(
                              value: mode,
                              title: Text(l10n.tr(_tunnelModeKey(mode))),
                            ),
                        ],
                      ),
                    ),
                    if (settings.tunnelMode.hasProxy) ...[
                      _hint(context, l10n.tr('tunnelModeHint')),
                      ListTile(
                        leading: const Icon(Icons.numbers),
                        title: Text(l10n.tr('socksPort')),
                        subtitle: Text('${settings.effectiveSocksPort}'),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editSocksPort(context),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.lock_outline),
                        title: Text(l10n.tr('socksAuth')),
                        value: settings.socksAuth,
                        onChanged: (value) => _change(
                          (s) => s.copyWith(socksAuth: value),
                        ),
                      ),
                      if (settings.socksAuth) ...[
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(l10n.tr('socksUsername')),
                          subtitle: Text(settings.socksUsername),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _editSocksText(
                            context,
                            title: l10n.tr('socksUsername'),
                            current: settings.socksUsername,
                            save: (s, value) =>
                                s.copyWith(socksUsername: value),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.password_outlined),
                          title: Text(l10n.tr('socksPassword')),
                          subtitle: Text('•' * 8),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _editSocksText(
                            context,
                            title: l10n.tr('socksPassword'),
                            current: settings.effectiveSocksPassword,
                            obscureText: true,
                            save: (s, value) =>
                                s.copyWith(socksPassword: value),
                          ),
                        ),
                      ],
                    ],
                    if (Vpn.status.value == VpnStatus.connected)
                      _hint(context, l10n.tr('reconnectHint')),
                  ],
                ),
                _group(
                  context,
                  icon: Icons.dns_outlined,
                  title: l10n.tr('networkSettings'),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: Text(l10n.tr('dns')),
                      subtitle: Text(
                        settings.dnsUsePanel
                            ? l10n.tr('dnsFromSubscription')
                            : '${l10n.tr('dnsActive')}: ${settings.dns}',
                      ),
                      onTap: () => _pickDns(context),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.route_outlined),
                      title: Text(l10n.tr('dnsTunnel')),
                      subtitle: Text(l10n.tr('dnsTunnelHint')),
                      value: settings.dnsRoute == DnsRoute.tunnel,
                      onChanged: (value) => _change(
                        (s) => s.copyWith(
                          dnsRoute: value ? DnsRoute.tunnel : DnsRoute.direct,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: Text(l10n.tr('bypassLan')),
                      value: settings.bypassLan,
                      onChanged: (value) =>
                          _change((s) => s.copyWith(bypassLan: value)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings_ethernet),
                      title: Text(l10n.tr('mtu')),
                      subtitle: Text('${settings.mtu}'),
                      onTap: () => _editMtu(context),
                    ),
                    if (Vpn.status.value == VpnStatus.connected)
                      _hint(context, l10n.tr('reconnectHint')),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('sectionAppearance'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _group(
              context,
              icon: Icons.palette_outlined,
              title: l10n.tr('sectionAppearance'),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ValueListenableBuilder<AppTheme>(
                    valueListenable: ThemeController.theme,
                    builder: (context, selectedTheme, _) => Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final variant in AppTheme.values)
                          ChoiceChip(
                            label: Text(l10n.tr(variant.labelKey)),
                            selected: variant == selectedTheme,
                            onSelected: (_) => ThemeController.set(variant),
                          ),
                      ],
                    ),
                  ),
                ),
                ValueListenableBuilder<Locale?>(
                  valueListenable: LocaleController.locale,
                  builder: (context, locale, _) => RadioGroup<String>(
                    groupValue: locale?.languageCode ?? 'system',
                    onChanged: (value) => LocaleController.set(
                      value == null || value == 'system' ? null : Locale(value),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: 'system',
                          title: Text(l10n.tr('languageSystem')),
                        ),
                        RadioListTile<String>(
                          value: 'ru',
                          title: Text(l10n.tr('languageRussian')),
                        ),
                        RadioListTile<String>(
                          value: 'en',
                          title: Text(l10n.tr('languageEnglish')),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LogsSettingsScreen extends StatelessWidget {
  const LogsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('sectionLogs'))),
      body: SafeArea(
        child: ValueListenableBuilder<AppState>(
          valueListenable: Store.instance.state,
          builder: (context, state, _) {
            final settings = state.settings;
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _group(
                  context,
                  icon: Icons.receipt_long_outlined,
                  title: l10n.tr('sectionLogs'),
                  subtitle: l10n.tr('xrayLogEnabledHint'),
                  children: [
                    SwitchListTile(
                      title: Text(l10n.tr('xrayLogEnabled')),
                      subtitle: Text(l10n.tr('xrayLogEnabledHint')),
                      value: settings.xrayLogEnabled,
                      onChanged: (value) =>
                          _change((s) => s.copyWith(xrayLogEnabled: value)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: Text(l10n.tr('logLevel')),
                      trailing: Text(
                        l10n.tr(_logLevelKey(settings.xrayLogLevel)),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      onTap: () => _pickLogLevel(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(l10n.tr('logRetention')),
                      subtitle: Text(
                        l10n.fmt('logRetentionHint', {
                          'hours': settings.xrayLogRetentionHours,
                        }),
                      ),
                      onTap: () => _editHours(
                        context,
                        title: l10n.tr('logRetention'),
                        current: settings.xrayLogRetentionHours,
                        min: Settings.minLogRetentionHours,
                        max: Settings.maxLogRetentionHours,
                        save: (hours) => _change(
                          (s) => s.copyWith(xrayLogRetentionHours: hours),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: Text(l10n.tr('logViewer')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LogScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// На Windows Rust-ядро недоступно: раздел нужен только чтобы показать,
/// что настройка не потерялась при переносе состояния с Android.
class ExperimentalSettingsScreen extends StatelessWidget {
  const ExperimentalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('sectionExperimental'))),
      body: SafeArea(
        child: ValueListenableBuilder<AppState>(
          valueListenable: Store.instance.state,
          builder: (context, state, _) {
            return ListView(
              children: [
                _group(
                  context,
                  icon: Icons.science_outlined,
                  title: l10n.tr('sectionExperimental'),
                  children: [
                    SwitchListTile(
                      value: state.settings.useRustCore,
                      title: Text(l10n.tr('useRustCore')),
                      onChanged: null,
                    ),
                    _hint(context, l10n.tr('useRustCoreHint')),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('sectionAbout'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _group(
              context,
              icon: Icons.info_outline,
              title: l10n.tr('sectionAbout'),
              children: const [_AboutTiles()],
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutTiles extends StatefulWidget {
  const _AboutTiles();

  @override
  State<_AboutTiles> createState() => _AboutTilesState();
}

class _AboutTilesState extends State<_AboutTiles> {
  String _appVersion = '';
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _appVersion = displayVersion);
  }

  Future<void> _checkUpdates() async {
    if (_checkingUpdate) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _checkingUpdate = true);
    try {
      final result = await UpdateChecker.check(
        force: true,
        // Диалог показывает этот экран сам; отметка «уже показывали» в
        // UpdateChecker всё равно ставится, чтобы фон его не повторил.
        showCoreDialog: false,
      );
      if (!mounted) return;
      if (result == UpdateCheckResult.available) {
        final notice = UpdateNotifier.available.value;
        if (notice != null) {
          await showUpdateDialog(
            context,
            notice.release,
            coreUpdated: notice.coreUpdated,
          );
        }
        return;
      }
      showMessage(
        context,
        result == UpdateCheckResult.error
            ? l10n.tr('updateError')
            : l10n.tr('updateNone'),
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.system_update_alt_outlined),
          title: Text(l10n.tr('checkUpdates')),
          subtitle: Text(
            l10n.fmt('updateCurrent', {
              'version': _appVersion.isEmpty ? '—' : _appVersion,
            }),
          ),
          trailing: _checkingUpdate
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _checkingUpdate ? null : _checkUpdates,
        ),
        ListTile(
          leading: const Icon(Icons.memory),
          title: Text(l10n.tr('coreVersion')),
          subtitle: Text(libXrayVersion),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(l10n.tr('licenses')),
          subtitle: const Text(
            'Curie — Curie Source-Available License 1.0 · libXray — MIT · '
            'Xray-core — MPL-2.0 · Flutter — BSD-3',
          ),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Curie',
            applicationVersion: _appVersion,
            applicationLegalese: l10n.tr('licenseLegalese'),
          ),
        ),
      ],
    );
  }
}
