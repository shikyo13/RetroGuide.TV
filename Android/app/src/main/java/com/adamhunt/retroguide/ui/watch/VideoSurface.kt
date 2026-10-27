package com.adamhunt.retroguide.ui.watch

import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.adamhunt.retroguide.player.MpvPlayer

/** The video picture: one SurfaceView that mpv draws into, moved and resized by its parent. */
@Composable
fun VideoSurface(player: MpvPlayer, modifier: Modifier = Modifier) {
    AndroidView(
        modifier = modifier,
        factory = { context ->
            SurfaceView(context).apply {
                holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) = player.attach(holder.surface)
                    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = player.resize(width, height)
                    override fun surfaceDestroyed(holder: SurfaceHolder) = player.detach()
                })
            }
        },
    )
}
