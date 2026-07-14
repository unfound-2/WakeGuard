plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.smartblealarm.smart_ble_alarm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications 22 (backup alarm scheduling),
        // which relies on java.time APIs that must be desugared for older
        // Android API levels.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.smartblealarm.smart_ble_alarm"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // The app is flavorized as "WakeGuard" (see `default-flavor` in pubspec.yaml
    // and the matching iOS WakeGuard scheme). Flutter builds the WakeGuard flavor
    // on every platform, so Android must define a matching product flavor or the
    // build fails looking for the `assembleWakeGuard*` tasks. The flavor keeps the
    // same applicationId, so the existing google-services.json still resolves.
    flavorDimensions += "brand"
    productFlavors {
        create("WakeGuard") {
            dimension = "brand"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Backing library for core library desugaring enabled above; version must
    // be >= 2.1.4 for flutter_local_notifications 22.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
