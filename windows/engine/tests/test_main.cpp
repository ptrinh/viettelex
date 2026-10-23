#include <cstdio>
#include <cstring>

int runGolden(const char* path);
int runPorted();
int runUnit();
int runRetro(const char* fixture);

int main(int argc, char** argv) {
    if (argc >= 3 && std::strcmp(argv[1], "golden") == 0) return runGolden(argv[2]);
    if (argc >= 2 && std::strcmp(argv[1], "unit") == 0) {
        int a = runPorted();
        int b = runUnit();
        return a || b;
    }
    if (argc >= 3 && std::strcmp(argv[1], "retro") == 0) return runRetro(argv[2]);
    std::fprintf(stderr, "usage: vtx_tests golden <golden.tsv[.gz]> | unit | retro <retro-english-eval.txt>\n");
    return 2;
}
