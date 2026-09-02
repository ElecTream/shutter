import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun missingReleaseSigningMessage(): String =
    """
    Missing or incomplete android/key.properties — release builds cannot be signed.
    Copy android/key.properties.example to android/key.properties, fill in
    storeFile, storePassword, keyAlias, and keyPassword, and place the upload
    keystore (for example upload-keystore.jks) where storeFile points.
    storeFile is relative to the android/ directory unless it is an absolute path.
    Debug and profile builds do not need this file. Release does not fall back
    to the debug keystore.
    """.trimIndent()

fun requireReleaseSigning() {
    val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    if (!keystorePropertiesFile.exists()) {
        throw GradleException(missingReleaseSigningMessage())
    }
    for (key in required) {
        if (keystoreProperties.getProperty(key).isNullOrBlank()) {
            throw GradleException(
                "android/key.properties is missing required key '$key'.\n${missingReleaseSigningMessage()}",
            )
        }
    }
    val store = rootProject.file(keystoreProperties.getProperty("storeFile"))
    if (!store.isFile) {
        throw GradleException(
            "storeFile in android/key.properties does not exist: ${store.absolutePath}\n${missingReleaseSigningMessage()}",
        )
    }
}

android {
    namespace = "com.electream.shutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.electream.shutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            // Populate only when the file exists so debug/profile still configure.
            // Release tasks validate via requireReleaseSigning() and fail closed.
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                if (!storeFilePath.isNullOrBlank()) {
                    storeFile = rootProject.file(storeFilePath)
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Add this to disable resource shrinking while keeping code shrinking
    buildFeatures {
        buildConfig = true
    }
}

gradle.taskGraph.whenReady {
    val buildingRelease =
        allTasks.any { task ->
            val name = task.name
            name.contains("Release") &&
                (
                    name.contains("assemble", ignoreCase = true) ||
                        name.contains("bundle", ignoreCase = true) ||
                        name.contains("package", ignoreCase = true) ||
                        name.contains("sign", ignoreCase = true)
                )
        }
    if (buildingRelease) {
        requireReleaseSigning()
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("androidx.work:work-runtime-ktx:2.8.1")
}

flutter {
    source = "../.."
}