#include "app_language.h"

namespace vtx {

namespace {
std::string lower(std::string s) {
    for (char& c : s)
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    return s;
}
}  // namespace

bool AppLanguageStore::vietnamese(const std::string& app) const {
    auto it = map_.find(lower(app));
    return it == map_.end() || it->second;
}

void AppLanguageStore::set(const std::string& app, bool vietnamese) {
    if (!app.empty()) map_[lower(app)] = vietnamese;
}

std::string AppLanguageStore::serialize() const {
    std::string out;
    for (const auto& [k, v] : map_) out += k + '\t' + (v ? '1' : '0') + '\n';
    return out;
}

void AppLanguageStore::parse(const std::string& text) {
    map_.clear();
    size_t pos = 0;
    while (pos < text.size()) {
        size_t nl = text.find('\n', pos);
        std::string line = text.substr(pos, nl == std::string::npos ? std::string::npos : nl - pos);
        pos = nl == std::string::npos ? text.size() : nl + 1;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        const size_t tab = line.find('\t');
        if (tab == std::string::npos || tab == 0 || tab + 2 != line.size()) continue;
        const char v = line[tab + 1];
        if (v != '0' && v != '1') continue;
        set(line.substr(0, tab), v == '1');
    }
}

}  // namespace vtx
