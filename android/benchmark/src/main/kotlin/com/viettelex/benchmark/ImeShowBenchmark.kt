package com.viettelex.benchmark

import android.graphics.Rect
import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.ExperimentalMetricApi
import androidx.benchmark.macro.FrameTimingMetric
import androidx.benchmark.macro.Metric
import androidx.benchmark.macro.TraceSectionMetric
import androidx.benchmark.macro.TraceSectionMetric.Mode
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.benchmark.perfetto.ExperimentalPerfettoCaptureApi
import androidx.benchmark.perfetto.PerfettoConfig
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Thời gian hiện bàn phím VietTelex (cold / warm) + vẽ khi gõ / đổi bảng phím, đo bằng mốc Perfetto
 * "VT.*" của IME (ImeTrace) và "Host.*" của app chủ :perfhost (khuôn AOSP ImePerfTest:
 * show(ime()) → WindowInsetsAnimation.onStart / onEnd).
 *
 * App ĐÍCH của Macrobenchmark là chính bàn phím (com.viettelex.android): CompilationMode áp cho IME,
 * killProcess() giết process IME (cold), FrameTimingMetric đo khung của process IME. App chủ mở bằng
 * `am start`. Lưu ý: force-stop (killProcess, compile --reset) bàn phím ĐANG CHỌN làm hệ thống đổi
 * sang bàn phím khác ⇒ mỗi vòng chọn lại VietTelex ([selectIme]); ở cold, chọn lại NẰM TRONG khối đo
 * (process bàn phím khởi động đúng lúc người dùng chạm ô, như thật). Xem docs/PERF-IME-SHOW.md — không chạy trong bộ unit test mặc định.
 */
@OptIn(ExperimentalMetricApi::class, ExperimentalPerfettoCaptureApi::class, androidx.benchmark.ExperimentalBenchmarkConfigApi::class)
@RunWith(AndroidJUnit4::class)
class ImeShowBenchmark {
    @get:Rule val rule = MacrobenchmarkRule()

    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val args = InstrumentationRegistry.getArguments()
    private val iterations = args.getString("vt.iterations")?.toIntOrNull() ?: 15
    /** vt.compilation=none | partial (Baseline Profile nếu có) | full. Mặc định none = tệ nhất (mới cài). */
    private val compilation: CompilationMode = when (args.getString("vt.compilation")) {
        "partial" -> CompilationMode.Partial()
        "full" -> CompilationMode.Full()
        else -> CompilationMode.None()
    }
    private val config = PerfettoConfig.Benchmark(listOf(IME, HOST), false)

    @Before fun checkInstalled() {
        val list = device.executeShellCommand("ime list -a -s")
        assertTrue("Chưa cài bàn phím bản đo: ./gradlew :app:installBenchmark", IME_ID in list)
    }

    private fun selectIme() {
        device.executeShellCommand("ime enable $IME_ID")
        device.executeShellCommand("ime set $IME_ID")
    }

    private fun section(name: String, mode: Mode = Mode.Sum, host: Boolean = false): Metric =
        TraceSectionMetric(name, mode, label = name.substringAfter('.') + "_" + mode.javaClass.simpleName,
            targetPackageOnly = !host)

    private fun showMetrics() = listOf(
        section("VT.onCreate"), section("VT.onCreateInputView"), section("VT.onStartInputView"),
        section("VT.showToFirstDraw"), section("VT.kbDraw", Mode.First), section("VT.layoutBuild"),
        section("Host.imeShowToAnimStart", host = true), section("Host.imeShowToAnimEnd", host = true),
    )

    private fun openHost() {
        device.executeShellCommand("am start -W -n $HOST/.HostActivity")
        device.wait(Until.hasObject(By.pkg(HOST).desc("show")), 5_000)
    }

    private fun tapHost(desc: String) {
        val o = device.findObject(By.pkg(HOST).desc(desc)) ?: run { openHost(); device.findObject(By.pkg(HOST).desc(desc)) }
        o!!.click()
    }

    private fun imeShown(): Boolean = device.executeShellCommand("dumpsys input_method").contains("mInputShown=true")

    private fun waitIme(shown: Boolean) {
        val until = System.currentTimeMillis() + 4_000
        while (imeShown() != shown && System.currentTimeMillis() < until) Thread.sleep(50)
        Thread.sleep(600)   // hết hoạt ảnh trượt + khung đầu đã vẽ
    }

    private fun show() { tapHost("show"); waitIme(true) }
    private fun hide() { tapHost("hide"); waitIme(false) }

    /** Lần hiện đầu sau khi giết process IME (onCreate + onCreateInputView + JIT nguội). */
    @Test fun showCold() = rule.measureRepeated(IME, showMetrics(), iterations, config, compilation,
        startupMode = null, setupBlock = {
            openHost(); hide()
            killProcess()          // hệ thống chuyển sang bàn phím khác
            Thread.sleep(1_000)
        }) { selectIme(); show() }

    /** Ẩn rồi hiện lại khi process + input view còn sống. */
    @Test fun showWarm() = rule.measureRepeated(IME, showMetrics(), iterations, config, compilation,
        startupMode = null, setupBlock = { selectIme(); openHost(); show(); hide() }) { show() }

    /** Gõ 20 chữ: chạm → lượt vẽ kế (VT.keyToDraw), xử lý phím (VT.onKey), khung hình process IME. */
    @Test fun typing() = rule.measureRepeated(IME,
        listOf(FrameTimingMetric(), section("VT.keyToDraw", Mode.Average), section("VT.onKey", Mode.Average),
            section("VT.kbDraw", Mode.Count)),
        iterations, config, compilation, startupMode = null,
        setupBlock = { selectIme(); openHost(); show() }) {
        val kb = keyboardBounds()
        // Hàng chữ thứ hai ("asdfghjkl") ≈ 45% chiều cao vùng phím, quét ngang.
        val y = kb.top + (kb.height() * 0.45f).toInt()
        repeat(20) { i -> device.click(kb.left + kb.width() * (1 + (i * 7) % 9) / 10, y); Thread.sleep(60) }
        Thread.sleep(300)
    }

    /** Đổi bảng phím chữ ↔ ?123 (VT.planeSwitch, dựng / lấy layout từ cache). */
    @Test fun planeSwitch() = rule.measureRepeated(IME,
        listOf(FrameTimingMetric(), section("VT.planeSwitch", Mode.Average), section("VT.layoutBuild", Mode.Count),
            section("VT.kbDraw", Mode.Average)),
        iterations, config, compilation, startupMode = null,
        setupBlock = { selectIme(); openHost(); show() }) {
        val kb = keyboardBounds()
        // Phím ?123 ở góc dưới-trái (hàng cuối), cả hai bảng cùng chỗ.
        val x = kb.left + kb.width() / 14; val y = kb.bottom - kb.height() / 10
        repeat(6) { device.click(x, y); Thread.sleep(250) }
    }

    /** Vùng phím (cửa sổ IME): node a11y của bàn phím; không thấy ⇒ 38% dưới màn hình. */
    private fun keyboardBounds(): Rect {
        val nodes = device.findObjects(By.pkg(IME))
        if (nodes.isNotEmpty()) {
            val r = Rect(nodes[0].visibleBounds); nodes.forEach { r.union(it.visibleBounds) }
            if (r.height() > 100) return r
        }
        val h = device.displayHeight; val w = device.displayWidth
        return Rect(0, (h * 0.62f).toInt(), w, h - (h * 0.04f).toInt())
    }

    companion object {
        const val IME = "com.viettelex.android"
        const val IME_ID = "$IME/.ime.VietTelexIME"
        const val HOST = "com.viettelex.perfhost"
    }
}
