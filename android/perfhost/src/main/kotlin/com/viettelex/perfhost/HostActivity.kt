package com.viettelex.perfhost

import android.app.Activity
import android.os.Bundle
import android.os.Trace
import android.view.Gravity
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout

/**
 * Host đo hiện bàn phím theo khuôn AOSP ImePerfTest: nút "show" gọi show(ime()) và mở hai async
 * section; WindowInsetsAnimation.onStart đóng "Host.imeShowToAnimStart", onEnd đóng
 * "Host.imeShowToAnimEnd". Nút "hide" ẩn bàn phím (đo warm). Không thư viện ngoài.
 */
class HostActivity : Activity() {
    private lateinit var field: EditText
    private var startOpen = false
    private var endOpen = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        field = EditText(this).apply { contentDescription = "field"; hint = "field" }
        val show = Button(this).apply { text = "show"; contentDescription = "show"; setOnClickListener { showIme() } }
        val hide = Button(this).apply { text = "hide"; contentDescription = "hide"; setOnClickListener { hideIme() } }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.TOP
            isFocusableInTouchMode = true
            addView(field); addView(show); addView(hide)
        }
        root.setWindowInsetsAnimationCallback(object : WindowInsetsAnimation.Callback(DISPATCH_MODE_STOP) {
            override fun onStart(a: WindowInsetsAnimation, b: WindowInsetsAnimation.Bounds): WindowInsetsAnimation.Bounds {
                if (startOpen && (a.typeMask and WindowInsets.Type.ime()) != 0) {
                    startOpen = false; Trace.endAsyncSection("Host.imeShowToAnimStart", 1)
                }
                return b
            }
            override fun onProgress(i: WindowInsets, r: MutableList<WindowInsetsAnimation>) = i
            override fun onEnd(a: WindowInsetsAnimation) {
                if (endOpen && (a.typeMask and WindowInsets.Type.ime()) != 0) {
                    endOpen = false; Trace.endAsyncSection("Host.imeShowToAnimEnd", 2)
                }
            }
        })
        setContentView(root)
        root.requestFocus()
    }

    private fun showIme() {
        field.requestFocus()
        if (!startOpen) { Trace.beginAsyncSection("Host.imeShowToAnimStart", 1); startOpen = true }
        if (!endOpen) { Trace.beginAsyncSection("Host.imeShowToAnimEnd", 2); endOpen = true }
        window.insetsController?.show(WindowInsets.Type.ime())
    }

    private fun hideIme() {
        window.insetsController?.hide(WindowInsets.Type.ime())
        (field.parent as LinearLayout).requestFocus()
    }
}
