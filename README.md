# Curie

Новый клиент Xray для Android, с поддержкой iOS позже. Сейчас проверяю приложение на
устройстве, код доступен здесь и проект буду развивать.

Есть подписки с автообновлением, список узлов с пингом, раздельное туннелирование, журнал
приложения и ядра Xray, русский и английский интерфейс. Ядро Xray вшито в APK — отдельно
ничего ставить не нужно. Туннель продолжает работать в фоне, а проверки подписок и обновлений
идут через него.

### Скачать

[Последний релиз](https://github.com/WaylandX11/Curie/releases/latest) — APK
`universal` для всех архитектур и ABI-сборки `arm64-v8a`, `armeabi-v7a`, `x86_64`.
Для каждой сборки есть файл `.sha256`. Проверить обновление можно прямо в приложении:
«Настройки → О приложении → Проверить обновления».

История изменений — в [CHANGELOG.md](CHANGELOG.md).

### FAQ

**Что это?**

Очередной клиент для Xray-подписок.

**Зачем? Чем он лучше?**

Создавался для себя — ради опыта, любопытства и интереса. Код открытый, приложение
никуда ничего не отправляет, кроме HWID, который легко отключить. А ещё в нём есть
экспериментальное ядро на Rust.

**Фу, это вайбкод?**

Да, даже скрывать не будем.

**У меня что-то не работает**

Пишите в [Issues](https://github.com/WaylandX11/Curie/issues), предлагайте —
постараемся улучшить и починить. Пока что это хоумпроект.

### Лицензия

Исходники Curie — [Curie Source-Available License 1.0](LICENSE): можно изучать и
использовать лично. Сторонние компоненты (Xray-core, Flutter и др.) описаны в
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

# Curie (English)

A new Xray client for Android, with iOS planned. The source is available here and the
project is under active development. Xray core is bundled into the APK.

[Download the latest release](https://github.com/WaylandX11/Curie/releases/latest):
a `universal` APK for all architectures plus ABI builds for `arm64-v8a`, `armeabi-v7a`
and `x86_64`, each with a `.sha256` checksum. The app can check for newer releases in
Settings → About.

### FAQ

**What is it?**

Just another client for Xray subscriptions.

**Why? What makes it better?**

I built it for myself — for the experience, out of curiosity and interest. The code is
open, and the app sends nothing anywhere except HWID, which can be easily disabled.
It also has an experimental Rust core.

**Ew, is this vibe-coded?**

Yes, and we're not even hiding it.

**Something doesn't work for me**

Open an [Issue](https://github.com/WaylandX11/Curie/issues) or suggest something —
we'll try to improve and fix it. For now it's a home project.

Curie source: [Curie Source-Available License 1.0](LICENSE). Third-party components are
listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
