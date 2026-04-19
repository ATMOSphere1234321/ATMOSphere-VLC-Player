/*
 * ATMOSphere: explicit Presentation for VLC's secondary-display output.
 *
 * VLC already ships `org.videolan.libvlc.util.DisplayManager` which uses its
 * own internal `SecondaryDisplay` class when clone mode is enabled. That path
 * stays the default on ATMOSphere devices with an external display attached.
 *
 * This class provides a *parallel* path that lives inside the VLC fork so
 * the ATMOSphere firmware pre-build gate (CM-MC18) can verify its presence
 * and the runtime can switch to a Presentation we control end-to-end. It
 * exposes a SurfaceView whose `holder.surface` is handed straight to
 * `IVLCVout.setVideoSurface(...)` on the main-thread media player.
 *
 * Activation: `setprop vlc.atmosphere.use_atmosphere_presentation true`.
 * Opt-out entirely: `setprop vlc.atmosphere.dual_display false`.
 */
package org.videolan.vlc.gui.video

import android.app.Presentation
import android.content.Context
import android.os.Bundle
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.widget.FrameLayout

class VideoSecondaryPresentation(
    context: Context,
    display: Display,
    private val onReady: (Surface) -> Unit,
    private val onChanged: (Int, Int) -> Unit,
    private val onLost: () -> Unit,
) : Presentation(context, display), SurfaceHolder.Callback {

    private lateinit var surfaceView: SurfaceView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        surfaceView = SurfaceView(context)
        val layout = FrameLayout(context)
        layout.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        setContentView(layout)
        surfaceView.holder.addCallback(this)
    }

    val videoSurface: Surface?
        get() = if (::surfaceView.isInitialized) surfaceView.holder.surface else null

    override fun surfaceCreated(holder: SurfaceHolder) {
        onReady(holder.surface)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        onChanged(width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        onLost()
    }
}
