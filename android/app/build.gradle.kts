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
    namespace = "com.mokshastro.ai"
    // compileSdk only affects what APIs the code can call — it does NOT change
    // the app's runtime target. It just has to be >= targetSdk, and both are
    // now 36 (Android 16), which is Play's current minimum for uploads.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (v10+): it relies on
        // core-library desugaring for the java.time APIs its scheduling
        // uses, and the flag is not inherited from the library module —
        // the consuming app has to set it or the build fails.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.mokshastro.ai"
        // Was 23 (Android 6.0). Raised to 24 because
        // flutter_local_notifications declares minSdkVersion 24 and the
        // manifest merger refuses a lower value in the app. 24 is also
        // Flutter's own current default (FlutterExtension.minSdkVersion),
        // so 23 was already an override of the toolchain default.
        //
        // Cost: devices on Android 6.0/6.0.1 stop receiving updates. They
        // keep the version they have; they are not uninstalled. Play's
        // distribution for API 23 is well under 1%.
        minSdk = 24
        // Documented in the flutter_local_notifications setup. A no-op
        // above API 21, where multidex is native — kept so the Gradle
        // config matches what the plugin asks for.
        multiDexEnabled = true
        targetSdk = 36                 // Play Store now requires API 36 minimum
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

dependencies {
    // Backports the java.time APIs flutter_local_notifications uses to
    // API 24. Version must match what the plugin's own build.gradle
    // declares; a mismatch is a Gradle resolution error.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
