#include "breaker.h"
#include "test.h"
#include "update_check.h"

using namespace vtx;

TEST(version_compare) {
    CHECK(compareVersions("0.10.0", "0.9.3") > 0);
    CHECK(compareVersions("1.0", "1.0.0") == 0);
    CHECK(compareVersions("1.0.1", "1.0") > 0);
    CHECK(compareVersions("0.1.0", "0.1.0.1") < 0);
    CHECK(isNewer("0.2.0", "0.1.9"));
    CHECK(!isNewer("0.1.0", "0.1.0"));
}

TEST(stable_json_windows_object) {
    const char* j = R"({
      "version": "1.7.12",
      "url": "https://github.com/ptrinh/viettelex/releases/tag/v1.7.12",
      "build": 108,
      "windows": { "version": "0.2.0",
                   "x64": "https://github.com/ptrinh/viettelex/releases/download/win-v0.2.0/VietTelex-0.2.0-x64.msi",
                   "arm64": "https://github.com/ptrinh/viettelex/releases/download/win-v0.2.0/VietTelex-0.2.0-arm64.msi",
                   "notes": "https://github.com/ptrinh/viettelex/releases/tag/win-v0.2.0" }
    })";
    WindowsRelease r;
    CHECK(parseStableJson(j, r));
    CHECK_EQ(r.version, std::string("0.2.0"));
    CHECK(isTrustedDownloadUrl(r.x64));
    CHECK(isTrustedDownloadUrl(r.arm64));
}

TEST(stable_json_without_windows_is_no_update) {
    WindowsRelease r;
    CHECK(!parseStableJson(R"({"version":"1.7.12","url":"x","build":108})", r));
    CHECK(!parseStableJson(R"({"windows": {"x64":"a"}})", r));
    CHECK(!parseStableJson("garbage", r));
    // "windows" appearing inside a string value is not the key.
    CHECK(!parseStableJson(R"({"url":"\"windows\" soon"})", r));
}

TEST(download_url_allowlist) {
    CHECK(!isTrustedDownloadUrl("http://github.com/ptrinh/viettelex/releases/download/a.msi"));
    CHECK(!isTrustedDownloadUrl("https://evil.example/VietTelex.msi"));
    CHECK(!isTrustedDownloadUrl("https://github.com/ptrinh/viettelex/releases/download/../../x"));
    CHECK(!isTrustedDownloadUrl("https://viettelex.com.evil.example/a.msi"));
}

TEST(rate_breaker_trips_and_recovers) {
    RateBreaker b(10, 100, 1000);
    CHECK(b.allow(0, 5));
    CHECK(b.allow(10, 5));
    CHECK(!b.allow(20, 1));    // 11 > 10 inside the window
    CHECK(b.tripped(500));
    CHECK(!b.allow(900, 1));
    CHECK(b.allow(1100, 1));   // cooldown over
    CHECK_EQ(b.trips(), 1u);
    CHECK(b.allow(1300, 10));  // new window
}
