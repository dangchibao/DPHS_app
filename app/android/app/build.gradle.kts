plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val ownerSigningNames = listOf("ANDROID_KEYSTORE_PATH", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")
val ownerSigning = ownerSigningNames.associateWith { System.getenv(it)?.takeIf(String::isNotBlank) }
val hasOwnerSigning = ownerSigning.values.all { it != null }
if (ownerSigning.values.any { it != null } && !hasOwnerSigning) {
    throw GradleException("ANDROID_SIGNING_INCOMPLETE: configure all four signing environment variables.")
}
if (System.getenv("ANDROID_REQUIRE_RELEASE_SIGNING") == "1" && !hasOwnerSigning) {
    throw GradleException("ANDROID_SIGNING_REQUIRED: owner-controlled release key is required.")
}
val ownerKeyFile = ownerSigning["ANDROID_KEYSTORE_PATH"]?.let { file(it) }
if (hasOwnerSigning && ownerKeyFile?.isFile != true) {
    throw GradleException("ANDROID_SIGNING_FILE_MISSING: signing key file does not exist.")
}

android {
    namespace = "vn.ngocthanh.ngoc_thanh_pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "vn.ngocthanh.ngoc_thanh_pos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasOwnerSigning) {
            create("ownerRelease") {
                storeFile = ownerKeyFile
                storePassword = ownerSigning["ANDROID_KEYSTORE_PASSWORD"]
                keyAlias = ownerSigning["ANDROID_KEY_ALIAS"]
                keyPassword = ownerSigning["ANDROID_KEY_PASSWORD"]
            }
        }
    }

    buildTypes {
        release {
            // No owner key: explicit preview signing, never an implicit production key.
            signingConfig = signingConfigs.getByName(if (hasOwnerSigning) "ownerRelease" else "debug")
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
