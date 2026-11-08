#include "debug_log.h"

#include <cstdio>

namespace vtx {

namespace {

void appendClean(std::string& line, const std::string& msg) {
    for (char c : msg) line.push_back(static_cast<unsigned char>(c) < 0x20 ? ' ' : c);
}

std::string prefix(const LogStamp& t, unsigned long pid, const std::string& exe, const char* component) {
    char head[48];
    std::snprintf(head, sizeof head, "%02d:%02d:%02d.%03d %lu ", t.hour, t.minute, t.second, t.millis, pid);
    std::string line = head;
    line += exe.empty() ? "?" : exe;
    line += " [";
    line += component ? component : "?";
    line += "] ";
    return line;
}

}  // namespace

std::string formatLogLine(const LogStamp& t, unsigned long pid, const std::string& exe, const char* component,
                          const std::string& msg) {
    std::string line = prefix(t, pid, exe, component);
    appendClean(line, msg);
    line += "\r\n";
    return line;
}

std::string formatDayLine(const LogStamp& t) {
    char buf[32];
    std::snprintf(buf, sizeof buf, "=== %04d-%02d-%02d ===\r\n", t.year, t.month, t.day);
    return buf;
}

std::string formatRepeatLine(const LogStamp& now, const LogStamp& last, unsigned long pid, const std::string& exe,
                             const char* component, unsigned count) {
    char tail[64];
    std::snprintf(tail, sizeof tail, "^ repeated %ux more until %02d:%02d:%02d.%03d\r\n", count, last.hour,
                  last.minute, last.second, last.millis);
    return prefix(now, pid, exe, component) + tail;
}

bool logNeedsDayLine(uint64_t size, const LogStamp& lastWrite, const LogStamp& now) {
    return size == 0 || lastWrite.year != now.year || lastWrite.month != now.month || lastWrite.day != now.day;
}

std::string LogCollapser::offer(const LogStamp& t, uint64_t nowMs, unsigned long pid, const std::string& exe,
                                const char* component, const std::string& msg) {
    std::string key = component ? component : "?";
    key.push_back('\0');
    key += msg;
    if (key == key_ && nowMs >= lastMs_ && nowMs - lastMs_ <= kDebugLogRepeatWindowMs) {
        ++repeats_;
        lastStamp_ = t;
        lastMs_ = nowMs;
        return std::string();
    }
    std::string out = drain(t, pid, exe);
    out += formatLogLine(t, pid, exe, component, msg);
    key_ = std::move(key);
    component_ = component ? component : "?";
    lastStamp_ = t;
    lastMs_ = nowMs;
    return out;
}

std::string LogCollapser::drain(const LogStamp& now, unsigned long pid, const std::string& exe) {
    if (repeats_ == 0) return std::string();
    std::string line = formatRepeatLine(now, lastStamp_, pid, exe, component_.c_str(), repeats_);
    repeats_ = 0;
    return line;
}

bool LogChangeGate::changed(const std::string& key, const std::string& value) {
    auto it = last_.find(key);
    if (it != last_.end()) {
        if (it->second == value) return false;
        it->second = value;
        return true;
    }
    if (last_.size() >= cap_) last_.clear();
    last_.emplace(key, value);
    return true;
}

}  // namespace vtx
