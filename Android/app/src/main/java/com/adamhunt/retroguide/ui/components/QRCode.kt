package com.adamhunt.retroguide.ui.components

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

private const val QR_MODULES = 25
private const val DARK = 0xFF000000.toInt()
private const val LIGHT = 0xFFFFFFFF.toInt()

/** A QR code for [text], one pixel per module (draw without smoothing). */
@Composable
fun qrCode(text: String): ImageBitmap = remember(text) {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, QR_MODULES, QR_MODULES)
    val pixels = IntArray(matrix.width * matrix.height) { index ->
        if (matrix[index % matrix.width, index / matrix.width]) DARK else LIGHT
    }
    Bitmap.createBitmap(pixels, matrix.width, matrix.height, Bitmap.Config.ARGB_8888).asImageBitmap()
}
