import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../models/profile.dart';
import 'app_log.dart';
import 'connection.dart';
import 'core_log.dart';
import 'geo_assets.dart';
import 'store.dart';
import 'system_locale.dart';
import 'traffic.dart';
import 'vpn.dart';
import 'xray.dart';
import 'xray_config.dart';

/// Иконка в системном трее Windows.
///
/// Окно не закрывается по X, а прячется в трей; оттуда можно показать окно,
/// включить/выключить туннель и выбрать сервер. Приложение продолжает работать
/// в фоне — planned-проверки подписок и обновлений не прерываются.
class CurieTray {
  CurieTray._();

  static final CurieTray instance = CurieTray._();

  static const _identifier = 'io.github.waylandx11.curie.tray';

  TrayIcon? _icon;
  Menu? _menu;
  Menu? _serversMenu;
  bool _started = false;
  bool _rebuilding = false;

  String get _title => 'Curie Alpha';

  String _tr(String key) {
    final values = isRussianSystemLocale()
        ? AppLocalizations.ru
        : AppLocalizations.en;
    return values[key] ?? AppLocalizations.en[key] ?? key;
  }

  Future<void> start() async {
    if (!Platform.isWindows || _started) return;
    _started = true;

    final icon = TrayIcon.createWithIdentifier(_identifier);
    if (icon == null) {
      AppLog.add('tray', 'не удалось создать иконку в трее');
      return;
    }
    _icon = icon;

    final image = ImageAsset.fromAsset('assets/tray_icon.png');
    if (image != null) icon.icon = image;
    icon.setTooltip(_title);
    // Левый клик — показать/спрятать окно, правый — меню.
    icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
    icon.addListener((event) {
      if (event is TrayIconClickedEvent) unawaited(_toggleWindow());
      if (event is TrayIconDoubleClickedEvent) unawaited(_showWindow());
    });
    icon.setVisible(true);

    await _rebuildMenu();

    Store.instance.state.addListener(_onChanged);
    Vpn.status.addListener(_onChanged);

    final window = WindowManager.instance.getCurrent();
    window?.addListener((event) {
      if (event is WindowCloseRequestedEvent) {
        // X означает «свернуть в трей». Настоящий выход — пункт меню «Выход»:
        // он сначала снимает системный прокси и останавливает xray.
        event.request.cancel();
        window.hide();
      }
    });

    AppLog.add('tray', 'иконка установлена, X сворачивает приложение в трей');
  }

  void _onChanged() => unawaited(_rebuildMenu());

  Future<void> _rebuildMenu() async {
    final icon = _icon;
    if (icon == null || _rebuilding) return;
    _rebuilding = true;
    try {
      final menu = Menu.create();
      if (menu == null) return;

      final status = Vpn.status.value;
      final busy =
          status == VpnStatus.connecting || status == VpnStatus.disconnecting;
      final toggleLabel = status == VpnStatus.connected
          ? _tr('disconnect')
          : _tr('connect');
      final toggle = MenuItem.createWithLabelAndType(
        toggleLabel,
        MenuItemType.normal,
      );
      if (toggle != null) {
        toggle.isEnabled = !busy;
        toggle.addListener((event) {
          if (event is MenuItemClickedEvent) unawaited(_toggleVpn());
        });
        menu.addItem(toggle);
      }

      final show = MenuItem.createWithLabelAndType(
        _tr('trayShow'),
        MenuItemType.normal,
      );
      if (show != null) {
        show.addListener((event) {
          if (event is MenuItemClickedEvent) unawaited(_showWindow());
        });
        menu.addItem(show);
      }

      menu.addSeparator();

      final serversMenu = Menu.create();
      if (serversMenu != null) {
        final state = Store.instance.state.value;
        final profiles = state.allProfiles;
        if (profiles.isEmpty) {
          final empty = MenuItem.createWithLabelAndType(
            _tr('trayNoServers'),
            MenuItemType.normal,
          );
          if (empty != null) {
            empty.isEnabled = false;
            serversMenu.addItem(empty);
          }
        } else {
          for (final profile in profiles) {
            final item = MenuItem.createWithLabelAndType(
              profile.name.isEmpty ? _tr('unnamedServer') : profile.name,
              MenuItemType.radio,
            );
            if (item == null) continue;
            item.state = profile.id == state.selectedId
                ? MenuItemState.checked
                : MenuItemState.unchecked;
            item.addListener((event) {
              if (event is MenuItemClickedEvent) {
                unawaited(_selectServer(profile));
              }
            });
            serversMenu.addItem(item);
          }
        }
        final serversItem = MenuItem.createWithLabelAndType(
          _tr('trayServers'),
          MenuItemType.submenu,
        );
        if (serversItem != null) {
          serversItem.submenu = serversMenu;
          menu.addItem(serversItem);
        }
      }

      menu.addSeparator();

      final quit = MenuItem.createWithLabelAndType(
        _tr('trayQuit'),
        MenuItemType.normal,
      );
      if (quit != null) {
        quit.addListener((event) {
          if (event is MenuItemClickedEvent) unawaited(_quit());
        });
        menu.addItem(quit);
      }

      icon.setContextMenu(menu);
      _menu?.dispose();
      _serversMenu?.dispose();
      _menu = menu;
      _serversMenu = serversMenu;
    } finally {
      _rebuilding = false;
    }
  }

  Future<void> _showWindow() async {
    final window = WindowManager.instance.getCurrent();
    if (window == null) return;
    if (!window.isVisible) window.show();
    window.focus();
  }

  Future<void> _toggleWindow() async {
    final window = WindowManager.instance.getCurrent();
    if (window == null) return;
    if (window.isVisible) {
      window.hide();
    } else {
      window.show();
      window.focus();
    }
  }

  Future<void> _toggleVpn() async {
    if (Vpn.status.value == VpnStatus.connected) {
      await Vpn.disconnect();
      return;
    }
    if (Vpn.status.value == VpnStatus.connecting ||
        Vpn.status.value == VpnStatus.disconnecting) {
      return;
    }
    final profile = Store.instance.state.value.selected;
    if (profile == null) {
      AppLog.add('tray', 'нет сервера для подключения');
      return;
    }
    await _connect(profile);
  }

  Future<void> _selectServer(Profile profile) async {
    await Store.instance.update(
      (state) => state.copyWith(selectedId: profile.id),
    );
    if (Vpn.status.value == VpnStatus.connected) {
      await _connect(profile);
    }
  }

  /// Тот же путь подключения, что и у кнопки на главном экране.
  Future<void> _connect(Profile profile) async {
    try {
      final settings = Store.instance.state.value.settings;
      final outbounds = await outboundsFor(profile);
      final base = baseConfigOf(profile);
      final ports = await const Xray().freePorts(2);
      final metricsPort = ports.isNotEmpty ? ports[0] : Traffic.defaultPort;
      final checkPort = ports.length > 1 ? ports[1] : metricsPort + 1;
      final logPath = await CoreLog.ensurePath();
      final geoAssetDir = await GeoAssets.assetDirectory();
      AppLog.add('tray', 'подключение: ${profile.name}');
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
    } on Object catch (e) {
      AppLog.add('tray', 'ошибка подключения: $e');
    }
  }

  Future<void> _quit() async {
    Store.instance.state.removeListener(_onChanged);
    Vpn.status.removeListener(_onChanged);
    _icon?.dispose();
    _icon = null;
    await Vpn.disconnect();
    exit(0);
  }
}
