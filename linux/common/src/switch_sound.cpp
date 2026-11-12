#include "viettelex/switch_sound.h"

#include <cmath>
#include <cstdlib>
#include <fcntl.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "viettelex/settings.h"

extern char **environ;

namespace viettelex {

std::vector<uint8_t> switchSoundWav(bool vietnamese) {
    const int perNote = kSwitchSoundRate * kSwitchSoundNoteMs / 1000;
    const int lead = kSwitchSoundRate * kSwitchSoundLeadMs / 1000;
    const int gap = kSwitchSoundRate * kSwitchSoundGapMs / 1000;
    const double notes[2] = {vietnamese ? kSwitchSoundLowHz : kSwitchSoundHighHz,
                             vietnamese ? kSwitchSoundHighHz : kSwitchSoundLowHz};
    std::vector<uint8_t> w;
    const uint32_t dataBytes = static_cast<uint32_t>(lead + perNote + gap + perNote) * 2;
    w.reserve(44 + dataBytes);
    auto u16 = [&w](uint32_t v) {
        w.push_back(static_cast<uint8_t>(v & 0xFF));
        w.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
    };
    auto u32 = [&u16](uint32_t v) {
        u16(v & 0xFFFF);
        u16(v >> 16);
    };
    auto tag = [&w](const char* t) { w.insert(w.end(), t, t + 4); };
    tag("RIFF"); u32(36 + dataBytes); tag("WAVE");
    tag("fmt "); u32(16); u16(1); u16(1); u32(kSwitchSoundRate); u32(kSwitchSoundRate * 2); u16(2); u16(16);
    tag("data"); u32(dataBytes);
    const double pi = 3.14159265358979323846;
    for (int i = 0; i < lead; ++i) u16(0);
    for (int n = 0; n < 2; ++n) {
        for (int i = 0; i < perNote; ++i) {
            // Wood block: a struck fundamental plus two inharmonic partials that die faster.
            const double t = static_cast<double>(i) / kSwitchSoundRate;
            const double attack = t < 0.002 ? t / 0.002 : 1.0;
            const double w0 = 2 * pi * notes[n] * t;
            const double v = attack * (0.15 * std::exp(-t / 0.022) * std::sin(w0) +
                                       0.035 * std::exp(-t / 0.008) * std::sin(2.7 * w0) +
                                       0.012 * std::exp(-t / 0.004) * std::sin(5.2 * w0));
            u16(static_cast<uint16_t>(static_cast<int16_t>(std::lround(v * 32767))));
        }
        if (n == 0)
            for (int i = 0; i < gap; ++i) u16(0);
    }
    return w;
}

std::string switchSoundPath(bool vietnamese, const char *runtimeDir, const char *cacheHome, const char *home) {
    std::string dir;
    if (runtimeDir && runtimeDir[0] == '/') dir = runtimeDir;
    else if (cacheHome && cacheHome[0] == '/') dir = std::string(cacheHome) + "/viettelex";
    else if (home && home[0] == '/') dir = std::string(home) + "/.cache/viettelex";
    else return "";
    return dir + (vietnamese ? "/viettelex-switch-vi.wav" : "/viettelex-switch-en.wav");
}

std::string switchSoundCommand(const std::string &path) {
    std::string q = "'";
    for (char c : path) {
        if (c == '\'') q += "'\\''";
        else q += c;
    }
    q += "'";
    return "(pw-play " + q + " || paplay " + q + " || aplay -q " + q + ") >/dev/null 2>&1 &";
}

void playSwitchSound(bool vietnamese) {
    const std::string path =
        switchSoundPath(vietnamese, std::getenv("XDG_RUNTIME_DIR"), std::getenv("XDG_CACHE_HOME"), std::getenv("HOME"));
    if (path.empty()) return;
    const std::vector<uint8_t> wav = switchSoundWav(vietnamese);
    struct stat st;
    if (stat(path.c_str(), &st) != 0 || static_cast<size_t>(st.st_size) != wav.size()) {
        const std::string dir = path.substr(0, path.rfind('/'));
        mkdir(dir.c_str(), 0700);  // the cache folder; the runtime dir already exists
        if (!writeFileAtomic(path, std::string(wav.begin(), wav.end()))) return;
    }
    const std::string cmd = switchSoundCommand(path);
    char sh[] = "sh", dashC[] = "-c";
    std::string cmdBuf = cmd;
    char *argv[] = {sh, dashC, cmdBuf.data(), nullptr};
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    pid_t pid = -1;
    const int rc = posix_spawn(&pid, "/bin/sh", &fa, nullptr, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    // sh puts the player in the background and exits at once: reaping it never waits for
    // the sound, and the player is re-parented (no zombie in the IM process).
    if (rc == 0 && pid > 0) {
        int status = 0;
        waitpid(pid, &status, 0);
    }
}

}  // namespace viettelex
