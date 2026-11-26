# Сторонние компоненты

Код Curie распространяется под `LICENSE` (Curie Source-Available License 1.0).
Перечисленные ниже компоненты имеют собственные лицензии; Curie **не** меняет
их условия и не перелицензирует их.

| Компонент | Лицензия | Назначение |
| --- | --- | --- |
| [libXray](https://github.com/XTLS/libXray) | MIT, © XTLS | Обёртка над Xray-core, готовый `libXray.aar` |
| [Xray-core](https://github.com/XTLS/Xray-core) | MPL-2.0, © XTLS | Сетевое ядро внутри `libXray` |
| [xray-rust-mobile](https://github.com/aimalygin/xray-rust-mobile) | MPL-2.0, © aimalygin | Экспериментальное Rust-ядро (`0.10.1`, по умолчанию выключено) |
| [Flutter](https://flutter.dev) / Dart SDK | BSD-3-Clause, © Google | UI-фреймворк и инструменты сборки |
| `cryptography` | Apache-2.0 / BSD-3-Clause | Шифрование локального хранилища |
| `crypto` | BSD-3-Clause | SHA-256 для geoip.dat/geosite.dat |
| `file_picker` | MIT | Выбор geoip.dat/geosite.dat вручную (Android) |
| `flutter_secure_storage` | BSD-3-Clause | Keystore/Keychain |
| `shared_preferences` | BSD-3-Clause | Несекретные настройки (тема, язык) |
| `device_info_plus`, `package_info_plus` | BSD-3-Clause | HWID и версии приложения/ядра |
| `image_picker`, `mobile_scanner` | BSD-3-Clause | Импорт подписки через QR/камеру/галерею |
| `share_plus`, `url_launcher` | BSD-3-Clause | «Поделиться» и открытие ссылок |
| `path_provider` | BSD-3-Clause | Пути для локальных файлов |
| `material_ui` | BSD-3-Clause | Виджеты интерфейса |
| `flutter_launcher_icons`, `flutter_lints` | BSD-3-Clause | Только разработка и сборка |

MPL-2.0 — file-level copyleft: обязательства возникают только при изменении
исходных файлов Xray-core и xray-rust-mobile. Curie использует готовые
библиотеки без правок, поэтому условиям MPL достаточно сохранения уведомлений
об авторстве. Экспериментальное Rust-ядро поставляется в AAR вместе с JNI для
`arm64-v8a`, `armeabi-v7a`, `x86` и `x86_64`.
