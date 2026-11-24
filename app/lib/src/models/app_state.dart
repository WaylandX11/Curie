import 'profile.dart';
import 'settings.dart';
import 'subscription.dart';

/// Всё состояние приложения. Целиком шифруется и лежит одним файлом.
class AppState {
  const AppState({
    this.profiles = const [],
    this.subscriptions = const [],
    this.settings = const Settings(),
    this.selectedId,
    this.deviceId,
  });

  /// Одиночные ссылки, добавленные вручную.
  final List<Profile> profiles;
  final List<Subscription> subscriptions;
  final Settings settings;
  final String? selectedId;

  /// Случайный идентификатор устройства для панелей с лимитом устройств.
  final String? deviceId;

  List<Profile> get allProfiles => [
        ...profiles,
        for (final subscription in subscriptions) ...subscription.nodes,
      ];

  Profile? get selected {
    final all = allProfiles;
    if (all.isEmpty) return null;
    if (selectedId != null) {
      for (final profile in all) {
        if (profile.id == selectedId) return profile;
      }
    }
    return all.first;
  }

  AppState copyWith({
    List<Profile>? profiles,
    List<Subscription>? subscriptions,
    Settings? settings,
    String? selectedId,
    String? deviceId,
    bool clearSelection = false,
  }) =>
      AppState(
        profiles: profiles ?? this.profiles,
        subscriptions: subscriptions ?? this.subscriptions,
        settings: settings ?? this.settings,
        selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
        deviceId: deviceId ?? this.deviceId,
      );

  Map<String, dynamic> toJson() => {
        'version': 2,
        'profiles': profiles.map((p) => p.toJson()).toList(),
        'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
        'settings': settings.toJson(),
        if (selectedId != null) 'selectedId': selectedId,
        if (deviceId != null) 'deviceId': deviceId,
      };

  factory AppState.fromJson(Map<String, dynamic> json) => AppState(
        profiles: ((json['profiles'] as List?) ?? const [])
            .map((e) => Profile.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        subscriptions: ((json['subscriptions'] as List?) ?? const [])
            .map((e) => Subscription.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        settings: json['settings'] == null
            ? const Settings()
            : Settings.fromJson((json['settings'] as Map).cast<String, dynamic>()),
        selectedId: (json['selectedId'] ?? json['selectedLink']) as String?,
        deviceId: json['deviceId'] as String?,
      );
}
