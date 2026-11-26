plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.waylandx11.curie"
    compileSdk = flutter.compileSdkVersion
    // NDK не нужен: нативного кода в проекте нет, ядро приходит готовой .so внутри libXray.aar.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.waylandx11.curie"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Общий ключ подписи для локальных сборок и CI. Без него APK с GitHub
    // не встаёт поверх уже установленного локальной сборкой: подписи разные.
    // Файл в .gitignore; в CI его кладёт секрет CURIE_DEBUG_KEYSTORE_BASE64.
    val sharedDebugKey = file("debug.keystore")
    if (sharedDebugKey.exists()) {
        signingConfigs {
            getByName("debug") {
                storeFile = sharedDebugKey
            }
        }
    }

    buildTypes {
        release {
            // Пока подписываем тем же ключом, чтобы обновления с GitHub ставились.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    lint {
        // AGP lintVitalAnalyzeRelease падает на image_picker_android из-за бага
        // CommentDetector; Dart-анализ и тесты уже проверены в CI отдельно.
        checkReleaseBuilds = false
        abortOnError = false
    }

    // Один universal APK и три лёгких варианта под конкретные ABI.
    // 32-битный x86 убран: Flutter 3.50 больше не поставляет для него
    // libflutter.so/gen_snapshot, хотя AAR xray-rust-mobile всё ещё содержит
    // libxray_ffi.so. Такой APK не смог бы запустить приложение.
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Ядро Xray: официальная обёртка XTLS (MIT). Кладёт scripts/sync-core.ps1.
    implementation(files("libs/libXray.aar"))
    // Экспериментальное Rust-ядро (MPL-2.0), выключаемое в интерфейсе.
    // Обычный путь по умолчанию остаётся на libXray.
    implementation("io.github.aimalygin:xray-rust-mobile:0.10.1")
}

flutter {
    source = "../.."
}
