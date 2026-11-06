// App chủ tối giản cho đo hiện bàn phím (docs/PERF-IME-SHOW.md): một EditText, không thư viện.
// Chỉ dùng cho :benchmark (Macrobenchmark) — không phát hành.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.viettelex.perfhost"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.viettelex.perfhost"
        minSdk = 30; targetSdk = 36
        versionCode = 1; versionName = "1"
    }
    buildTypes {
        create("benchmark") {
            initWith(getByName("debug"))
            isDebuggable = false
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release")
        }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
