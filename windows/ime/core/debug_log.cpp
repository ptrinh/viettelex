#include "debug_log.h"

#include <cstdio>

namespace vtx {

std::string formatLogLine(const LogStamp& t, unsigned long pid, const std::string& exe, const char* component,
                          const std::string& msg) {
    char head[96];
    std::snprintf(head, sizeof head, "%04d-%02d-%02d %02d:%02d:%02d.%03d pid=%lu ", t.year, t.month, t.day, t.hour,
                  t.minute, t.second, t.millis, pid);
    std::string line = head;
    line += exe.empty() ? "?" : exe;
    line += " [";
    line += component ? component : "?";
    line += "] ";
    for (char c : msg) line.push_back(static_cast<unsigned char>(c) < 0x20 ? ' ' : c);
    line += "\r\n";
    return line;
}

}  // namespace vtx
