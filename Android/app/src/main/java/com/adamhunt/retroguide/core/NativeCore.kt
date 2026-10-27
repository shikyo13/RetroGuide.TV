package com.adamhunt.retroguide.core

/** The Swift core (libRetroGuideCore.so): one blocking JSON request function. */
internal object NativeCore {
    init {
        System.loadLibrary("RetroGuideCore")
    }

    @JvmStatic
    external fun call(request: String): String
}
