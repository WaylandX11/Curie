import 'package:flutter/foundation.dart';

import 'update.dart';

/// Обновление, которое уже detected и ждёт реакции пользователя.
class UpdateNotice {
  const UpdateNotice(this.release, {this.coreUpdated = false});

  final GithubRelease release;
  final bool coreUpdated;
}

/// Глобальное состояние баннера и одноразового диалога про новое ядро.
///
/// Держится вне виджетов: проверка идёт в фоне, а главный экран может быть
/// в стеке под экраном настроек.
class UpdateNotifier {
  static final ValueNotifier<UpdateNotice?> available = ValueNotifier(null);
  static final ValueNotifier<UpdateNotice?> coreDialog = ValueNotifier(null);

  static void publish(UpdateNotice notice, {required bool showCoreDialog}) {
    available.value = notice;
    if (showCoreDialog && notice.coreUpdated) coreDialog.value = notice;
  }

  static void restore(UpdateNotice notice) => available.value = notice;

  static void dismissDialog() => coreDialog.value = null;

  static void clear() {
    available.value = null;
    coreDialog.value = null;
  }
}
