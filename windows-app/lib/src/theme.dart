import 'package:material_ui/material_ui.dart';

/// Палитра из branding/brand.json.
const Color curieTeal = Color(0xFF2FE3D0);
const Color curieMint = Color(0xFF9BFF6A);
const Color curieBackground = Color(0xFF0B1220);
const Color curieLightBackground = Color(0xFFF3F7F8);

/// Темы приложения. Идентификаторы стабильны: они пишутся в SharedPreferences.
enum AppTheme {
  dark('dark'),
  light('light'),
  amber('amber'),
  ocean('ocean'),
  forest('forest'),
  vanilla('vanilla'),
  pink('pink');

  const AppTheme(this.id);

  final String id;

  static AppTheme fromId(String? id) => AppTheme.values.firstWhere(
        (theme) => theme.id == id,
        orElse: () => AppTheme.dark,
      );

  Brightness get brightness => switch (this) {
        AppTheme.light ||
        AppTheme.forest ||
        AppTheme.vanilla ||
        AppTheme.pink => Brightness.light,
        _ => Brightness.dark,
      };

  String get labelKey => switch (this) {
        AppTheme.dark => 'themeDark',
        AppTheme.light => 'themeLight',
        AppTheme.amber => 'themeAmber',
        AppTheme.ocean => 'themeOcean',
        AppTheme.forest => 'themeForest',
        AppTheme.vanilla => 'themeVanilla',
        AppTheme.pink => 'themePink',
      };
}

/// Дополнительный «хороший» цвет (успех, активное соединение), которого нет
/// в стандартной M3-палитре. Хранится в ThemeData, чтобы виджеты не знали про
/// конкретный выбор пользователя.
@immutable
class CurieColors extends ThemeExtension<CurieColors> {
  const CurieColors({required this.good});

  final Color good;

  @override
  CurieColors copyWith({Color? good}) => CurieColors(good: good ?? this.good);

  @override
  CurieColors lerp(ThemeExtension<CurieColors>? other, double t) {
    if (other is! CurieColors) return this;
    return CurieColors(good: Color.lerp(good, other.good, t) ?? good);
  }
}

typedef _Spec = ({
  Color seed,
  Color background,
  Color surface,
  Color primary,
  Color secondary,
  Color good,
});

_Spec _specOf(AppTheme theme) => switch (theme) {
      // Фирменная тёмная: бирюза + мята.
      AppTheme.dark => (
          seed: curieTeal,
          background: curieBackground,
          surface: const Color(0xFF111C2E),
          primary: curieTeal,
          secondary: curieMint,
          good: curieMint,
        ),
      // Классическая светлая: те же оттенки, но читаемые на белом.
      AppTheme.light => (
          seed: curieTeal,
          background: curieLightBackground,
          surface: Colors.white,
          primary: const Color(0xFF00796B),
          secondary: const Color(0xFF00897B),
          good: const Color(0xFF147A38),
        ),
      // Тёплая тёмная: янтарь и светло-зелёный индикатор.
      AppTheme.amber => (
          seed: const Color(0xFFFFB300),
          background: const Color(0xFF171207),
          surface: const Color(0xFF2A2012),
          primary: const Color(0xFFFFC44D),
          secondary: const Color(0xFFFFE082),
          good: const Color(0xFFB8E986),
        ),
      // Холодная тёмная: океанский синий.
      AppTheme.ocean => (
          seed: const Color(0xFF29B6F6),
          background: const Color(0xFF061423),
          surface: const Color(0xFF10263D),
          primary: const Color(0xFF4FC3F7),
          secondary: const Color(0xFF81D4FA),
          good: const Color(0xFF81C784),
        ),
      // Светлая «лесная»: спокойный зелёный для длительного чтения.
      AppTheme.forest => (
          seed: const Color(0xFF2E7D32),
          background: const Color(0xFFEFF6EE),
          surface: Colors.white,
          primary: const Color(0xFF2E7D32),
          secondary: const Color(0xFF00897B),
          good: const Color(0xFF1B5E20),
        ),
      // «Ваниль»: почти исходная кремовая тема, но чуть глубже по тонам.
      AppTheme.vanilla => (
          seed: const Color(0xFFF0C078),
          background: const Color(0xFFF8EDD2),
          surface: const Color(0xFFFFF9EC),
          primary: const Color(0xFF7A4700),
          secondary: const Color(0xFFA86A00),
          good: const Color(0xFF2E7D32),
        ),
      // «Розовая»: светлая розовая, чуть темнее первого варианта.
      AppTheme.pink => (
          seed: const Color(0xFFEC9AB4),
          background: const Color(0xFFF8DFE9),
          surface: const Color(0xFFFFEFF5),
          primary: const Color(0xFFA8134E),
          secondary: const Color(0xFFC2185B),
          good: const Color(0xFF2E7D32),
        ),
    };

ThemeData curieTheme(AppTheme theme) {
  final spec = _specOf(theme);
  final scheme = ColorScheme.fromSeed(
    seedColor: spec.seed,
    brightness: theme.brightness,
  );
  final resolved = scheme.copyWith(
    primary: spec.primary,
    secondary: spec.secondary,
    surface: spec.surface,
  );

  return ThemeData(
    colorScheme: resolved,
    scaffoldBackgroundColor: spec.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: resolved.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    extensions: <ThemeExtension<dynamic>>[
      CurieColors(good: spec.good),
    ],
  );
}

/// Акцент темы. Все виджеты берут его из ThemeData, а не из константы бренда.
Color curieAccent(ThemeData theme) => theme.colorScheme.primary;

/// Цвет успешного состояния (подключено, быстрый пинг).
Color curieGood(ThemeData theme) =>
    theme.extension<CurieColors>()?.good ?? theme.colorScheme.primary;
