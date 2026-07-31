import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Uploads ProGuard/R8 mappings and native debug symbols to Sentry on release builds.
    id("io.sentry.android.gradle")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.moneymanager.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.moneymanager.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = false
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

sentry {
    // The Sentry Android SDK is already bundled by sentry_flutter.
    autoInstallation {
        enabled.set(false)
    }
    // Credentials come from environment variables so they are never committed.
    // Only set them when the token is present; otherwise the plugin skips uploads.
    val sentryAuthToken = System.getenv("SENTRY_AUTH_TOKEN")
    if (!sentryAuthToken.isNullOrEmpty()) {
        org.set(System.getenv("SENTRY_ORG"))
        projectName.set(System.getenv("SENTRY_PROJECT"))
        authToken.set(sentryAuthToken)
    }
}

// Avoid the Sentry plugin running upload tasks when no auth token is configured
// (e.g. local builds). The plugin passes the mapping path unquoted to cmd on
// Windows, which breaks when the project path contains spaces.
if (System.getenv("SENTRY_AUTH_TOKEN").isNullOrEmpty()) {
    tasks.configureEach {
        if (name.startsWith("uploadSentryProguardMappings") || name.startsWith("uploadSentryNativeSymbols")) {
            enabled = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
