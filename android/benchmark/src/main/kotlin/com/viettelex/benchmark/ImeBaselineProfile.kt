package com.viettelex.benchmark

import androidx.benchmark.macro.junit4.BaselineProfileRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Sinh Baseline + Startup Profile cho bàn phím (đường: process mới → hiện bàn phím → gõ → đổi bảng
 * phím → ẩn). Chỉ chạy khi gọi rõ (vt.genProfile=1) — xem docs/PERF-IME-SHOW.md mục "Baseline Profile":
 * kết quả `ImeBaselineProfile_generate-baseline-prof.txt` chép vào app/src/main/baseline-prof.txt.
 */
@RunWith(AndroidJUnit4::class)
class ImeBaselineProfile {
    @get:Rule val rule = BaselineProfileRule()

    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun generate() {
        assumeTrue("Sinh profile: -Pandroid.testInstrumentationRunnerArguments.vt.genProfile=1",
            InstrumentationRegistry.getArguments().getString("vt.genProfile") == "1")
        rule.collect(packageName = IME, includeInStartupProfile = true, maxIterations = 8, stableIterations = 3) {
            // collect() force-stop bàn phím mỗi vòng ⇒ hệ thống đổi sang bàn phím khác: chọn lại.
            device.executeShellCommand("ime enable $IME_ID")
            device.executeShellCommand("ime set $IME_ID")
            device.executeShellCommand("am start -W -n $HOST/.HostActivity")
            device.wait(Until.hasObject(By.pkg(HOST).desc("show")), 5_000)
            device.findObject(By.pkg(HOST).desc("show"))?.click()
            Thread.sleep(1_500)
            val h = device.displayHeight; val w = device.displayWidth
            val top = (h * 0.62f).toInt(); val kbH = h - (h * 0.04f).toInt() - top
            // Gõ vài chữ hàng giữa, dấu cách, xoá; đổi ?123 ↔ chữ.
            repeat(12) { i -> device.click(w * (1 + (i * 7) % 9) / 10, top + (kbH * 0.45f).toInt()); Thread.sleep(80) }
            device.click(w / 2, top + kbH - kbH / 10); Thread.sleep(80)
            repeat(2) { device.click(w / 14, top + kbH - kbH / 10); Thread.sleep(300) }
            device.findObject(By.pkg(HOST).desc("hide"))?.click()
            Thread.sleep(800)
        }
    }

    companion object {
        const val IME = "com.viettelex.android"
        const val IME_ID = "$IME/.ime.VietTelexIME"
        const val HOST = "com.viettelex.perfhost"
    }
}
