import 'dart:io';

import 'package:flutter/services.dart';

import '../generated/core_info.dart';
import 'store.dart';
import 'xray.dart';

/// Версия активного ядра. По умолчанию это libXray (Go), но если в
/// «Экспериментальном» включено Rust-ядро, подпись и User-Agent должны
/// показывать версию именно работающего ядра.
Future<String> rustCoreVersion() async {
  if (!Platform.isAndroid) return '';
  try {
    final version = await const MethodChannel('io.github.waylandx11.curie/bridge')
        .invokeMethod<String>('rustCoreVersion');
    return version?.trim() ?? '';
  } on Object {
    // AAR может отсутствовать в старой сборке — тогда просто показываем Go.
    return '';
  }
}

bool get rustCoreEnabled =>
    Platform.isAndroid && Store.instance.state.value.settings.useRustCore;

Future<String> coreVersion({bool? rust}) async {
  final useRust = rust ?? rustCoreEnabled;
  if (useRust) {
    final version = await rustCoreVersion();
    if (version.isNotEmpty) return version;
  }
  final version = await const Xray().version();
  return version.trim().isEmpty ? libXrayVersion : version;
}

/// Подпись в интерфейсе: «Xray 26.11.9» или «xray-rust 0.10.1».
String coreLabel(String version, {bool? rust}) {
  final clean = version
      .trim()
      .replaceFirst(RegExp(r'^xray\s+', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^rust\s+', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^v(?=\d)', caseSensitive: false), '');
  final name = (rust ?? rustCoreEnabled) ? 'xray-rust' : 'Xray';
  return '$name $clean'.trim();
}
