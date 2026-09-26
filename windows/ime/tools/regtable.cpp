// regtable — turns vtx::reg::tipRegistryEntries() (the data DllRegisterServer registers)
// into MSI Registry-table rows, and checks a built MSI against it.
//
//   regtable sql   <component> <dllPathFmt> <iconPathFmt>   -> one MSI SQL INSERT per line
//   regtable rows  <component> <dllPathFmt> <iconPathFmt>   -> expected rows (TSV)
//   regtable check <Registry.idt> <component> <dllPathFmt> <iconPathFmt>
//        compares the rows of <component> in `msiinfo export <msi> Registry` output with
//        the expected rows; exit 1 and a diff on any difference (missing, extra, changed).
//
// Row encoding (MSI Registry table): Root 2 = HKLM; DWORD -> "#<decimal>"; a string
// starting with '#' -> "##..."; a key with no values -> Name "*" (create on install,
// remove on uninstall), Value empty. The registry view (64/32-bit) comes from the
// component's msidbComponentAttributes64bit bit, set in the .wxs.
#include <cstdio>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#include "registration.h"

namespace {

struct Row {
    std::string key, name, value, component;
    bool operator<(const Row& o) const {
        if (key != o.key) return key < o.key;
        if (name != o.name) return name < o.name;
        if (value != o.value) return value < o.value;
        return component < o.component;
    }
};

std::vector<Row> expected(const std::string& comp, const std::string& dll, const std::string& icon) {
    std::vector<Row> rows;
    for (const auto& e : vtx::reg::tipRegistryEntries(dll, icon)) {
        Row r{e.key, e.name, "", comp};
        switch (e.type) {
            case vtx::reg::ValueType::Key: r.name = "*"; break;
            case vtx::reg::ValueType::Dword: r.value = "#" + std::to_string(e.dword); break;
            case vtx::reg::ValueType::Sz: r.value = (!e.sz.empty() && e.sz[0] == '#') ? "#" + e.sz : e.sz; break;
        }
        rows.push_back(r);
    }
    return rows;
}

std::vector<std::string> split(const std::string& s, char sep) {
    std::vector<std::string> out;
    std::string cur;
    for (char c : s) {
        if (c == sep) { out.push_back(cur); cur.clear(); }
        else if (c != '\r') cur.push_back(c);
    }
    out.push_back(cur);
    return out;
}

int usage() {
    std::fprintf(stderr, "usage: regtable sql|rows <component> <dllPathFmt> <iconPathFmt>\n"
                         "       regtable check <Registry.idt> <component> <dllPathFmt> <iconPathFmt>\n");
    return 2;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) return usage();
    const std::string cmd = argv[1];
    if ((cmd == "sql" || cmd == "rows") && argc == 5) {
        const auto rows = expected(argv[2], argv[3], argv[4]);
        int n = 0;
        for (const Row& r : rows) {
            if (cmd == "rows") {
                std::printf("2\t%s\t%s\t%s\t%s\n", r.key.c_str(), r.name.c_str(), r.value.c_str(), r.component.c_str());
            } else {
                for (const std::string* f : {&r.key, &r.name, &r.value})
                    if (f->find('\'') != std::string::npos) { std::fprintf(stderr, "quote in value\n"); return 1; }
                std::printf("INSERT INTO `Registry` (`Registry`,`Root`,`Key`,`Name`,`Value`,`Component_`) "
                            "VALUES ('vtx_%s_%02d',2,'%s','%s','%s','%s')\n",
                            r.component.c_str(), n++, r.key.c_str(), r.name.c_str(), r.value.c_str(),
                            r.component.c_str());
            }
        }
        return 0;
    }
    if (cmd == "check" && argc == 6) {
        std::ifstream in(argv[2], std::ios::binary);
        if (!in) { std::fprintf(stderr, "cannot read %s\n", argv[2]); return 2; }
        const std::string comp = argv[3];
        std::map<Row, int> have, want;
        std::string line;
        int lineNo = 0;
        while (std::getline(in, line)) {
            if (++lineNo <= 3) continue;  // column names, types, table name
            auto f = split(line, '\t');
            if (f.size() != 6 || f[5] != comp) continue;
            if (f[1] != "2") { std::fprintf(stderr, "row %s: root %s is not HKLM\n", f[0].c_str(), f[1].c_str()); return 1; }
            ++have[Row{f[2], f[3], f[4], f[5]}];
        }
        for (const Row& r : expected(comp, argv[4], argv[5])) ++want[r];
        int bad = 0;
        for (const auto& kv : want)
            if (have[kv.first] != kv.second) {
                std::fprintf(stderr, "MISSING %s | %s | %s\n", kv.first.key.c_str(), kv.first.name.c_str(), kv.first.value.c_str());
                ++bad;
            }
        for (const auto& kv : have)
            if (kv.second && want[kv.first] != kv.second) {
                std::fprintf(stderr, "EXTRA   %s | %s | %s\n", kv.first.key.c_str(), kv.first.name.c_str(), kv.first.value.c_str());
                ++bad;
            }
        if (bad) return 1;
        std::printf("registry rows of %s match DllRegisterServer data (%zu rows)\n", comp.c_str(), want.size());
        return 0;
    }
    return usage();
}
