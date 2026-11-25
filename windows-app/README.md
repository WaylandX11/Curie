# Curie для Windows

Отдельный Flutter-клиент на базе Android-приложения Curie. Общая логика, UI и
тесты используются без изменений; платформенные сервисы заменены Windows-реализациями.

Windows-сборка имеет канал `alpha`: версия в интерфейсе выглядит как
`26.11.25.1146-alpha`, а в свойствах `Curie.exe` указано `Curie Alpha`.
Имя приложения, заголовок окна и иконка совпадают с Android-версией —
`.ico` собран из `app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
скриптом `dart run tool/make_icon.dart`.

## Что отличается от Android

- `Vpn` запускает `xray.exe` с локальным `mixed` inbound и включает системный
  HTTP/SOCKS-прокси Windows через HKCU. Раздельное туннелирование по приложениям
  недоступно (`Apps.isSupported == false`); адресные правила работают как раньше.
- `Xray` сохраняет тот же JSON-envelope `invoke()`, но версию берёт из CLI ядра,
  свободные порты — из Dart, а разбор share-ссылок и TCP/TLS-пинг — локально.
- `DeviceIdentity` выводит HWID из `MachineGuid` с тем же HMAC-SHA256 и pepper.
- `PlatformInfo` читает версию Windows из реестра вместо MethodChannel.
- QR читается из файла (`image_picker` + `zxing2`): `mobile_scanner` не поддерживает Windows.
- Кнопка «×» скрывает окно в системный трей, а не завершает приложение. Левый
  клик по иконке показывает/скрывает окно, правый открывает меню: подключить/
  отключить VPN, выбрать сервер, показать окно, выйти. «Выход» сначала снимает
  системный прокси и останавливает `xray.exe`.
- Запуск второй копии запрещён: именованный мьютекс Windows показывает окно
  «Curie уже запущен» и завершает процесс.
- Язык этого окна и меню трея берётся из языка интерфейса Windows (`ru` — русский,
  всё остальное — английский), а не из языка, выбранного внутри Curie.

## Подготовка

1. Visual Studio 2022 с рабочей нагрузкой **Desktop development with C++**
   (включая ATL — нужен `flutter_secure_storage_windows`).
2. Flutter SDK с включённой поддержкой Windows.
3. Скачать ядро:

   ```powershell
   .\scripts\install-xray.ps1
   ```

   Если `flutter pub get` просит включить Developer Mode, выполните
   `.\scripts\fix-plugin-symlinks.ps1` и повторите `flutter pub get`.

   Скрипт кладёт проверенный `xray.exe` в `tools\xray\` и копирует его рядом с
   исполняемым файлом при сборке. Можно также задать `CURIE_XRAY_EXE` с путём к
   другому `xray.exe`.

## Версия

Windows-версия живёт отдельно от Android, но считается по той же схеме
`YY.MM.DD.HHMM` и всегда помечается каналом `alpha`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\set-version.ps1
```

Скрипт обновляет `lib/src/generated/build_info.dart`, `pubspec.yaml`
(монотонный build number) и версию в свойствах `Curie.exe`.

## Сборка

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

Готовое приложение: `build\windows\x64\runner\Release\Curie.exe`.

Ярлык «Curie Alpha» на рабочем столе и в меню «Пуск» (с той же иконкой):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create-shortcut.ps1
```

## Проверки

- `flutter analyze` и `flutter test` не требуют Visual Studio и `xray.exe`.
- Для запуска приложения нужен `xray.exe` рядом с `Curie.exe` или переменная
  `CURIE_XRAY_EXE`.
- Если приложение завершилось аварийно, при следующем запуске оно выключит
  оставленный системный прокси, только если в реестре всё ещё адрес Curie.
