// Đo thời gian hiện bàn phím + vẽ khi gõ (Macrobenchmark, chạy trên emulator/máy thật) —
// docs/PERF-IME-SHOW.md. KHÔNG nằm trong bộ unit test mặc định; chạy bằng
//   ./gradlew :benchmark:connectedBenchmarkAndroidTest
// sau khi cài bàn phím bản đo (:app:installBenchmark) và host (:perfhost:installBenchmark).
plugins {
    id("com.android.test")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.viettelex.benchmark"
    compileSdk = 36
    defaultConfig {
        minSdk = 30; targetSdk = 36
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Emulator: số đo chỉ để so trước/sau trên CÙNG máy ảo (ghi rõ là số emulator).
        testInstrumentationRunnerArguments["androidx.benchmark.suppressErrors"] = "EMULATOR,LOW-BATTERY,UNLOCKED"
    }
    buildTypes {
        create("benchmark") {
            isDebuggable = true
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release")
        }
    }
    // Không cài app đích qua test module: bàn phím (com.viettelex.android) cài riêng bằng :app:installBenchmark.
    targetProjectPath = ":perfhost"
    experimentalProperties["android.experimental.self-instrumenting"] = true
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation("androidx.test.ext:junit:1.3.0")
    implementation("androidx.test:runner:1.7.0")
    implementation("androidx.test.uiautomator:uiautomator:2.4.0")
    implementation("androidx.benchmark:benchmark-macro-junit4:1.5.0")
}
androidComponents { beforeVariants(selector().all()) { it.enable = it.buildType == "benchmark" } }
