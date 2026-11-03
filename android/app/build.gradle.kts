import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase 활성화 — google-services.json 기반 Firebase 옵션 자동 주입 (FCM/Phone Auth)
    id("com.google.gms.google-services")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties()
if (releaseSigningPropertiesFile.isFile) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

val requiredReleaseSigningKeys = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val missingReleaseSigningKeys = requiredReleaseSigningKeys.filter { key ->
    releaseSigningProperties.getProperty(key).isNullOrBlank()
}
val releaseStoreFilePath = releaseSigningProperties.getProperty("storeFile")
val releaseStoreFile = releaseStoreFilePath?.takeIf(String::isNotBlank)?.let(::file)
val releaseTaskRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("release", ignoreCase = true)
}

fun validateReleaseSigning() {
    when {
        !releaseSigningPropertiesFile.isFile -> throw GradleException(
            "Release signing requires android/key.properties. " +
                "Copy key.properties.example and provide the ignored secrets.",
        )
        missingReleaseSigningKeys.isNotEmpty() -> throw GradleException(
            "Release signing is missing key.properties values: " +
                missingReleaseSigningKeys.joinToString(),
        )
        releaseStoreFile?.isFile != true -> throw GradleException(
            "Release signing keystore was not found: ${releaseStoreFile?.path}",
        )
    }
}

if (releaseTaskRequested) {
    validateReleaseSigning()
}

val appProjectPath = project.path
gradle.taskGraph.whenReady {
    val releaseTaskInGraph = allTasks.any { task ->
        task.project.path == appProjectPath &&
            task.name.contains("release", ignoreCase = true)
    }
    if (releaseTaskInGraph) {
        validateReleaseSigning()
    }
}

val releaseSigningAvailable =
    releaseSigningPropertiesFile.isFile &&
        missingReleaseSigningKeys.isEmpty() &&
        releaseStoreFile?.isFile == true

android {
    namespace = "com.whh07151.lunchsync"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.whh07151.lunchsync"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningAvailable) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }
}

flutter {
    source = "../.."
}
