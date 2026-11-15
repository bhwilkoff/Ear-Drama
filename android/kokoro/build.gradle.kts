// :kokoro — the Kokoro voices' engine (Decision 078): ONNX Runtime and the renderer, an on-demand Play Feature
// Delivery module (owner 2026-11-15). The base app installs it with the voices when the person taps Download voices
// and reaches it only through KokoroEngines (by reflection), so the base install carries none of it.

plugins {
    alias(libs.plugins.android.dynamic.feature)
}

android {
    namespace = "com.example.appname.kokoroengine"
    compileSdk = 37

    defaultConfig {
        minSdk = 29
    }

    buildTypes {
        debug {}
        release {}
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 }
}

dependencies {
    implementation(project(":app"))
    // ONNX Runtime Android, MIT, CPU provider.
    implementation(libs.onnxruntime.android)
}
