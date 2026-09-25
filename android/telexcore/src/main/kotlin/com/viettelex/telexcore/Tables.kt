// Port of TelexCore/Tables.swift. Static lookup tables, built once; the hot path
// reads flat arrays only (no maps, no boxing).
package com.viettelex.telexcore

/** Diacritic mark carried by a base letter (Swift `Mark`, raw values kept). */
internal object Mark {
    const val NONE = 0
    const val CIRCUMFLEX = 1 // â ê ô
    const val BREVE = 2      // ă
    const val HORN = 3       // ơ ư
    const val BAR = 4        // đ
}

/** Tone raw values (Swift `Tone.rawValue`), used internally as plain Ints. */
internal object T {
    const val NONE = 0
    const val ACUTE = 1
    const val GRAVE = 2
    const val HOOK = 3
    const val TILDE = 4
    const val DOT = 5
}

internal object Tables {
    private val tonedGroups = arrayOf(
        "aáàảãạ", "ăắằẳẵặ", "âấầẩẫậ", "eéèẻẽẹ", "êếềểễệ", "iíìỉĩị",
        "oóòỏõọ", "ôốồổỗộ", "ơớờởỡợ", "uúùủũụ", "ưứừửữự", "yýỳỷỹỵ",
        "AÁÀẢÃẠ", "ĂẮẰẲẴẶ", "ÂẤẦẨẪẬ", "EÉÈẺẼẸ", "ÊẾỀỂỄỆ", "IÍÌỈĨỊ",
        "OÓÒỎÕỌ", "ÔỐỒỔỖỘ", "ƠỚỜỞỠỢ", "UÚÙỦŨỤ", "ƯỨỪỬỮỰ", "YÝỲỶỸỴ",
    )

    // toneless scalar (< 0x200) -> row into tonedForms (row*6 + tone), -1 = not a vowel.
    private const val TONELESS_LIMIT = 0x200
    private val tonedRow = IntArray(TONELESS_LIMIT) { -1 }
    private val tonedForms = IntArray(tonedGroups.size * 6)

    // toned scalar (< 0x2000) -> (base << 3) | tone, -1 = not in the table.
    private const val DETONE_LIMIT = 0x2000
    private val detone = IntArray(DETONE_LIMIT) { -1 }

    init {
        for ((row, g) in tonedGroups.withIndex()) {
            val base = g[0].code
            tonedRow[base] = row
            for (i in 0 until 6) {
                val s = g[i].code
                tonedForms[row * 6 + i] = s
                detone[s] = (base shl 3) or i
            }
        }
    }

    /** Detone: returns (base << 3) | tone, or -1 when `scalar` is not a (toned) vowel. */
    fun detone(scalar: Int): Int = if (scalar in 0 until DETONE_LIMIT) detone[scalar] else -1

    /** Compose a lowercase ascii base + mark into a toneless scalar. */
    fun markedScalar(base: Int, mark: Int, upper: Boolean): Int {
        if (mark != Mark.NONE) {
            when (base) {
                'a'.code -> if (mark == Mark.CIRCUMFLEX) return if (upper) 'Â'.code else 'â'.code
                    else if (mark == Mark.BREVE) return if (upper) 'Ă'.code else 'ă'.code
                'e'.code -> if (mark == Mark.CIRCUMFLEX) return if (upper) 'Ê'.code else 'ê'.code
                'o'.code -> if (mark == Mark.CIRCUMFLEX) return if (upper) 'Ô'.code else 'ô'.code
                    else if (mark == Mark.HORN) return if (upper) 'Ơ'.code else 'ơ'.code
                'u'.code -> if (mark == Mark.HORN) return if (upper) 'Ư'.code else 'ư'.code
                'd'.code -> if (mark == Mark.BAR) return if (upper) 'Đ'.code else 'đ'.code
            }
        }
        return if (upper) (base - 32) and 0xFF else base
    }

    /** Apply a tone to a toneless (possibly marked) vowel scalar. */
    fun applyTone(scalar: Int, tone: Int): Int {
        if (tone == T.NONE) return scalar
        if (scalar < 0 || scalar >= TONELESS_LIMIT) return scalar
        val row = tonedRow[scalar]
        if (row < 0) return scalar
        return tonedForms[row * 6 + tone]
    }

    // MARK: - Letter classes (0-25 = a-z; 26-32 = â ă ê ô ơ ư đ)

    const val CLASS_COUNT = 33

    /** Class of an engine letter (lowercase ascii base + mark), wrapped to a byte like Swift's `&-`. */
    fun letterClass(base: Int, mark: Int): Int {
        if (mark != Mark.NONE) {
            when (base) {
                'a'.code -> if (mark == Mark.CIRCUMFLEX) return 26 else if (mark == Mark.BREVE) return 27
                'e'.code -> if (mark == Mark.CIRCUMFLEX) return 28
                'o'.code -> if (mark == Mark.CIRCUMFLEX) return 29 else if (mark == Mark.HORN) return 30
                'u'.code -> if (mark == Mark.HORN) return 31
                'd'.code -> if (mark == Mark.BAR) return 32
            }
        }
        return (base - 'a'.code) and 0xFF
    }

    /** Character → class (lowercase toneless letters only), -1 = unmappable. */
    fun charClass(c: Char): Int {
        if (c in 'a'..'z') return c - 'a'
        return when (c) {
            'â' -> 26; 'ă' -> 27; 'ê' -> 28; 'ô' -> 29; 'ơ' -> 30; 'ư' -> 31; 'đ' -> 32
            else -> -1
        }
    }

    private val vowelClassMask: Long = run {
        var m = 0L
        for (ch in "aeiouyâăêôơư") m = m or (1L shl charClass(ch))
        m
    }

    /** Swift's smart shift yields 0 for a shift ≥ 64 — Kotlin's `shr` wraps, so guard. */
    fun isVowelClass(c: Int): Boolean = c in 0..63 && ((vowelClassMask ushr c) and 1L) == 1L
}

private const val ASCII_VOWEL_MASK = (1 shl 0) or (1 shl 4) or (1 shl 8) or (1 shl 14) or (1 shl 20) or (1 shl 24)

internal fun isVowelAscii(c: Int): Boolean {
    val i = (c - 'a'.code) and 0xFF
    return i < 26 && ((ASCII_VOWEL_MASK ushr i) and 1) == 1
}

/** Tone key → tone raw value, or -1. */
internal fun toneForKey(c: Int): Int = when (c) {
    's'.code -> T.ACUTE
    'f'.code -> T.GRAVE
    'r'.code -> T.HOOK
    'x'.code -> T.TILDE
    'j'.code -> T.DOT
    else -> -1
}

internal fun isLetter(c: Int): Boolean = (c in 'a'.code..'z'.code) || (c in 'A'.code..'Z'.code)
internal fun isDigit(c: Int): Boolean = c in '0'.code..'9'.code
internal fun isUpperAscii(c: Int): Boolean = c in 'A'.code..'Z'.code
internal fun lowercased(c: Int): Int = if (isUpperAscii(c)) c + 32 else c
