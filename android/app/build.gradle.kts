import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.sakashi.crunchyroll_calendar"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        
        // Core Library Desugaring für flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.sakashi.crunchyroll_calendar"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core Library Desugaring für Java 8+ Features (z.B. java.time in flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Setze explizit Source/Target für alle JavaCompile Tasks auf Java 17
// und unterdrücke Warnungen zu veralteten Optionen (-Xlint:-options).
// Hilft wenn Plugins noch standardmäßig 1.8 verwenden.
tasks.withType<JavaCompile> {
    sourceCompatibility = "17"
    targetCompatibility = "17"
    options.compilerArgs.addAll(listOf("-Xlint:-options"))
}
