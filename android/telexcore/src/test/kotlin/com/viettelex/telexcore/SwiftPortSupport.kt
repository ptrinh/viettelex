package com.viettelex.telexcore

// Kotlin twins of the private helpers in the Swift XCTests (see port-swift-tests.py).

internal fun engineWith(cfg: TelexEngine.() -> Unit): TelexEngine = TelexEngine().apply(cfg)

internal fun composeWith(keys: String, cfg: TelexEngine.() -> Unit): String {
    val e = engineWith(cfg)
    for (ch in keys) e.feed(ch)
    return e.composed
}

internal fun commitWith(keys: String, autoRestore: Boolean = true, cfg: TelexEngine.() -> Unit): String {
    val e = engineWith(cfg)
    for (ch in keys) e.feed(ch)
    return e.commitText(autoRestore)
}

internal fun backspaceWith(keys: String, n: Int, cfg: TelexEngine.() -> Unit): String {
    val e = engineWith(cfg)
    for (ch in keys) e.feed(ch)
    repeat(n) { e.backspace() }
    return e.composed
}

/** ContextEnglishTests.sentence: commit at each space; final word if any (or empty input). */
internal fun sentenceCtx(s: String, cfg: TelexEngine.() -> Unit): String {
    val e = engineWith(cfg)
    val words = ArrayList<String>()
    var wroteCurrent = false
    for (ch in s) {
        if (ch == ' ') { words.add(e.commitText(true)); wroteCurrent = false } else { e.feed(ch); wroteCurrent = true }
    }
    if (wroteCurrent || words.isEmpty()) words.add(e.commitText(true))
    return words.joinToString(" ")
}

/** CollisionPreferenceTests.sentence: split on spaces (omitting empties), commit each word. */
internal fun sentenceSplit(text: String, cfg: TelexEngine.() -> Unit): String {
    val e = engineWith(cfg)
    val out = ArrayList<String>()
    for (word in text.split(' ').filter { it.isNotEmpty() }) {
        for (ch in word) e.feed(ch)
        out.add(e.commitText(true))
    }
    return out.joinToString(" ")
}

/** TeencodeToggleTests.commit: commit at each space and once more at the end. */
internal fun sentenceToggle(keys: String, cfg: TelexEngine.() -> Unit): String {
    val e = engineWith(cfg)
    val out = ArrayList<String>()
    for (ch in keys) if (ch == ' ') out.add(e.commitText(true)) else e.feed(ch)
    out.add(e.commitText(true))
    return out.joinToString(" ")
}
