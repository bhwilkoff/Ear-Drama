// :wear — the Wear OS stub (Decision 056). Its first screen is Continue,
// waiting on the phone. It shares nothing with :app: the catalog and the
// player come over from the phone once the core five are done.

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

/** The one marketing version, read as :app reads it (tools/test_version_contract.py). */
val marketingVersion: String = rootProject.file("../AppVersion.xcconfig")
    .readLines()
    .firstOrNull { it.trimStart().startsWith("MARKETING_VERSION") }
    ?.substringAfter("=")?.trim()
    ?: error("MARKETING_VERSION not found in AppVersion.xcconfig")

android {
    namespace = "com.example.appname.wear"
    compileSdk = 37

    defaultConfig {
        // The phone's id: Play lists a watch app under the phone app it pairs with.
        applicationId = "app.eardrama"
        // Wear OS 3 (API 30), the floor: see android/README.md "Wear OS".
        minSdk = 30
        targetSdk = 36
        // Must differ from :app's versionCode when both are uploaded to the one listing.
        versionCode = 1
        versionName = marketingVersion
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures { compose = true }
}

kotlin {
    compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.activity.compose)
    implementation(libs.wear.compose.material3)
    implementation(libs.wear.compose.foundation)
}
