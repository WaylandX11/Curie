import 'dart:io';

import '../generated/build_info.dart';
import '../generated/core_info.dart';
import 'app_log.dart';
import 'platform_info.dart';
import 'xray.dart';

/// Заголовок подписок: Curie/версия Curie/версия ядра/ОС с версией.
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
  // И версия ядра из libXray, и ответ xrayVersion могут прийти с префиксом v.
  // В заголовке оставляем только цифры: Curie/…/26.11.9/…, а не /v26.11.9/…
  final xray = (core.isEmpty ? libXrayVersion : core).replaceFirst(
    RegExp(r'^v(?=\d)', caseSensitive: false),
    '',
  );
  final os = (platform ?? Platform.operatingSystem).trim();
  return ['Curie', app, xray, os].where((part) => part.isNotEmpty).join('/');
}

/// Версия ядра запрашивается у libXray; если ядро не ответило, используется
/// версия вшитой обёртки — заголовок остаётся заполненным всегда.
/// ОС — `Android17`, а не просто `android`: версию даёт нативный канал.
Future<String> currentUserAgent({
  Xray xray = const Xray(),
  Future<String> Function()? platformPart,
}) async {
  final os = platformPart != null
      ? await platformPart()
      : await PlatformInfo.userAgentPart();
  final header = formatUserAgent(
    appVersion: buildStamp,
    xrayVersion: await xray.version(),
    platform: os,
  );
  // Заголовок пишется один раз для каждого значения: после смены версии ядра
  // новый заголовок тоже должен появиться в журнале.
  if (_loggedHeader != header &&
      !AppLog.contains('app', 'User-Agent: $header')) {
    _loggedHeader = header;
    AppLog.add('app', 'User-Agent: $header');
  }
  return header;
}

String? _loggedHeader;
