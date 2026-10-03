import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

// 릴리스(업로드) 서명 키. android/key.properties(커밋 금지)에서 읽는다. 만드는 법은 docs/RELEASE.md
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

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
        // flutter_local_notifications(알림 예약 시각 처리)가 java.time 백포트를 요구한다
        isCoreLibraryDesugaringEnabled = true
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
        // 개발 중에는 구글 테스트 앱 ID만 쓴다. 출시 빌드에서 --dart-define=ADMOB_APP_ID=... 로 바꾼다
        manifestPlaceholders["admobAppId"] =
            dartDefines["ADMOB_APP_ID"] ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 디버그 키로 서명한 릴리스가 실수로 나가지 않게, 업로드 키가 없으면 아래에서 빌드를 멈춘다
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

// 릴리스 빌드인데 업로드 키가 없으면 친절하게 멈춘다
gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.name.contains("Release") && it.project == project }
    if (wantsRelease && !hasReleaseKey) {
        throw GradleException(
            "android/key.properties가 없어 릴리스 서명을 할 수 없어요. docs/RELEASE.md의 '업로드 키 만들기'를 따라 주세요."
        )
    }
}
