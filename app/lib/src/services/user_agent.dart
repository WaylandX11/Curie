import 'dart:io';

import '../generated/build_info.dart';
import '../generated/core_info.dart';
import 'xray.dart';

/// Заголовок подписок: Curie/версия приложения/версия Xray/ОС.
/// Панели по нему определяют клиента и формат ответа.
String formatUserAgent({
  required String appVersion,
  required String xrayVersion,
  String? platform,
}) {
  final app = appVersion.trim().isEmpty ? '0.1' : appVersion.trim();
  final core = xrayVersion
      .trim()
      .replaceFirst(RegExp(r'^xray', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), '');
  final xray = core.isEmpty ? libXrayVersion : core;
  final os = (platform ?? Platform.operatingSystem).trim();
  return ['Curie', app, xray, os].where((part) => part.isNotEmpty).join('/');
}

/// Версия ядра запрашивается у libXray; если ядро не ответило, используется
/// версия вшитой обёртки — заголовок остаётся заполненным всегда.
Future<String> currentUserAgent({Xray xray = const Xray()}) async =>
    formatUserAgent(appVersion: buildStamp, xrayVersion: await xray.version());
