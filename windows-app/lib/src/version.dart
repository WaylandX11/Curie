import 'generated/build_info.dart';

/// Канал Windows-сборки. Отделен от [buildStamp], чтобы номер сборки оставался
/// совместим с проверкой обновлений и User-Agent Android-клиента.
const String buildChannel = 'alpha';

/// Версия, которую видит пользователь: 26.11.25.1146-alpha.
String get displayVersion => '$buildStamp-$buildChannel';
