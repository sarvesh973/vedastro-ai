import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// Load keystore properties if available (CI or local)
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.vedastro.ai"
    // compileSdk = 36 to satisfy AndroidX libs (activity 1.12.4, core 1.18.0).
    // targetSdk stays at 34 (Play Store minimum, avoids new runtime behavior
    // changes from API 35/36). compileSdk only affects what APIs the code can
    // call — does NOT change app's runtime target.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.vedastro.ai"
        minSdk = 23                    // Android 6.0+ — covers ~99% of devices
        targetSdk = 34                 // Required by Play Store
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasKeystore) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 code shrinking + obfuscation + resource shrinking.
            // Without this the AAB is 2-3× larger AND code (including Razorpay
            // logic) is readable in plaintext after decompilation.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
