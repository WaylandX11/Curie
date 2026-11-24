import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../generated/build_info.dart';
import '../generated/core_info.dart';
import '../models/app_state.dart';
import '../models/settings.dart';
import '../services/apps.dart';
import '../services/device_identity.dart';
import '../services/locale_controller.dart';
import '../services/store.dart';
import '../services/theme_controller.dart';
import '../services/update.dart';
import '../services/vpn.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'app_picker_screen.dart';
import 'log_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _dnsPresets = ['77.88.8.8', '1.1.1.1', '8.8.8.8', '9.9.9.9'];
  static const _dnsPanel = '__panel__';
  static const _dnsCustom = '__custom__';

  Future<void> _change(Settings Function(Settings settings) change) => Store
      .instance
      .update((state) => state.copyWith(settings: change(state.settings)));

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

  Future<void> _editMtu(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final current = Store.instance.state.value.settings.mtu;
    final value = await promptText(
      context,
      title: l10n.tr('mtu'),
      hint: '1500',
      initial: '$current',
      keyboardType: TextInputType.number,
    );
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return;
    await _change(
      (settings) => settings.copyWith(mtu: parsed.clamp(576, 1500)),
    );
  }

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

            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _section(l10n.tr('theme'), theme),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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

                _section(l10n.tr('routing'), theme),
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
                if (Apps.isSupported && settings.routingMode != RoutingMode.all)
                  ListTile(
                    leading: const Icon(Icons.apps),
                    title: Text(l10n.tr('chooseApps')),
                    subtitle: Text(
                      l10n.fmt('appsSelected', {
                        'count': settings.selectedApps.length,
                      }),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            AppPickerScreen(mode: settings.routingMode),
                      ),
                    ),
                  ),
                if (Vpn.status.value == VpnStatus.connected)
                  _hint(context, l10n.tr('reconnectHint')),

                _section(l10n.tr('dns'), theme),
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

                _section(l10n.tr('subscriptions'), theme),
                SwitchListTile(
                  title: Text(l10n.tr('autoUpdate')),
                  value: settings.autoUpdateSubscriptions,
                  onChanged: (value) => _change(
                    (s) => s.copyWith(autoUpdateSubscriptions: value),
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
                if (settings.sendHwid)
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(72, 0, 20, 0),
                    title: Text(
                      state.deviceId ?? l10n.tr('hwidEmpty'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),

                _section(l10n.tr('ping'), theme),
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
                            Settings.maxPingTimeout - Settings.minPingTimeout,
                        label:
                            '${settings.pingTimeoutSeconds} '
                            '${l10n.tr('secondsShort')}',
                        onChanged: (value) => _change(
                          (s) => s.copyWith(pingTimeoutSeconds: value.round()),
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

                _section(l10n.tr('language'), theme),
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

                _section(l10n.tr('about'), theme),
                const _AboutTiles(),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(l10n.tr('log')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LogScreen()),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _section(String title, ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
    child: Text(
      title,
      style: theme.textTheme.labelLarge?.copyWith(
        color: curieAccent(theme),
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _hint(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
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
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = buildStamp.isEmpty
          ? '${info.version}+${info.buildNumber}'
          : buildStamp;
    });
  }

  Future<void> _openLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw 'cannot launch';
      }
    } on Object catch (_) {
      if (mounted) {
        showMessage(context, AppLocalizations.of(context).tr('updateError'));
      }
    }
  }

  Future<void> _checkUpdates() async {
    if (_checkingUpdate) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _checkingUpdate = true);
    try {
      final release = await GithubUpdate.fetchLatest();
      if (!mounted) return;
      if (release == null ||
          !GithubUpdate.isNewer(release.version, _appVersion)) {
        showMessage(context, l10n.tr('updateNone'));
        return;
      }

      final abi = await Vpn.abi() ?? '';
      final download = release.downloadUrlFor(abi);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.tr('updateAvailable')),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.fmt('updateFound', {'version': release.version})),
                const SizedBox(height: 4),
                Text(
                  l10n.fmt('updateCurrent', {'version': _appVersion}),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
                _openLink(release.htmlUrl);
              },
              child: Text(l10n.tr('updateOpenRelease')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openLink(download);
              },
              child: Text(l10n.tr('updateDownload')),
            ),
          ],
        ),
      );
    } on Object catch (_) {
      if (mounted) showMessage(context, l10n.tr('updateError'));
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
