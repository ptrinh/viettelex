package com.viettelex.keyboard

// Onboarding người dùng mới + bộ chọn hồ sơ nhanh — docs/ONBOARDING-SPEC.md §2/§3/§5. Phần THUẦN
// để test được: giá trị từng hồ sơ, hồ sơ đang khớp ("Tuỳ chỉnh" khi không khớp), màn onboarding
// nào cần hiện, nhận diện người dùng cũ khi nâng cấp, yêu cầu ngôn ngữ khởi đầu cho bàn phím.
// Song sinh iOS Shared/OnboardingProfile.swift — sửa bên này thì sửa y hệt bên kia (OnboardingTest
// hai bên cùng số liệu).
//
// Hồ sơ = bộ cài đặt cụ thể: chọn hồ sơ GHI THẲNG giá trị vào từng key hiện có rồi thôi — không lưu
// "chế độ" nào chi phối về sau. Chỉ lưu thêm onboardingDone + onboardingProfile, cờ một lần của thẻ
// người dùng cũ, và yêu cầu ngôn ngữ cho bàn phím. Không key nào ở đây nằm trong sao lưu
// ([BackupSettings]) — không gửi đi đâu.

enum class OnboardingProfile(val id: String, val viTitle: String, val example: String, val samples: List<String>) {
    VI("vi", "Chủ yếu tiếng Việt", "Chiều nay mình đi cà phê nhé", // l10n-key
        listOf("Chiều nay mình đi cà phê nhé", "Cảm ơn bạn nhiều lắm")),
    MIXED("mixed", "Việt + Anh nhiều", "Chiều nay họp team, nhớ check mail nha", // l10n-key
        listOf("Mai họp team lúc 9h, nhớ confirm nhé", "Gửi mình file slide trước deadline nha", "His car is very fast")),
    EN("en", "Chủ yếu tiếng Anh", "See you at the meeting, nhớ mang laptop nhé", // l10n-key
        listOf("See you at the meeting, nhớ mang laptop nhé", "Thanks, I will check my email tonight"));

    val title: String get() = tr(viTitle)

    /** Ngôn ngữ khởi đầu của bàn phím (§3: hồ sơ `en` bắt đầu ở Tiếng Anh). */
    val keyboardLanguage: KeyboardLanguage get() = if (this == EN) KeyboardLanguage.EN else KeyboardLanguage.VI

    /** Giá trị ghi vào từng key (bảng §3; `en` = như `mixed`; `vi` = mặc định hiện tại). */
    val values: Map<String, Boolean>
        get() = if (this == VI) OnboardingSettings.DEFAULTS else OnboardingSettings.KEYS.associateWith { true }

    companion object {
        fun of(id: String?): OnboardingProfile? = entries.firstOrNull { it.id == id }
    }
}

object OnboardingSettings {
    /** Key hiện có (KHÔNG đổi tên) mà hồ sơ ghi vào — thứ tự như nhóm "Gõ mixed Việt/Anh". */
    val KEYS = listOf(Keys.AUTO_RESTORE, Keys.CONTEXTUAL_ENGLISH, Keys.RETRO_ENGLISH_AUTO, Keys.ENGLISH_BY_FREQUENCY,
        Keys.SPACE_SWIPE_LANGUAGE, Keys.SWIPE_ENGLISH)

    /** Mặc định khi chưa ghi — lấy từ [KeyboardSettings] để không lệch IME/app. */
    val DEFAULTS: Map<String, Boolean> = KeyboardSettings().let { d ->
        mapOf(Keys.AUTO_RESTORE to d.autoRestore, Keys.CONTEXTUAL_ENGLISH to d.contextualEnglish,
            Keys.RETRO_ENGLISH_AUTO to d.retroEnglishAuto, Keys.ENGLISH_BY_FREQUENCY to d.englishByFrequency,
            Keys.SPACE_SWIPE_LANGUAGE to d.spaceSwipeLanguage, Keys.SWIPE_ENGLISH to d.swipeEnglish)
    }

    /** Giá trị đang có (thiếu ⇒ mặc định). */
    fun current(read: (String) -> Boolean?): Map<String, Boolean> = KEYS.associateWith { read(it) ?: DEFAULTS.getValue(it) }

    /**
     * Hồ sơ khớp ĐÚNG cài đặt hiện tại; null = "Tuỳ chỉnh". `mixed` và `en` cùng bộ công tắc (chỉ khác
     * ngôn ngữ khởi đầu — trạng thái bàn phím) ⇒ tô `en` khi lần chọn gần nhất là `en`, còn lại `mixed`.
     */
    fun match(current: Map<String, Boolean>, lastChosen: OnboardingProfile?): OnboardingProfile? = when (current) {
        OnboardingProfile.VI.values -> OnboardingProfile.VI
        OnboardingProfile.MIXED.values -> if (lastChosen == OnboardingProfile.EN) OnboardingProfile.EN else OnboardingProfile.MIXED
        else -> null
    }

    /** Key sẽ bị đổi nếu áp [profile] (theo thứ tự [KEYS]). */
    fun changes(current: Map<String, Boolean>, profile: OnboardingProfile): List<String> =
        KEYS.filter { current[it] != profile.values[it] }

    /** Hỏi xác nhận khi đang "Tuỳ chỉnh" (không khớp hồ sơ nào) và áp sẽ đổi ít nhất một công tắc. */
    fun needsConfirmation(current: Map<String, Boolean>, profile: OnboardingProfile, lastChosen: OnboardingProfile?): Boolean =
        match(current, lastChosen) == null && changes(current, profile).isNotEmpty()

    /** Các giá trị cần ghi khi áp hồ sơ: §3 + onboardingProfile + yêu cầu ngôn ngữ khởi đầu. */
    fun writes(profile: OnboardingProfile, nowMs: Long): Map<String, Any> =
        profile.values + mapOf(OnboardingFlow.PROFILE_KEY to profile.id,
            KeyboardLanguageRequest.KEY to KeyboardLanguageRequest.encode(profile.keyboardLanguage, nowMs))

    /** Tên hiển thị (khoá dịch) của một key. */
    fun viTitle(key: String): String = when (key) {
        Keys.AUTO_RESTORE -> "Tự khôi phục từ tiếng Anh" // l10n-key
        Keys.CONTEXTUAL_ENGLISH -> "Quyết định theo ngữ cảnh" // l10n-key
        Keys.RETRO_ENGLISH_AUTO -> "Tự sửa từ phía trước" // l10n-key
        Keys.ENGLISH_BY_FREQUENCY -> "Đoán từ trùng theo tần suất" // l10n-key
        Keys.SPACE_SWIPE_LANGUAGE -> "Vuốt phím cách đổi Tiếng Việt / Tiếng Anh" // l10n-key
        Keys.SWIPE_ENGLISH -> "Vuốt từ tiếng Anh" // l10n-key
        else -> key
    }
}

object OnboardingFlow {
    const val DONE_KEY = "onboardingDone"
    const val PROFILE_KEY = "onboardingProfile"
    /** Thẻ một lần cho người dùng cũ (§5): true = còn chờ hiện; đóng/xem ⇒ false. */
    const val TIP_KEY = "mixedTypingTip"

    enum class Screen { CHOOSE, TRY_IT }

    /** Đã xong ⇒ không gì; chưa chọn hồ sơ ⇒ màn 1; đã chọn ⇒ màn 2 khi bàn phím đã bật. */
    fun screen(done: Boolean, profile: OnboardingProfile?, keyboardEnabled: Boolean): Screen? = when {
        done -> null
        profile == null -> Screen.CHOOSE
        keyboardEnabled -> Screen.TRY_IT
        else -> null
    }

    /** Key IME tự ghi khi chạy (không phải người dùng chỉnh) — không tính là "đã có cài đặt". */
    val KEYBOARD_RUNTIME_KEYS = setOf(Keys.PASTE_OFFERED_ID, Keys.AUTO_CORRECT_REJECTED, Keys.EMOJI_RECENTS)

    /** Key cài đặt người dùng: sao lưu + gõ tắt/mẫu câu. */
    val SETTING_KEYS: Set<String> = BackupSettings.all.map { it.key }.toSet() +
        setOf(Keys.SHORTCUTS, Keys.USER_TEMPLATES, Keys.KEYBOARD_THEME, Keys.FLOATING_KEYBOARD, Keys.ONE_HAND_MODE)

    /**
     * Lần đầu bản này chạy (chưa có [DONE_KEY]): đã có cài đặt cũ ⇒ người dùng cũ: xong onboarding + thẻ
     * một lần; chưa ⇒ người mới: ghi [DONE_KEY] = false tường minh (lần sau không đoán lại khi app/IME
     * đã ghi thêm key). Có [DONE_KEY] rồi ⇒ null.
     */
    fun upgradeWrites(existingKeys: Set<String>, settingKeys: Set<String> = SETTING_KEYS): Map<String, Boolean>? {
        if (DONE_KEY in existingKeys) return null
        val markers = settingKeys - KEYBOARD_RUNTIME_KEYS
        return if (existingKeys.none { it in markers }) mapOf(DONE_KEY to false) else mapOf(DONE_KEY to true, TIP_KEY to true)
    }
}

/**
 * Yêu cầu ngôn ngữ khởi đầu app → IME. Ngôn ngữ đang gõ là trạng thái RIÊNG của IME (prefs
 * "ime_state", process khác) ⇒ app ghi "en@<mốc>" vào prefs chung; IME lần mở ô kế tiếp thấy yêu cầu
 * MỚI (khác yêu cầu đã áp) thì đặt ngôn ngữ một lần, rồi người dùng vuốt phím cách đổi như thường.
 */
object KeyboardLanguageRequest {
    const val KEY = "keyboardLanguageRequest"
    /** IME (prefs riêng) nhớ yêu cầu đã áp. */
    const val APPLIED_KEY = "keyboardLanguageRequestApplied"

    fun encode(language: KeyboardLanguage, nowMs: Long): String = "${language.id}@$nowMs"

    /** Ngôn ngữ cần đặt nếu có yêu cầu chưa áp; null = không làm gì. */
    fun pending(request: String?, applied: String?): KeyboardLanguage? {
        if (request.isNullOrEmpty() || request == applied) return null
        val id = request.substringBefore('@')
        return KeyboardLanguage.entries.firstOrNull { it.id == id }
    }
}
