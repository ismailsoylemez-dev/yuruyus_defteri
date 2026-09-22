plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase: google-services.json dosyasini okur ve kaynaklara isler.
    id("com.google.gms.google-services") version "4.4.4"
}

android {
    namespace = "com.ismail.adim_sayar"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications icin gerekli (java.time vb.)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ismail.adim_sayar"
        // firebase_auth 6.x en az API 23 ister.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Kisisel kullanim: debug anahtari ile imzalaniyor.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.forEach { output ->
            if (output is com.android.build.gradle.internal.api.BaseVariantOutputImpl) {
                val versionName = flutter.versionName
                val buildType = variant.buildType.name
                output.outputFileName = "adim_sayar-$buildType-v$versionName.apk"
            }
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // StepService.kt: NotificationCompat / ContextCompat
    implementation("androidx.core:core-ktx:1.15.0")
    // RouteTracker.kt: FusedLocationProviderClient (GPS rota kaydi)
    implementation("com.google.android.gms:play-services-location:21.3.0")
}
