import java.util.Properties

// :app — composition root. Manifest, R8 config, all features.
// Modular split (core/* + feature/*) is the next step as the app grows.

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

// The bundled catalog seed (docs/CATALOG-CONTRACT.md §2, `ear-drama-seed.sqlite`).
// The database is never committed: it is copied into a generated assets
// directory under build/ at build time, from the first of
//   -PearDramaSeed=<path>, `ear.drama.seed=<path>` in local.properties,
//   $EAR_DRAMA_SEED, then ../catalog/out/publish-clean/ear-drama.sqlite.
// With none present the app builds without a seed and runs download-only.
abstract class CopyCatalogSeed : DefaultTask() {
    @get:InputFiles
    abstract val seed: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outDir: DirectoryProperty

    @TaskAction
    fun run() {
        val dir = outDir.get().asFile
        dir.deleteRecursively()
        dir.mkdirs()
        seed.files.firstOrNull { it.isFile }?.copyTo(File(dir, "ear-drama-seed.sqlite"), overwrite = true)
    }
}

val localProps = Properties().apply {
    rootProject.file("local.properties").takeIf { it.isFile }?.inputStream()?.use { load(it) }
}
val catalogSeedPath: String = providers.gradleProperty("earDramaSeed").orNull
    ?: localProps.getProperty("ear.drama.seed")
    ?: providers.environmentVariable("EAR_DRAMA_SEED").orNull
    ?: rootProject.file("../catalog/out/publish-clean/ear-drama.sqlite").path

val copyCatalogSeed = tasks.register<CopyCatalogSeed>("copyCatalogSeed") {
    seed.from(listOf(file(catalogSeedPath)).filter { it.isFile })
}

// The castable scripts (docs/PLAYS-DESIGN.md §3), `catalog/plays/castable-scripts.json`,
// bundled as an asset the same way: copied at build time, never committed twice.
abstract class CopyCastableScripts : DefaultTask() {
    @get:InputFiles
    abstract val scripts: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outDir: DirectoryProperty

    @TaskAction
    fun run() {
        val dir = outDir.get().asFile
        dir.deleteRecursively()
        dir.mkdirs()
        scripts.files.firstOrNull { it.isFile }?.copyTo(File(dir, "castable-scripts.json"), overwrite = true)
    }
}

val copyCastableScripts = tasks.register<CopyCastableScripts>("copyCastableScripts") {
    scripts.from(listOf(rootProject.file("../catalog/plays/castable-scripts.json")).filter { it.isFile })
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(copyCatalogSeed, CopyCatalogSeed::outDir)
        variant.sources.assets?.addGeneratedSourceDirectory(copyCastableScripts, CopyCastableScripts::outDir)
    }
}

/** The one marketing version, shared with the Apple targets. Fails loudly rather
 *  than guessing: a silent fallback would put the drift straight back. */
val marketingVersion: String = rootProject.file("../AppVersion.xcconfig")
    .readLines()
    .firstOrNull { it.trimStart().startsWith("MARKETING_VERSION") }
    ?.substringAfter("=")?.trim()
    ?: error("MARKETING_VERSION not found in AppVersion.xcconfig")

android {
    namespace = "com.example.appname"  // FILL IN: your reverse-DNS package
    compileSdk = 37                    // the 2026.05 Compose BOM requires compiling against API 37

    defaultConfig {
        applicationId = "app.eardrama"  // FILL IN
        minSdk = 29                            // Android 10 — >95% device coverage in 2026
        targetSdk = 36                         // bump to 37 when Android 17 ships + Play forces
        // Play rejects ANY previously-uploaded versionCode — bump +1 before
        // every Play upload, even if that upload was never released.
        versionCode = 4
        // READ from AppVersion.xcconfig rather than copied, because copying is
        // what goes wrong: a literal here drifted 88 patch versions behind the
        // Apple apps in a shipped app, so an Android user reporting a problem
        // named a version family that had not existed for weeks.
        // tools/test_version_contract.py holds this.
        versionName = marketingVersion

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }

        // The Worker (docs/WORKER.md) and the sign-in client ids. None is a
        // secret, but each is the owner's to create (WORKER.md, Needs Ben), so
        // each comes from a gradle property (~/.gradle/gradle.properties or -P)
        // and stays a REPLACE_WITH placeholder in git. While one is a
        // placeholder, that sign-in shows as not set up (WorkerConfig).
        fun account(name: String, placeholder: String) = buildConfigField(
            "String",
            name,
            "\"${providers.gradleProperty("EARDRAMA_$name").orNull ?: placeholder}\"",
        )
        account("WORKER_BASE_URL", "REPLACE_WITH_WORKER_BASE_URL")
        // The Web OAuth client id: Credential Manager asks for a token addressed to it.
        account("GOOGLE_WEB_CLIENT_ID", "REPLACE_WITH_GOOGLE_WEB_CLIENT_ID")
        // The Sign in with Apple Services ID, and the https return URL registered for it.
        account("APPLE_SERVICES_ID", "REPLACE_WITH_APPLE_SERVICES_ID")
        account("APPLE_RETURN_URL", "https://eardrama.org/auth/apple/")
    }

    lint {
        abortOnError = true
        warningsAsErrors = true
        checkReleaseBuilds = true
        lintConfig = file("lint.xml")
    }

    signingConfigs {
        // Upload signing config — keystore + creds live in gradle.properties
        // (git-excluded). Play App Signing handles the production key.
        create("release") {
            val keystorePath = providers.gradleProperty("UPLOAD_KEYSTORE_PATH").orNull
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = providers.gradleProperty("UPLOAD_KEYSTORE_PASSWORD").orNull
                keyAlias = providers.gradleProperty("UPLOAD_KEY_ALIAS").orNull
                keyPassword = providers.gradleProperty("UPLOAD_KEY_PASSWORD").orNull
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            isDebuggable = true
        }
        release {
            // R8 always on for release — single highest-impact perf knob.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "/META-INF/LICENSE*",
            )
        }
    }

    androidResources {
        noCompress += "sqlite"
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all { it.systemProperty("earDramaSeed", catalogSeedPath) }
    }
}

// JVM unit tests run the real query code on the desktop build of the same
// bundled SQLite (FTS5 included); the Android build of it loads a .so that a
// JVM cannot.
configurations.configureEach {
    if (name.endsWith("UnitTestRuntimeClasspath")) {
        exclude(group = "androidx.sqlite", module = "sqlite-bundled-android")
    }
}

kotlin {
    compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 }
}

dependencies {
    // Compose BOM — pins ui / foundation / material together
    implementation(platform(libs.compose.bom))
    androidTestImplementation(platform(libs.compose.bom))
    implementation(libs.bundles.compose.core)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    // Adaptive layouts (tablet + Chromebook from day one per ANDROID-DESIGN §6.6)
    implementation(libs.bundles.adaptive)

    // Activity + lifecycle (edge-to-edge + predictive back)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.viewmodel.compose)

    // Navigation 3
    implementation(libs.bundles.nav3)
    implementation(libs.hilt.navigation.compose)

    // Hilt
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    // Coroutines + serialization
    implementation(libs.coroutines.core)
    implementation(libs.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    // Persistence: Room + DataStore + Tink (encrypted secrets)
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)
    implementation(libs.datastore.preferences)
    implementation(libs.tink.android)

    // Catalog: the published SQLite file, read through the bundled driver
    implementation(libs.sqlite)
    implementation(libs.sqlite.bundled)

    // Playback: Media3 session service + ExoPlayer
    implementation(libs.bundles.media3)

    // Episode downloads: a persisted job per download, across process death and reboot
    implementation(libs.work.runtime)

    // Image loading
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    // Networking — OkHttp shared with Coil; Ktor on top
    implementation(libs.okhttp)
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.serialization.json)

    // Auth — Credential Manager + Google one-tap. Wire Supabase or your
    // own backend on top.
    implementation(libs.credentials)
    implementation(libs.credentials.play.services)
    implementation(libs.googleid)
    implementation(libs.browser)

    // Supabase (uncomment if your project uses it)
    // implementation(platform(libs.supabase.bom))
    // implementation(libs.supabase.auth)
    // implementation(libs.supabase.postgrest)
    // implementation(libs.supabase.compose.auth)

    // Biometric (sensitive Profile actions)
    implementation(libs.biometric.compose)

    // Splash screen API
    implementation(libs.splashscreen)

    // Tests
    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.turbine)
    testImplementation(libs.mockk)
    testImplementation(libs.ktor.client.mock)
    testImplementation(libs.sqlite.bundled.jvm)

    androidTestImplementation(libs.junit.ext)
    androidTestImplementation(libs.espresso.core)
    androidTestImplementation(libs.compose.ui.test.junit4)
}
