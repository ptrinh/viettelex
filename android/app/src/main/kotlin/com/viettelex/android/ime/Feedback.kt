package com.viettelex.android.ime

import android.content.Context
import android.media.AudioManager
import android.view.HapticFeedbackConstants
import android.view.View

/**
 * Âm + rung ở TOUCH-DOWN (spec §8). Âm: AudioManager.playSoundEffect — chỉ kêu khi
 * "Âm thanh khi chạm" của hệ thống bật. Rung: toggle hapticFeedback (mặc định TẮT),
 * Android không cần quyền đặc biệt.
 */
class Feedback(ctx: Context) {
    private val audio = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    @Volatile var hapticsEnabled = false

    fun click(kind: Int, view: View) {
        audio.playSoundEffect(when (kind) {
            DELETE -> AudioManager.FX_KEYPRESS_DELETE
            SPACE -> AudioManager.FX_KEYPRESS_SPACEBAR
            RETURN -> AudioManager.FX_KEYPRESS_RETURN
            else -> AudioManager.FX_KEYPRESS_STANDARD
        })
        if (hapticsEnabled) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP,
                HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
        }
    }

    companion object {
        const val LETTER = 0
        const val DELETE = 1
        const val MODIFIER = 2
        const val SPACE = 3
        const val RETURN = 4
    }
}
