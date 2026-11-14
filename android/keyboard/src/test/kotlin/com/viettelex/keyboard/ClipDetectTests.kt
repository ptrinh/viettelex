package com.viettelex.keyboard

import com.viettelex.keyboard.ClipChip.Kind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Chip tách số — vector dùng chung với iOS ClipDetectTests.swift. */
class ClipDetectTests {
    private fun d(s: String) = ClipDetect.detect(s).map { it.kind to it.value }

    @Test fun bankSmsAccountOnly() {
        assertEquals(listOf(Kind.ACCOUNT to "1234567890"),
            d("Vietcombank: TK 1234567890 +500,000VND luc 12:30 27/09/2026. SD 1,234,567VND. ND: chuyen tien"))
    }

    @Test fun otpMessages() {
        assertEquals(listOf(Kind.OTP to "482913"), d("Ma OTP cua quy khach la 482913. Khong chia se ma nay"))
        assertEquals(listOf(Kind.OTP to "5821"), d("Your verification code is 5821"))
        assertEquals(listOf(Kind.OTP to "651305"), d("The temporary code you requested to sign-in is 651305. Please don't share this code with anyone."))
        assertEquals(listOf(Kind.OTP to "123123"), d("123123 là OTP là bạn"))   // mã đứng TRƯỚC từ khoá
        assertEquals(listOf(Kind.OTP to "123456"), d("123456"))
        assertEquals(listOf(Kind.OTP to "908172"), d("Mã xác thực (OTP) của bạn là 908172, hiệu lực trong 5 phút."))
        assertEquals(listOf(Kind.OTP to "7731"), d("Mã: 7731"))
        assertEquals(listOf(Kind.OTP to "55120374"), d("[MB Bank] Ma giao dich cua Quy khach: 55120374. Tuyet doi KHONG cung cap"))
    }

    @Test fun phones() {
        assertEquals(listOf(Kind.PHONE to "0912345678"), d("0912 345 678"))
        assertEquals(listOf(Kind.PHONE to "0912345678"), d("+84 912 345 678"))
        assertEquals(listOf(Kind.PHONE to "0987654321"), d("Goi 0987.654.321 de duoc ho tro"))
        assertEquals(listOf(Kind.PHONE to "0356789012"), d("SĐT: 0356-789-012"))
        assertEquals(listOf(Kind.PHONE to "02838234567"), d("028 3823 4567"))
        assertEquals(listOf(Kind.PHONE to "0912345678"), d("84912345678"))
    }

    @Test fun accounts() {
        assertEquals(listOf(Kind.ACCOUNT to "0071000123456"), d("STK: 0071 0001 23456 Vietcombank"))
        assertEquals(listOf(Kind.ACCOUNT to "19036789012345"), d("Số tài khoản 19036789012345 Techcombank - Nguyen Van A"))
        assertEquals(listOf(Kind.ACCOUNT to "0123456789"), d("0123456789"))
        assertEquals(listOf(Kind.ACCOUNT to "1903678901"), d("1903-6789-01"))
        assertEquals(listOf(Kind.ACCOUNT to "123456"), d("stk 123456 acb"))       // có keyword ⇒ 6 số được
        assertEquals(listOf(Kind.ACCOUNT to "9704229212345678"), d("the 9704 2292 1234 5678 het han 12/28"))
    }

    @Test fun mixedPhoneAndAccount() {
        assertEquals(listOf(Kind.PHONE to "0912345678", Kind.ACCOUNT to "1903456789012"),
            d("Chuyen khoan STK 1903456789012 Techcombank, lien he 0912345678"))
    }

    /** Vector bổ sung khớp iOS. */
    @Test fun sharedVectorsWithIOS() {
        assertEquals(listOf(Kind.OTP to "739104"), d("Mã xác thực giao dịch của Quý khách là 739104, hiệu lực 3 phút."))
        assertEquals(listOf(Kind.OTP to "5521"), d("MB: Ma xac nhan 5521 de dang nhap. Het han sau 60s"))
        assertEquals(listOf(Kind.OTP to "438210"), d("G-438210 is your Google verification code."))
        assertEquals(listOf(Kind.ACCOUNT to "01234567890"),
            d("TPBank: TK 0123 4567 890 giảm 150.000 VND lúc 08:15 26/09. Số dư 2.345.000 VND"))
        assertEquals(listOf(Kind.PHONE to "0987654321"), d("Liên hệ anh Nam 0987.654.321 nhé"))
        assertEquals(listOf(Kind.PHONE to "0901234567"), d("SĐT: 090-123-4567"))
        assertEquals(listOf(Kind.ACCOUNT to "123456"), d("Chuyển khoản vào tk 123456 MB giúp em"))
        assertEquals(listOf(Kind.PHONE to "0912345678", Kind.ACCOUNT to "19036789012345"),
            d("STK 1903 6789 0123 45, SĐT 0912345678 (chị Lan)"))
        assertEquals(listOf(Kind.PHONE to "0912345678"), d("0912 345 678 99"))
        assertEquals(listOf(Kind.PHONE to "0912345678"), d("+84 0912 345 678"))
        assertEquals(emptyList<Any>(), d("Giá 1,250,000 VND"))
        assertEquals(emptyList<Any>(), d("Năm 2026 có 365 ngày"))
        assertEquals(emptyList<Any>(), d("Không chia sẻ mã này cho ai"))
    }

    @Test fun nothing() {
        assertEquals(emptyList<Any>(), d("Chuyển 500000 đ"))
        assertEquals(emptyList<Any>(), d("hẹn 12:30 ngày 27/09"))
        assertEquals(emptyList<Any>(), d("abc"))
        assertEquals(emptyList<Any>(), d("Mã giao dịch: thanh toán 50000 VND thành công")) // số tiền ≠ OTP
        assertEquals(emptyList<Any>(), d(""))
        assertEquals(emptyList<Any>(), d("Số dư 1,234,567 VND"))
        assertEquals(emptyList<Any>(), d("Tổng 250000 VND"))
        assertEquals(emptyList<Any>(), d("TK x1234 da tru tien"))
        assertEquals(emptyList<Any>(), d("năm 2026"))
        assertEquals(emptyList<Any>(), d("a".repeat(501) + " 0912345678"))
    }

    /** Địa chỉ — feedback 15/11/2026; vector khớp iOS testShippingInfoAddress. */
    @Test fun shippingInfoAddress() {
        assertEquals(listOf(Kind.PHONE to "0976543210", Kind.ADDRESS to "458 Lê Văn Sỹ, P.14, Q.3, TP.HCM"),
            d("Nguyễn Văn A, 0976.543.210, 458 Lê Văn Sỹ, P.14, Q.3, TP.HCM"))
        assertEquals(listOf(Kind.PHONE to "0912345678", Kind.ADDRESS to "12/3A Nguyễn Trãi, Phường Bến Thành, Quận 1, TP Hồ Chí Minh"),
            d("Tên: Trần Thị B\nSĐT: 0912345678\nĐịa chỉ: 12/3A Nguyễn Trãi, Phường Bến Thành, Quận 1, TP Hồ Chí Minh"))
        assertEquals(listOf(Kind.PHONE to "0987654321", Kind.ADDRESS to "Số 5 ngõ 10 Láng Hạ, Đống Đa, Hà Nội"),
            d("Chị Lan 0987654321\nSố 5 ngõ 10 Láng Hạ, Đống Đa, Hà Nội"))
        assertEquals(listOf(Kind.PHONE to "0356789012", Kind.ADDRESS to "xóm 3, xã Tân Lập, huyện Đan Phượng, Hà Nội"),
            d("xóm 3, xã Tân Lập, huyện Đan Phượng, Hà Nội - 0356789012"))
        assertEquals(listOf(Kind.ADDRESS to "25 Trần Phú, Hải Châu, Đà Nẵng"), d("ship giúp e về 25 Trần Phú, Hải Châu, Đà Nẵng nhé"))
        assertEquals(listOf(Kind.ADDRESS to "thôn Đông, xã Yên Phú, Ý Yên, Nam Định"), d("Đ/c: thôn Đông, xã Yên Phú, Ý Yên, Nam Định"))
        assertEquals(listOf(Kind.ADDRESS to "123 Lê Lợi, Phường 7, Quận Gò Vấp, TPHCM"),
            d("Địa chỉ:\n123 Lê Lợi\nPhường 7, Quận Gò Vấp\nTPHCM"))
        assertEquals(listOf(Kind.ADDRESS to "Lô B2, KDC Hồng Loan, P. Hưng Thạnh, Q. Cái Răng, Cần Thơ"),
            d("Lô B2, KDC Hồng Loan, P. Hưng Thạnh, Q. Cái Răng, Cần Thơ"))
        assertEquals(listOf(Kind.ADDRESS to "458 Lê Văn Sỹ Q3"), d("Ghi chú: giao giờ hành chính, 458 Lê Văn Sỹ Q3"))
    }

    @Test fun noAddress() {
        assertEquals(emptyList<Any>(), d("Phở Hà Nội ngon lắm"))
        assertEquals(emptyList<Any>(), d("Hẹn 8h30 ở Quận 1 nhé"))
        assertEquals(emptyList<Any>(), d("quán phở bò ngon"))
        assertEquals(emptyList<Any>(), d("2 cái áo size M"))
    }

    @Test fun prioritizeByField() {
        val c = ClipDetect.detect("Nguyễn Văn A, 0976543210, 458 Lê Văn Sỹ, P.14, Q.3, TP.HCM")
        assertEquals(listOf(Kind.ADDRESS, Kind.PHONE), ClipDetect.prioritize(c, Kind.ADDRESS).map { it.kind })
        assertEquals(listOf(Kind.PHONE, Kind.ADDRESS), ClipDetect.prioritize(c, Kind.PHONE).map { it.kind })
        assertEquals(listOf(Kind.PHONE, Kind.ADDRESS), ClipDetect.prioritize(c, null).map { it.kind })
        assertEquals("Dán địa chỉ", ClipDetect.detect("458 Lê Văn Sỹ, Q.3").single().label)
    }

    @Test fun labels() {
        assertEquals("Dán STK 0071…", ClipDetect.detect("STK: 0071 0001 23456 Vietcombank").single().label)
        assertEquals("Dán SĐT 0912…", ClipDetect.detect("0912345678").single().label)
        assertEquals("Dán OTP 482913", ClipDetect.detect("482913").single().label)
        assertEquals("Dán STK 123456", ClipDetect.detect("stk 123456").single().label)
    }

    @Test fun sensitivity() {
        assertTrue(ClipSensitivity.looksSecret("Xk9#mP2qL"))
        assertTrue(ClipSensitivity.looksSecret("sk_live_4eC39HqLyjWDarjtT1zdp7dc"))
        assertTrue(ClipSensitivity.looksSecret("482913"))
        assertTrue(ClipSensitivity.looksSecret("Ma OTP cua quy khach la 482913"))
        assertFalse(ClipSensitivity.looksSecret("https://example.com/a1b2c3d4e5f6g7h8"))
        assertFalse(ClipSensitivity.looksSecret("phuc.nguyen2@gmail.com"))
        assertFalse(ClipSensitivity.looksSecret("xin chao ban"))
        assertFalse(ClipSensitivity.looksSecret("1234567890123"))
        assertFalse(ClipSensitivity.looksSecret("Nguyễn"))
    }
}

/** Dịch bằng Gemini Nano (thử nghiệm): kiểm kết quả trước khi ghi vào ô. */
class AITranslateTests {
    private val viEn = TranslateDirection.Plan("vi", "en")
    private val enVi = TranslateDirection.Plan("en", "vi")
    private val viJa = TranslateDirection.Plan("vi", "ja")

    @Test fun acceptsGoodTranslations() {
        assertEquals("It's raining cats and dogs", AITranslate.validate("It's raining cats and dogs", "Mưa như trút nước", viEn))
        assertEquals("Trời mưa như trút nước", AITranslate.validate("Trời mưa như trút nước", "It's raining cats and dogs", enVi))
        assertEquals("ありがとう", AITranslate.validate("ありがとう", "Cảm ơn", viJa))
        assertEquals("Hello", AITranslate.validate("Translation:\nHello", "Xin chào", viEn))   // bỏ lời dẫn
        assertEquals("Hello", AITranslate.validate("\"Hello\"", "Xin chào", viEn))           // bỏ ngoặc bao
        assertEquals("Line one\nLine two", AITranslate.validate("Line one\nLine two", "Dòng một\nDòng hai", viEn))
    }

    @Test fun rejectsSuspiciousOutput() {
        assertNull(AITranslate.validate("", "Xin chào", viEn))
        assertNull(AITranslate.validate("Xin chào bạn", "Xin chào bạn", viEn))                // chưa dịch
        assertNull(AITranslate.validate("Hello", "Hello", enVi))                              // không thành tiếng Việt
        assertNull(AITranslate.validate("Hello", "Xin chào", viJa))                           // sai chữ viết
        assertNull(AITranslate.validate("Line one and two", "Dòng một\nDòng hai", viEn))      // mất dòng
        assertNull(AITranslate.validate("Hi. ".repeat(40), "Chào", viEn))                     // dài bất thường
    }

    @Test fun promptNamesLanguages() {
        val p = AITranslate.prompt("Xin chào", viEn)
        assertTrue(p.contains("from Vietnamese to English"))
        assertTrue(p.endsWith("Xin chào"))
    }
}
