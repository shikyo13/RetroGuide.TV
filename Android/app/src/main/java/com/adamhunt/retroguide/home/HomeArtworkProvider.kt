package com.adamhunt.retroguide.home

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * Serves the home screen row's artwork to the TV launcher. Server image
 * addresses carry access tokens, so the app downloads the pictures itself
 * and shares only the files (the Apple app does the same for Top Shelf).
 */
class HomeArtworkProvider : ContentProvider() {
    companion object {
        const val AUTHORITY = "com.adamhunt.retroguide.homeartwork"
        const val FOLDER = "home-artwork"

        fun uri(file: File): Uri = Uri.Builder().scheme("content").authority(AUTHORITY).appendPath(file.name).build()
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val context = context ?: throw FileNotFoundException()
        val name = uri.lastPathSegment ?: throw FileNotFoundException()
        val folder = File(context.cacheDir, FOLDER)
        val file = File(folder, name)
        // Only plain names inside the artwork folder.
        if (file.parentFile != folder || !file.exists()) throw FileNotFoundException(name)
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri) = "image/jpeg"
    override fun onCreate() = true
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
