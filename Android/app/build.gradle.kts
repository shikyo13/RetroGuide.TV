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
        versionCode = 1
        versionName = "0.1.0"
        // Exactly the ABIs Scripts/build-core.sh built the Swift core for.
        ndk { abiFilters += file("src/main/jniLibs").list().orEmpty().toList() }
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
}
