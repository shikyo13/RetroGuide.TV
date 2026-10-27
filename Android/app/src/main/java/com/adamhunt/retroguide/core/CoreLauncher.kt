package com.adamhunt.retroguide.core

import android.content.Context
import android.os.Build
import android.provider.Settings
import java.io.File
import java.util.UUID

/** Prepares the core's files and starts it for this install. */
object CoreLauncher {
    /** RetroGuideKit's data files, shipped as assets. */
    private val kitResources = listOf("curated-channels.json", "genre-taxonomy.json", "title-classification.bin")
    private const val RESOURCES_FOLDER = "kit"
    private const val CORE_FOLDER = "core"
    private const val PREFERENCES = "install"
    private const val INSTALL_ID = "id"
    private const val COPIED_VERSION = "kitResourcesVersion"

    suspend fun start(context: Context, core: CoreClient, tokens: Map<String, String>): StartResult {
        val app = context.applicationContext
        val version = app.packageManager.getPackageInfo(app.packageName, 0).versionName ?: "0"
        return core.start(
            filesDirectory = File(app.filesDir, CORE_FOLDER).path,
            resourcesDirectory = kitResourcesDirectory(app, version).path,
            installID = installID(app),
            deviceName = deviceName(app),
            appVersion = version,
            osVersion = Build.VERSION.RELEASE,
            tokens = tokens,
        )
    }

    /** Copies the Kit's data files out of the assets once per app version. */
    private fun kitResourcesDirectory(context: Context, version: String): File {
        val directory = File(context.filesDir, RESOURCES_FOLDER).apply { mkdirs() }
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (preferences.getString(COPIED_VERSION, null) != version) {
            for (name in kitResources) {
                context.assets.open(name).use { input -> File(directory, name).outputStream().use(input::copyTo) }
            }
            preferences.edit().putString(COPIED_VERSION, version).apply()
        }
        return directory
    }

    /** A random id made once per install, so each server lists this device once. */
    private fun installID(context: Context): String {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        return preferences.getString(INSTALL_ID, null) ?: UUID.randomUUID().toString().also {
            preferences.edit().putString(INSTALL_ID, it).apply()
        }
    }

    private fun deviceName(context: Context): String =
        Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL
}
