import java.util.Base64

// `flutter build/run --dart-define=KEY=VALUE` 값을 네이티브 설정에서도 쓰기 위해 해석한다.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.mapNotNull {
            val decoded = String(Base64.getDecoder().decode(it))
            val i = decoded.indexOf('=')
            if (i > 0) decoded.substring(0, i) to decoded.substring(i + 1) else null
        }
        ?.toMap()
        ?: emptyMap()

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.meeil.app"
    // permission_handler 13이 SDK 37 컴파일을 요구한다. targetSdk는 Flutter 기본값 유지
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.meeil.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 카카오 키가 없으면 쓰이지 않는 더미 스킴(로그인 버튼이 "준비 중"을 안내)
        manifestPlaceholders["kakaoScheme"] =
            "kakao" + (dartDefines["KAKAO_NATIVE_APP_KEY"] ?: "disabled")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
