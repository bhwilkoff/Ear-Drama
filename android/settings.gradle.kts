// Top-level settings — repository + plugin resolution + module list.
// Modular from day one: as the app grows, split feature/ and core/
// modules out of :app and add them here. The single-module shape is
// the smallest viable starting point; don't carry it past v1.

pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "AppName"
include(":app")
// The Wear OS stub (Decision 056): its own app, sharing no code with :app yet.
include(":wear")
// Add as the project grows:
// include(":core:ui", ":core:data", ":core:domain", ":core:network")
// include(":feature:find", ":feature:learn", ":feature:profile")
// include(":baselineprofile")
