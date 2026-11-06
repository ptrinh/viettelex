#!/bin/bash
# Đo thời gian hiện bàn phím bằng Macrobenchmark (docs/PERF-IME-SHOW.md) — chạy instrumentation
# thẳng bằng adb (không giữ Gradle chạy suốt phiên đo; app chủ không bị gỡ sau khi đo).
#
#   Scripts/ime-perf.sh [OUT_DIR] [TEST_FILTER] [ITERATIONS] [COMPILATION]
#     OUT_DIR      thư mục chép kết quả (mặc định build/ime-perf/<thời điểm>)
#     TEST_FILTER  vd com.viettelex.benchmark.ImeShowBenchmark#showCold (mặc định cả lớp ImeShowBenchmark)
#     ITERATIONS   số vòng mỗi test (mặc định 10)
#     COMPILATION  none | partial | full (mặc định none = mới cài, tệ nhất)
#
# Thiết bị: ANDROID_SERIAL nếu có nhiều máy. Cần build trước:
#   ./gradlew --max-workers=2 :app:assembleBenchmark :perfhost:assembleBenchmark :benchmark:assembleBenchmark
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-build/ime-perf/$(date +%Y%m%d-%H%M%S)}
FILTER=${2:-com.viettelex.benchmark.ImeShowBenchmark}
ITER=${3:-10}
COMP=${4:-none}
PKG=com.viettelex.benchmark
DEV_OUT=/sdcard/Android/media/$PKG/additional_test_output

adb install -r app/build/outputs/apk/benchmark/app-benchmark.apk >/dev/null
adb install -r perfhost/build/outputs/apk/benchmark/perfhost-benchmark.apk >/dev/null
adb install -r -t benchmark/build/outputs/apk/benchmark/benchmark-benchmark.apk >/dev/null
adb shell rm -rf "$DEV_OUT"
adb shell am instrument -w \
  -e class "$FILTER" \
  -e vt.iterations "$ITER" -e vt.compilation "$COMP" \
  -e androidx.benchmark.suppressErrors EMULATOR,LOW-BATTERY,UNLOCKED \
  -e additionalTestOutputDir "$DEV_OUT" \
  "$PKG/androidx.test.runner.AndroidJUnitRunner" | tail -5
mkdir -p "$OUT"
adb pull "$DEV_OUT/." "$OUT/" >/dev/null
python3 - "$OUT/$PKG-benchmarkData.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for b in d["benchmarks"]:
    print(b["name"])
    for k, v in sorted(b["metrics"].items()):
        print("  %-34s min %9.2f  median %9.2f  max %9.2f" % (k, v["minimum"], v["median"], v["maximum"]))
    for k, v in sorted(b.get("sampledMetrics", {}).items()):
        print("  %-34s P50 %9.2f  P90 %9.2f  P99 %9.2f" % (k, v["P50"], v["P90"], v["P99"]))
PY
echo "Kết quả: $OUT"
