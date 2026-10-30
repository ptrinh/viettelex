package com.viettelex.telexcore

import org.junit.Assert.assertEquals
import org.junit.Test

// Twin of TelexCore InitialsSuffixTests.swift (issue #138): "PhuwowngTH" → PhươngTH.
// The golden corpus covers the full behaviour (⌫, reopen, flips); this pins the contract.
class InitialsSuffixTest {

    private val configs: List<TelexEngine.() -> Unit> = listOf(
        {},
        { liveSpellCheck = true },
        { liveSpellCheck = true; eagerEnglishRestore = true },
        { liveSpellCheck = true; freeMarking = true },
    )

    private fun type(keys: String, cfg: TelexEngine.() -> Unit): Pair<String, String> {
        val e = engineWith(cfg)
        for (ch in keys) e.feed(ch)
        val live = e.composed
        val peek = e.peekCommitText(true)
        val text = e.commitText(true)
        assertEquals("peek ≠ commit for $keys", peek, text)
        return live to text
    }

    @Test fun nameWithInitialsKeepsVietnamese() {
        val cases = listOf(
            "PhuwowngTH" to "PhươngTH", "KieenTV" to "KiênTV", "HungfNV" to "HùngNV",
            "LinhPTT" to "LinhPTT", "TraanfTH" to "TrầnTH", "DDinhNV" to "ĐinhNV",
            "HungfNVVV" to "HùngNVVV", "ThuyrNT" to "ThủyNT", "NgocjAT" to "NgọcAT",
            "KieenSV" to "KiênSV", "NguyeenXJ" to "NguyênXJ", "TuaanFR" to "TuânFR",
        )
        for (cfg in configs) for ((keys, want) in cases) {
            val (live, commit) = type(keys, cfg)
            assertEquals("live $keys", want, live)
            assertEquals("commit $keys", want, commit)
        }
    }

    @Test fun guardsStayAsBefore() {
        val same = listOf(
            "KieenS", "KieenX", "PhuwowngT", "SaaS", "OmS", "iOS", "macOS", "PhD", "McDonald",
            "JavaScript", "TypeScript", "GitHub", "MySQL", "NoSQL", "NodeJS", "DevOps",
            "AsJSON", "HasID", "VieeJt", "PhuwowngABCDE", "PhuwowngTHa",
        )
        for (cfg in configs) {
            for (w in same) assertEquals(w, w, type(w, cfg).second)
            assertEquals("VIỆT", type("VIEETJ", cfg).second)
            assertEquals("HĐND", type("HDDND", cfg).second)
        }
    }

    @Test fun backspaceAcrossTheSplit() {
        for (cfg in configs) {
            val e = engineWith(cfg)
            for (ch in "KieenSV") e.feed(ch)
            e.backspace()
            assertEquals(composeWith("KieenS", cfg), e.composed)
            e.feed('V')
            assertEquals("KiênSV", e.composed)
            assertEquals("LinhPTT", backspaceWith("LinhPTTx", 1, cfg))
            assertEquals("Hùng", backspaceWith("HungfNV", 2, cfg))
        }
    }

    @Test fun vniHead() {
        assertEquals("PhươngTH", commitWith("Phu7o7ngTH") { vniMode = true })
        assertEquals("HùngNV", commitWith("Hu2ngNV") { vniMode = true })
    }
}
