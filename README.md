# Curie

Xray-клиент для Android (iOS в планах). Исходный код открыт, проект активно развивается.
Ядро Xray встроено в APK.

## Скачать

[Последний релиз](https://github.com/WaylandX11/Curie/releases/latest) — универсальный APK для всех архитектур,
а также отдельные сборки `arm64-v8a`, `armeabi-v7a`, `x86_64`, каждая с файлом `.sha256`.
Приложение умеет проверять наличие новых версий в настройках («О приложении»).

## Возможности

- Подключения: VLESS / VMess / Trojan / Shadowsocks / Hysteria2 и другие протоколы Xray.
- Подписки (Remnawave, Marzban, 3x-ui и совместимые): добавление по ссылке или QR,
  автообновление, трафик и срок действия.
- TUN-режим и SOCKS5, раздельное туннелирование по приложениям.
- Балансировка между серверами с failover (leastLoad / leastPing).
- Экспериментальное Rust-ядро (xray-rust) — переключатель в настройках.
- DNS из подписки, белые списки, geoip/geosite.
- Журналы приложения и ядра, проверка соединения, пинг узлов.
- Тёмная/светлая тема, русский и английский интерфейс.

## Сборка

```powershell
cd app
flutter pub get
flutter build apk --release --split-per-abi
```

APK появятся в `app/build/app/outputs/flutter-apk/`.

## Лицензия

Код Curie — [Curie Source-Available License 1.0](LICENSE). Сторонние компоненты
(Xray-core, Flutter и др.) распространяются по своим лицензиям — см.
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

# Curie (English)

An Xray client for Android (iOS planned). Source available, actively developed.
Xray core is bundled into the APK.

## Download

[Latest release](https://github.com/WaylandX11/Curie/releases/latest) — a universal APK
plus ABI builds for `arm64-v8a`, `armeabi-v7a`, `x86_64`, each with a `.sha256` checksum.
The app can check for newer releases in Settings → About.

## Features

- Protocols: VLESS / VMess / Trojan / Shadowsocks / Hysteria2 and other Xray protocols.
- Subscriptions (Remnawave, Marzban, 3x-ui compatible): add by URL or QR, auto-update,
  traffic and expiry info.
- TUN mode and SOCKS5, per-app routing.
- Load balancing with failover (leastLoad / leastPing).
- Experimental Rust core (xray-rust) — toggle in settings.
- DNS from subscription, whitelists, geoip/geosite.
- App and core logs, connection check, node ping.
- Dark/light theme, Russian and English UI.

## Build

```powershell
cd app
flutter pub get
flutter build apk --release --split-per-abi
```

APKs land in `app/build/app/outputs/flutter-apk/`.

## License

Curie code — [Curie Source-Available License 1.0](LICENSE). Third-party components
(Xray-core, Flutter, etc.) keep their own licenses — see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).