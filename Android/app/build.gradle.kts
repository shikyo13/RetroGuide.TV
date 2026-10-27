plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.adamhunt.retroguide"
    compileSdk {
        version = release(37) { minorApiLevel = 2 }
    }

    defaultConfig {
        applicationId = "com.adamhunt.retroguide"
        minSdk = 28
        targetSdk = 36
        // One version for every platform: project.yml's MARKETING_VERSION, and its
        // build number (20261027.1) as 2026102701.
        versionCode = appleVersion("CURRENT_PROJECT_VERSION").split(".").let { (day, build) -> "$day${build.padStart(2, '0')}".toInt() }
        versionName = appleVersion("MARKETING_VERSION")
        // Exactly the ABIs Scripts/build-core.sh built the Swift core for.
        ndk { abiFilters += file("src/main/jniLibs").list().orEmpty().toList() }
    }

    // Play upload signing, from the developer's own Gradle properties
    // (~/.gradle/gradle.properties: retroguide.uploadStoreFile, …StorePassword,
    // …KeyAlias, …KeyPassword); never in the repository. Without them a release
    // build is signed with the debug key, for testing on a device only.
    val upload = listOf("StoreFile", "StorePassword", "KeyAlias", "KeyPassword")
        .associateWith { providers.gradleProperty("retroguide.upload$it").orNull }
    signingConfigs {
        if (upload.values.all { it != null }) {
            create("upload") {
                storeFile = file(upload.getValue("StoreFile")!!)
                storePassword = upload.getValue("StorePassword")
                keyAlias = upload.getValue("KeyAlias")
                keyPassword = upload.getValue("KeyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // RetroGuideKit's data files (channel catalog, genre taxonomy, title
    // classification) ship as assets; the core reads them from app storage.
    sourceSets["main"].assets.directories += "../../Packages/RetroGuideKit/Sources/RetroGuideKit/Resources"
    // License texts shown in Settings › Acknowledgements.
    sourceSets["main"].assets.directories += "../../LICENSES"

    packaging {
        // libmpv and the Swift runtime both ship libc++_shared.so; keep the app's own (newer NDK) copy.
        jniLibs { pickFirsts += "**/libc++_shared.so" }
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.tv.material)
    implementation(libs.activity.compose)
    implementation(libs.libmpv)
    implementation(libs.serialization.json)
    implementation(libs.coroutines.android)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    implementation(libs.okhttp)
    implementation(libs.zxing.core)
    implementation(libs.tvprovider)
}

/** A setting from the Apple app's project.yml (`KEY: "value"`). */
fun appleVersion(key: String): String =
    rootProject.file("../project.yml").readLines()
        .firstNotNullOf { line -> Regex("""^\s*$key:\s*"([^"]+)"""").find(line)?.groupValues?.get(1) }
