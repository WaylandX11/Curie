import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/app_state.dart';
import '../models/profile.dart';
import '../models/subscription.dart';
import '../services/app_log.dart';
import '../services/connection.dart';
import '../services/connection_check.dart';
import '../services/core_log.dart';
import '../services/country.dart';
import '../services/geo_assets.dart';
import '../services/ping.dart';
import '../services/store.dart';
import '../services/subscriptions.dart';
import '../services/theme_controller.dart';
import '../services/traffic.dart';
import '../services/update_notifier.dart';
import '../services/vpn.dart';
import '../services/xray.dart';
import '../services/xray_config.dart';
import '../theme.dart';
import '../widgets/add_sheet.dart';
import '../widgets/common.dart';
import '../widgets/profile_editor_sheet.dart';
import '../widgets/provider_card.dart';
import '../version.dart';
import '../widgets/update_dialog.dart';
import 'log_screen.dart';
import 'subscriptions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  String _appVersion = '';
  String _coreVersion = '';
  VpnStatus _status = VpnStatus.disconnected;

  Timer? _ticker;
  Duration _uptime = Duration.zero;
  bool _checking = false;
  CheckResult? _lastCheck;
  int _geoRestartSeen = 0;
  bool _restartingGeo = false;

  @override
  void initState() {
    super.initState();
    _status = Vpn.status.value;
    Vpn.status.addListener(_onStatus);
    UpdateNotifier.coreDialog.addListener(_onCoreDialog);
    GeoAssets.prompt.addListener(_onGeoPrompt);
    GeoAssets.restartRequested.addListener(_onGeoRestart);
    _geoRestartSeen = GeoAssets.restartRequested.value;
    _loadVersions();
    _syncTimer();
    // Уведомления могли прийти до монтирования экрана — не теряем их.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onCoreDialog();
      _onGeoPrompt();
      _onGeoRestart();
    });
  }

  @override
  void dispose() {
    Vpn.status.removeListener(_onStatus);
    UpdateNotifier.coreDialog.removeListener(_onCoreDialog);
    GeoAssets.prompt.removeListener(_onGeoPrompt);
    GeoAssets.restartRequested.removeListener(_onGeoRestart);
    _ticker?.cancel();
    super.dispose();
  }

  void _onCoreDialog() {
    final notice = UpdateNotifier.coreDialog.value;
    if (notice == null || !mounted) return;
    UpdateNotifier.dismissDialog();
    showUpdateDialog(context, notice.release, coreUpdated: notice.coreUpdated);
  }

  void _onGeoPrompt() {
    if (!GeoAssets.prompt.value || !mounted) return;
    GeoAssets.dismissPrompt();
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tr('geoAssetsNeededTitle')),
        content: Text(l10n.tr('geoAssetsNeededBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.tr('geoAssetsLater')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_downloadGeoAssets());
            },
            child: Text(l10n.tr('geoAssetsDownloadAll')),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadGeoAssets() async {
    final l10n = AppLocalizations.of(context);
    final errors = await GeoAssets.downloadAll(proxyPort: Vpn.tunnelProxyPort);
    if (!mounted) return;
    final failed = errors.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key.fileName}: ${entry.value}')
        .toList();
    if (failed.isEmpty) {
      showMessage(context, l10n.tr('geoAssetsReady'));
    } else {
      showMessage(
        context,
        l10n.fmt('geoAssetsFailed', {
          'file': 'geoip.dat / geosite.dat',
          'error': failed.join('; '),
        }),
      );
    }
  }

  void _onGeoRestart() {
    final value = GeoAssets.restartRequested.value;
    if (value <= _geoRestartSeen) return;
    _geoRestartSeen = value;
    if (!mounted || _busy || _restartingGeo) return;
    final settings = Store.instance.state.value.settings;
    final profile = Store.instance.state.value.selected;
    if (!settings.geoAssetsRestartXray ||
        profile == null ||
        Vpn.status.value != VpnStatus.connected) {
      return;
    }
    _restartingGeo = true;
    unawaited(() async {
      try {
        await _connect(profile);
      } finally {
        _restartingGeo = false;
      }
    }());
  }

  Future<void> _loadVersions() async {
    final core = Vpn.isSupported ? await const Xray().version() : '';
    if (!mounted) return;
    setState(() {
      _appVersion = displayVersion;
      _coreVersion = core.replaceFirst(
        RegExp(r'^Xray\s+', caseSensitive: false),
        '',
      );
    });
  }

  void _onStatus() {
    if (!mounted) return;
    final next = Vpn.status.value;
    setState(() => _status = next);
    _syncTimer();

    if (next == VpnStatus.error) {
      final message = Vpn.lastError.value ?? '';
      AppLog.add('vpn', 'ошибка: $message');
      _showError(message);
    }
  }

  void _syncTimer() {
    if (_status == VpnStatus.connected) {
      // Время старта приходит из сервиса: после возвращения в приложение
      // счётчик не должен начинаться заново.
      final started = Vpn.connectedAt.value ?? DateTime.now();
      _uptime = DateTime.now().difference(started);
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(
          () => _uptime = DateTime.now().difference(
            Vpn.connectedAt.value ?? started,
          ),
        );
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
      _uptime = Duration.zero;
    }
  }

  void _showError(String message) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tr('errorDetails')),
        content: SingleChildScrollView(
          child: SelectableText(
            message.isEmpty ? l10n.tr('statusError') : message,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => ClipboardCopy.copy(context, message),
            child: Text(l10n.tr('copyLog')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.tr('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle() async {
    final l10n = AppLocalizations.of(context);
    final state = Store.instance.state.value;

    if (_status == VpnStatus.connecting || _status == VpnStatus.disconnecting) {
      return;
    }

    if (_status == VpnStatus.connected) {
      await Vpn.disconnect();
      return;
    }

    if (!Vpn.isSupported) {
      showMessage(context, l10n.tr('iosNotSupported'));
      return;
    }

    final profile = state.selected;
    if (profile == null) {
      await showAddSheet(context);
      return;
    }
    await _connect(profile);
  }

  Future<void> _connect(Profile profile) async {
    final l10n = AppLocalizations.of(context);
    final settings = Store.instance.state.value.settings;

    setState(() => _busy = true);
    try {
      final outbounds = await outboundsFor(profile);
      final base = baseConfigOf(profile);
      AppLog.add(
        'vpn',
        'подключение: ${profile.name} (outbound: ${outbounds.length}, routing: ${base?['routing'] != null})',
      );
      final ports = await const Xray().freePorts(2);
      final metricsPort = ports.isNotEmpty ? ports[0] : Traffic.defaultPort;
      final checkPort = ports.length > 1 ? ports[1] : metricsPort + 1;
      // Файл может быть ещё открыт старым ядром: чистим его только на старте
      // приложения, когда туннель гарантированно не работает.
      final logPath = await CoreLog.ensurePath();
      final geoAssetDir = await GeoAssets.assetDirectory();
      _lastCheck = null;
      await Vpn.connect(
        config: buildXrayConfig(
          outbounds: outbounds,
          settings: settings,
          base: base,
          metricsPort: metricsPort,
          checkPort: checkPort,
          logPath: logPath,
          geoAssetDir: geoAssetDir,
        ),
        settings: settings,
      );
    } on VpnException catch (e) {
      AppLog.add('vpn', 'ошибка канала: ${e.code} ${e.message}');
      if (mounted) {
        showMessage(context, e.isDenied ? l10n.tr('vpnDenied') : e.message);
      }
    } catch (e, stack) {
      AppLog.add('vpn', 'ошибка ${e.runtimeType}: $e');
      AppLog.add('vpn', stack.toString().split('\n').take(3).join(' | '));
      if (mounted) _showError('${e.runtimeType}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(Profile profile) async {
    // Плитки узлов остаются нажимаемыми во время подключения — не даём
    // вторая команда переподключения встать в очередь к первой.
    if (_busy) return;
    await Store.instance.update(
      (state) => state.copyWith(selectedId: profile.id),
    );
    // Как в привычных клиентах: выбор другого узла во время работы переподключает.
    if (Vpn.status.value == VpnStatus.connected) {
      await _connect(profile);
    }
  }

  Future<void> _refresh(Subscription subscription) async {
    final l10n = AppLocalizations.of(context);
    final failure = await Subscriptions.refresh(subscription);
    if (!mounted) return;
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

  Future<void> _ping(List<Profile> profiles) async {
    final settings = Store.instance.state.value.settings;
    await Ping.measure(profiles, settings);
  }

  Future<void> _check() async {
    final port = Vpn.tunnelProxyPort;
    if (_checking || port == 0) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _checking = true;
      _lastCheck = null;
    });
    try {
      final result = await const ConnectionCheck().run(port);
      if (!mounted) return;
      setState(() => _lastCheck = result);
      showMessage(
        context,
        result.ok
            ? l10n.fmt('checkOk', {'ms': result.ms ?? 0})
            : l10n.fmt('checkFail', {'error': result.error ?? '—'}),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _editProfile(Profile profile) async {
    final updated = await showProfileEditor(context, profile);
    // id JSON-узла зависит от имени, поэтому при переименовании он меняется —
    // сравнивать его здесь нельзя, иначе правка молча потеряется.
    if (updated == null) return;
    await Store.instance.update((state) {
      if (profile.subscriptionUrl == null) {
        return state.copyWith(
          profiles: state.profiles
              .map((p) => p.id == profile.id ? updated : p)
              .toList(),
        );
      }
      final subscriptions = state.subscriptions.map((s) {
        if (s.url != profile.subscriptionUrl) return s;
        return s.copyWith(
          nodes: s.nodes.map((p) => p.id == profile.id ? updated : p).toList(),
          edits: {...s.edits, profile.id: updated.toJson()},
        );
      }).toList();
      return state.copyWith(subscriptions: subscriptions);
    });
    if (mounted) {
      showMessage(context, AppLocalizations.of(context).tr('saved'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Curie',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.4),
            ),
            Text(
              [
                if (_appVersion.isNotEmpty) 'v$_appVersion',
                if (_coreVersion.isNotEmpty) 'Xray $_coreVersion',
              ].join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<AppTheme>(
            valueListenable: ThemeController.theme,
            builder: (context, selectedTheme, _) => IconButton(
              tooltip: l10n.tr('themeToggle'),
              icon: Icon(
                selectedTheme.brightness == Brightness.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
              onPressed: ThemeController.toggle,
            ),
          ),
          // «Проверить» живёт в шапке: ссылка может быть любой длины, а
          // кнопка посередине экрана больше не мешает компактной раскладке.
          IconButton(
            tooltip: l10n.tr('checkConnection'),
            icon: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check_outlined),
            onPressed: _status == VpnStatus.connected && !_checking
                ? _check
                : null,
          ),
          IconButton(
            tooltip: l10n.tr('log'),
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const LogScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<AppState>(
          valueListenable: Store.instance.state,
          builder: (context, state, _) {
            final selected = state.selected;
            final subscription = _subscriptionOf(state, selected);
            final group = subscription?.nodes ?? state.profiles;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const SizedBox(height: 4),
                Center(child: _connectButton(l10n, theme)),
                const SizedBox(height: 8),
                Center(child: _statusLabel(l10n, theme, selected)),
                const SizedBox(height: 12),
                _updateBanner(l10n, theme),
                if (group.isNotEmpty) ...[
                  Text(
                    l10n.tr('currentProvider').toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ProviderCard(
                    profiles: group,
                    selectedId: selected?.id,
                    // Карточка показывает реально настроенный интервал, а не
                    // рекомендацию панели — как и меню «Подключение».
                    updateHours: state.settings.subscriptionUpdateHours,
                    subscription: subscription,
                    onSelect: _select,
                    onRefresh: subscription == null
                        ? null
                        : () => _refresh(subscription),
                    onPing: () => _ping(group),
                    onManage: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SubscriptionsScreen(),
                      ),
                    ),
                    onEdit: _editProfile,
                    expanded: subscription?.expanded,
                    onExpandedChanged: subscription == null
                        ? null
                        : (value) => Subscriptions.setExpanded(
                            subscription.url,
                            value,
                          ),
                  ),
                ] else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.tr('emptyTitle'),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.tr('emptyBody'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => showAddSheet(context),
                        icon: const Icon(Icons.add),
                        label: Text(l10n.tr('add')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => importFromClipboard(context),
                        icon: const Icon(Icons.content_paste),
                        label: Text(l10n.tr('paste')),
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

  Subscription? _subscriptionOf(AppState state, Profile? selected) {
    final url = selected?.subscriptionUrl;
    if (url != null) {
      for (final subscription in state.subscriptions) {
        if (subscription.url == url) return subscription;
      }
      return null;
    }
    // Выбран узел, добавленный вручную, — показываем их группу, а не подписку.
    if (state.profiles.isNotEmpty) return null;
    return state.subscriptions.isEmpty ? null : state.subscriptions.first;
  }

  Widget _updateBanner(AppLocalizations l10n, ThemeData theme) {
    return ValueListenableBuilder<UpdateNotice?>(
      valueListenable: UpdateNotifier.available,
      builder: (context, notice, _) {
        if (notice == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            color: theme.colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.system_update_alt_outlined),
              title: Text(
                l10n.fmt('updateAvailableBanner', {
                  'version': notice.release.version,
                }),
              ),
              subtitle: Text(l10n.tr('updateDaily')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showUpdateDialog(
                context,
                notice.release,
                coreUpdated: notice.coreUpdated,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statusLabel(
    AppLocalizations l10n,
    ThemeData theme,
    Profile? selected,
  ) {
    if (_status == VpnStatus.connected) {
      if (selected == null) {
        return Text(
          l10n.tr('statusConnected'),
          style: theme.textTheme.titleSmall?.copyWith(color: curieGood(theme)),
        );
      }
      final code = Country.of(selected);
      // Всё лишнее (время, скорость, «Проверить») уехало в кнопку и в шапку:
      // под кнопкой остаётся только текущий узел и результат проверки.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                code == null ? '🏳️' : Country.flag(code),
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  Country.cleanName(selected.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: curieAccent(theme),
                  ),
                ),
              ),
            ],
          ),
          if (_lastCheck != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _lastCheck!.ok
                    ? l10n.fmt('checkOk', {'ms': _lastCheck!.ms ?? 0})
                    : l10n.fmt('checkFail', {
                        'error': _lastCheck!.error ?? '—',
                      }),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _lastCheck!.ok
                      ? curieGood(theme)
                      : theme.colorScheme.error,
                ),
              ),
            ),
        ],
      );
    }

    final label = switch (_status) {
      VpnStatus.connecting => l10n.tr('statusConnecting'),
      VpnStatus.disconnecting => l10n.tr('statusDisconnecting'),
      VpnStatus.error => l10n.tr('statusError'),
      _ => l10n.tr('tapToConnect'),
    };
    final color = _status == VpnStatus.error
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(color: color),
    );
  }

  static String _formatUptime(Duration duration) {
    String two(int v) => v.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return hours > 0
        ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
        : '${two(minutes)}:${two(seconds)}';
  }

  Widget _connectButton(AppLocalizations l10n, ThemeData theme) {
    final active = _status == VpnStatus.connected;
    final busy =
        _busy ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting;
    final color = active ? curieGood(theme) : curieAccent(theme);

    return Semantics(
      button: true,
      label: active ? l10n.tr('disconnect') : l10n.tr('connect'),
      child: GestureDetector(
        onTap: busy ? null : _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 190,
          height: 190,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withValues(alpha: 0.22), Colors.transparent],
              stops: const [0.55, 1],
            ),
            border: Border.all(
              color: color.withValues(alpha: 0.85),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.22),
                blurRadius: 36,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        active
                            ? Icons.shield
                            : Icons.power_settings_new_rounded,
                        size: active ? 46 : 56,
                        color: color,
                      ),
                      // Время подключения и скорость — внутри кнопки, чтобы
                      // экран не разрастался вертикально во время работы.
                      if (active) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatUptime(_uptime),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        ValueListenableBuilder<TrafficSample>(
                          valueListenable: Traffic.speed,
                          builder: (context, sample, _) {
                            // Стрелки убраны: показываем только общую скорость
                            // и только когда она действительно есть.
                            if (sample.total <= 0) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                '${l10n.tr('speed')}: '
                                '${formatBytes(sample.total)}/s',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
