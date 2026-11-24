import 'package:material_ui/material_ui.dart';

import '../models/app_state.dart';
import 'vault.dart';

/// Единственный источник правды для экранов. Любое изменение сразу
/// шифруется и пишется на диск.
class Store {
  Store({Vault? vault}) : _vault = vault ?? Vault();

  static Store instance = Store();

  final Vault _vault;
  final ValueNotifier<AppState> state = ValueNotifier(const AppState());

  Future<void>? _loaded;

  Future<void> load() => _loaded ??= _load();

  Future<void> _load() async {
    try {
      final json = await _vault.read();
      if (json.isNotEmpty) {
        state.value = AppState.fromJson(json);
      }
    } on Object {
      // Повреждённый файл или недоступный ключ: стартуем с чистого состояния,
      // но не падаем — пользователь сможет добавить сервер заново.
    }
  }

  Future<void> update(AppState Function(AppState current) change) async {
    final next = change(state.value);
    state.value = next;
    await _vault.write(next.toJson());
  }
}
