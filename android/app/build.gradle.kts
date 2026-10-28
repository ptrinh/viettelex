import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "com.viettelex.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.viettelex.android"
        minSdk = 26; targetSdk = 36
        versionCode = 27; versionName = "1.5.20"
    }
    // Upload key: keystore.properties (gitignored, ~/keystores/viettelex.jks). Thiếu file → release unsigned.
    val keystoreProps = Properties().apply {
        val f = rootProject.file("keystore.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    if (keystoreProps.isNotEmpty()) {
        signingConfigs {
            create("upload") {
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }
    buildTypes { release {
        if (keystoreProps.isNotEmpty()) signingConfig = signingConfigs.getByName("upload")
        isMinifyEnabled = true; isShrinkResources = true
        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    androidResources { noCompress += listOf("bin") }
    // Module Play Feature Delivery (on-demand) — chỉ vào AAB; assembleRelease (APK GitHub) không có.
    dynamicFeatures += setOf(":translate")
}
dependencies {
    implementation(project(":telexcore")); implementation(project(":keyboard"))
    implementation("androidx.core:core-ktx:1.13.1")
    // ExploreByTouchHelper (TalkBack cho từng phím) — đã có sẵn qua phụ thuộc bắc cầu, khai rõ.
    implementation("androidx.customview:customview:1.0.0")
    // Process ":settings" tự khởi tạo EmojiCompat (androidx.startup chỉ chạy ở process chính) —
    // cùng bản đã có sẵn qua Compose, chỉ khai rõ để gọi được.
    implementation("androidx.startup:startup-runtime:1.1.1")
    implementation("androidx.emoji2:emoji2:1.3.0")
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-tooling-preview")   // không có @Preview trong main ⇒ chỉ bản debug
    // VietTelex Plus + ủng hộ: Google Play Billing (thư viện chính chủ của Google).
    implementation("com.android.billingclient:billing:8.0.0")
    // Dịch trên máy (Plus): ML Kit nằm ở module on-demand :translate (APK gốc không có);
    // Play Feature Delivery tải module khi người dùng bấm trong app.
    implementation("com.google.android.play:feature-delivery:2.1.0")
    // Billing kéo vài androidx cũ (livedata 2.8.3, fragment 1.1.0) — nâng lên bản mới hơn
    // (đã có sẵn trong cache Gradle) để build --offline chạy được; chỉ là ràng buộc
    // phiên bản, không thêm thư viện mới.
    constraints {
        implementation("androidx.lifecycle:lifecycle-livedata:2.8.7")
        implementation("androidx.fragment:fragment:1.5.4")
    }
    testImplementation("junit:junit:4.13.2")
}
// Bộ test chậm (benchmark ImePerfBenchTest): VT_SLOW_TESTS=1 bật; là input để đổi giá trị thì chạy lại.
tasks.withType<Test>().configureEach {
    inputs.property("vtSlowTests", System.getenv("VT_SLOW_TESTS") ?: "")
}
