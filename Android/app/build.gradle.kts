plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
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
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    buildFeatures { compose = true }

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
}
