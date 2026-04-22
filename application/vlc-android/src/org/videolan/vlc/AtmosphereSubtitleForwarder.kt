// SPDX-License-Identifier: Apache-2.0
// AtmosphereSubtitleForwarder.kt — VLC Tier C1 subtitle-to-Presenter hook.
//
// QA Session 26.04.01 User #6 Tier C1 — vlc-player fork.
//
// STATUS — partial coverage.
// libvlc renders SPU subtitles natively in its C video-output (VOUT)
// pipeline, directly on the surface. The Java bindings in
// org.videolan.libvlc do NOT expose a per-cue text callback; the only
// subtitle-related events reachable from Java are:
//   * MediaPlayer.Event.ESAdded     — a subtitle track was detected
//   * MediaPlayer.Event.ESDeleted   — a subtitle track was removed
//   * MediaPlayer.Event.ESSelected  — the active track changed
// No Java-side event carries the active cue TEXT.
//
// A full Tier C1 hook that routes per-cue text requires a libvlc
// native patch (adding a JNI binding for libvlc_video_set_subtitle_
// text_callback). That work is deferred; in the meantime this forwarder
// still participates in the Tier B AccessibilityService path because
// VLC's overlay subtitle panel (settings → video → subtitles) uses a
// standard TextView that the Presenter AccessibilityService CAN detect.
//
// This class is therefore a placeholder + track-change notifier. It
// forwards an EMPTY cue (to clear any stale Presenter text) on
// ESDeleted / ESSelected changes, so the secondary display correctly
// reflects subtitle-off state.

package org.videolan.vlc

import android.os.IBinder
import android.util.Log
import org.videolan.libvlc.MediaPlayer
import org.videolan.medialibrary.interfaces.media.IMedia

object AtmosphereSubtitleForwarder {

    private const val TAG = "ATMOSphere::VlcSubFwd"
    private const val PKG = "atmosphere.videolan.vlc"

    @Volatile private var currentText: String = ""
    @Volatile private var vomBinder: IBinder? = null

    /** Called from PlaybackService.mediaPlayerListener on every event. */
    fun onEvent(event: MediaPlayer.Event) {
        when (event.type) {
            MediaPlayer.Event.ESSelected,
            MediaPlayer.Event.ESDeleted -> {
                if (event.esChangedType == IMedia.Track.Type.Text) {
                    // Track change — clear any stale cue on Presenter.
                    if (currentText.isNotEmpty()) {
                        currentText = ""
                        dispatch("")
                    }
                }
            }
            MediaPlayer.Event.Stopped,
            MediaPlayer.Event.EndReached -> {
                if (currentText.isNotEmpty()) {
                    currentText = ""
                    dispatch("")
                }
            }
        }
    }

    /** Called from org.videolan.vlc subtitle UI when a cue is rendered
     *  in a Java-side TextView (rare — overlays only). Will be invoked
     *  by a future PR once the native libvlc_video_set_subtitle_text_callback
     *  JNI binding lands. */
    @Suppress("unused")
    fun forwardCue(text: String) {
        val t = text.trim()
        if (t == currentText) return
        currentText = t
        dispatch(t)
    }

    private fun dispatch(text: String) {
        try {
            val binder = vomBinder ?: (getServiceBinder("video_output")?.also {
                vomBinder = it
            })
            if (binder == null) return
            val stubCls = Class.forName("android.media.IVideoOutputManager\$Stub")
            val vom = stubCls.getMethod("asInterface", IBinder::class.java).invoke(null, binder)
            vom.javaClass.getMethod(
                "routeSubtitleCue",
                String::class.java, String::class.java,
                Long::class.javaPrimitiveType, Long::class.javaPrimitiveType,
                String::class.java
            ).invoke(vom, PKG, text, 0L, 0L, "")
        } catch (t: Throwable) {
            // Non-ATMOSphere build or service unavailable — stay silent.
            Log.v(TAG, "forward failed: ${t.message}")
        }
    }

    private fun getServiceBinder(name: String): IBinder? = try {
        val sm = Class.forName("android.os.ServiceManager")
        sm.getMethod("getService", String::class.java).invoke(null, name) as IBinder?
    } catch (t: Throwable) {
        null
    }
}
