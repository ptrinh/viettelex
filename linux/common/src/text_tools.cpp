// text_tools.cpp — see text_tools.h.

#include "viettelex/text_tools.h"

#include "viettelex/settings.h"

#include <cctype>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <map>
#include <poll.h>
#include <pthread.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <vector>

extern char **environ;

#ifndef VT_TEXT_TOOL_PATH
#define VT_TEXT_TOOL_PATH "/usr/lib/viettelex/viettelex-text-tool"
#endif

namespace viettelex {

namespace {

struct ToolInfo {
    TextTool tool;
    const char *id;
    const char *vi;
    const char *en;
};

// Labels = macOS TextAction.titleKey (en) / vi.lproj (vi).
const ToolInfo kTools[kTextToolCount] = {
    {TextTool::AddTones, "addTones", "Thêm dấu cho vùng chọn", "Add tones to selection"},
    {TextTool::Upper, "upper", "HOA", "UPPERCASE"},
    {TextTool::Lower, "lower", "thường", "lowercase"},
    {TextTool::Title, "title", "Hoa Đầu Từ", "Title Case"},
    {TextTool::Sentence, "sentence", "Hoa đầu câu", "Sentence case"},
    {TextTool::StripDiacritics, "stripDiacritics", "Xoá dấu", "Remove tones"},
};

const ToolInfo &info(TextTool t) {
    for (const auto &i : kTools)
        if (i.tool == t) return i;
    return kTools[0];
}

// IM menu strings (Fcitx5 status area / IBus property menu). Keep in sync with the
// frontends; test_common checks every key used there has a translation.
const std::map<std::string, std::string> &enTable() {
    static const std::map<std::string, std::string> t = {
        {"Tiếng Việt", "Vietnamese"},
        {"English", "English"},
        {"Đang gõ tiếng Việt — bấm để chuyển sang English", "Typing Vietnamese — click to switch to English"},
        {"Đang gõ English — bấm để chuyển sang tiếng Việt", "Typing English — click to switch to Vietnamese"},
        {"Chuyển Việt/Anh", "Switch Vietnamese/English"},
        {"Cài đặt…", "Settings…"},
        {"Mở VietTelex Settings", "Open VietTelex Settings"},
        {"Công cụ…", "Tools…"},
        {"Công cụ văn bản", "Text tools"},
        {"Công cụ văn bản cho chữ đang bôi đen", "Text tools for the selected text"},
    };
    return t;
}

size_t utf8Chars(const std::string &s) {
    size_t n = 0;
    for (unsigned char c : s)
        if ((c & 0xc0) != 0x80) ++n;
    return n;
}

// Byte offset of character `chars` (clamped to the end).
size_t byteOffset(const std::string &s, size_t chars) {
    size_t byte = 0;
    for (size_t c = 0; c < chars && byte < s.size(); ++c) {
        ++byte;
        while (byte < s.size() && (static_cast<unsigned char>(s[byte]) & 0xc0) == 0x80) ++byte;
    }
    return byte;
}

bool hasLetterOrDigit(const std::string &s) {
    for (unsigned char c : s)
        if (c >= 0x80 || std::isalnum(c)) return true;
    return false;
}

bool executable(const std::string &p) { return !p.empty() && access(p.c_str(), X_OK) == 0; }

// First `name` on $PATH, or "".
std::string which(const char *name) {
    const char *path = std::getenv("PATH");
    std::string all = path && *path ? path : "/usr/local/bin:/usr/bin:/bin";
    size_t start = 0;
    while (start <= all.size()) {
        size_t end = all.find(':', start);
        if (end == std::string::npos) end = all.size();
        std::string dir = all.substr(start, end - start);
        if (!dir.empty()) {
            std::string p = dir + "/" + name;
            struct stat st;
            if (stat(p.c_str(), &st) == 0 && S_ISREG(st.st_mode) && access(p.c_str(), X_OK) == 0) return p;
        }
        start = end + 1;
    }
    return "";
}

bool cloexecPipe(int fds[2]) {
#ifdef __linux__
    return pipe2(fds, O_CLOEXEC) == 0;
#else
    if (pipe(fds) != 0) return false;
    fcntl(fds[0], F_SETFD, FD_CLOEXEC);
    fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    return true;
#endif
}

struct SigpipeGuard {
    sigset_t old, pipe;
    SigpipeGuard() {
        sigemptyset(&pipe);
        sigaddset(&pipe, SIGPIPE);
        pthread_sigmask(SIG_BLOCK, &pipe, &old);
    }
    ~SigpipeGuard() {
        sigset_t pending;
        sigpending(&pending);
        if (sigismember(&pending, SIGPIPE) && !sigismember(&old, SIGPIPE)) {
            int sig;
            sigwait(&pipe, &sig);  // consume ours before unblocking
        }
        pthread_sigmask(SIG_SETMASK, &old, nullptr);
    }
};

// Spawns argv, writes `in` to its stdin, collects stdout, kills it after `timeoutMs`.
// Returns the exit status (0…255), or -1 on spawn failure / timeout / signal.
int runProcess(const std::vector<std::string> &argv, const std::string &in, std::string &out, int timeoutMs,
               size_t maxOut = 4u << 20) {
    int inPipe[2], outPipe[2];
    if (!cloexecPipe(inPipe)) return -1;
    if (!cloexecPipe(outPipe)) {
        close(inPipe[0]);
        close(inPipe[1]);
        return -1;
    }
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, inPipe[0], 0);
    posix_spawn_file_actions_adddup2(&fa, outPipe[1], 1);
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    std::vector<char *> args;
    for (const auto &a : argv) args.push_back(const_cast<char *>(a.c_str()));
    args.push_back(nullptr);
    pid_t pid = -1;
    int rc = posix_spawn(&pid, args[0], &fa, nullptr, args.data(), environ);
    posix_spawn_file_actions_destroy(&fa);
    close(inPipe[0]);
    close(outPipe[1]);
    if (rc != 0) {
        close(inPipe[1]);
        close(outPipe[0]);
        return -1;
    }
    fcntl(inPipe[1], F_SETFL, O_NONBLOCK);
    fcntl(outPipe[0], F_SETFL, O_NONBLOCK);
    // Writing to a child that already exited must not kill the IM process with SIGPIPE:
    // block it on THIS thread only (write then fails with EPIPE), drop it afterwards.
    SigpipeGuard sigpipe;
    size_t written = 0;
    int wfd = inPipe[1];
    if (in.empty()) {
        close(wfd);
        wfd = -1;
    }
    bool timedOut = false;
    auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
    char buf[16384];
    while (true) {
        auto now = std::chrono::steady_clock::now();
        if (now >= deadline) {
            timedOut = true;
            break;
        }
        int wait = int(std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now).count()) + 1;
        struct pollfd fds[2];
        int n = 0;
        fds[n++] = {outPipe[0], POLLIN, 0};
        if (wfd >= 0) fds[n++] = {wfd, POLLOUT, 0};
        int pr = poll(fds, nfds_t(n), wait);
        if (pr < 0) {
            if (errno == EINTR) continue;
            timedOut = true;
            break;
        }
        if (wfd >= 0 && n > 1 && (fds[1].revents & (POLLOUT | POLLERR | POLLHUP))) {
            ssize_t w = write(wfd, in.data() + written, in.size() - written);
            if (w > 0) written += size_t(w);
            if (w < 0 && errno != EAGAIN && errno != EINTR) written = in.size();  // child closed stdin
            if (written >= in.size()) {
                close(wfd);
                wfd = -1;
            }
        }
        if (fds[0].revents & (POLLIN | POLLHUP | POLLERR)) {
            ssize_t r = read(outPipe[0], buf, sizeof buf);
            if (r > 0) {
                out.append(buf, size_t(r));
                if (out.size() > maxOut) {
                    timedOut = true;
                    break;
                }
            } else if (r == 0) {
                break;  // EOF: child done
            } else if (errno != EAGAIN && errno != EINTR) {
                break;
            }
        }
    }
    if (wfd >= 0) close(wfd);
    close(outPipe[0]);
    if (timedOut) kill(pid, SIGKILL);
    int status = 0;
    // After EOF the child is exiting; bounded wait anyway (never hang the worker).
    for (int i = 0; i < 200; ++i) {
        pid_t w = waitpid(pid, &status, timedOut ? 0 : WNOHANG);
        if (w == pid) break;
        if (w < 0 && errno != EINTR) break;
        if (i == 199) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            return -1;
        }
        usleep(5000);
    }
    if (timedOut || !WIFEXITED(status)) return -1;
    return WEXITSTATUS(status);
}

}  // namespace

TextTool textToolAt(int i) { return kTools[i >= 0 && i < kTextToolCount ? i : 0].tool; }

const char *textToolId(TextTool t) { return info(t).id; }

bool textToolFromId(const std::string &id, TextTool &out) {
    for (const auto &i : kTools)
        if (id == i.id) {
            out = i.tool;
            return true;
        }
    return false;
}

std::string textToolLabel(TextTool t, bool english) { return english ? info(t).en : info(t).vi; }

std::string uiText(const std::string &vi, bool english) {
    if (!english) return vi;
    auto it = enTable().find(vi);
    return it == enTable().end() ? vi : it->second;
}

std::string hotkeyLabel(const std::string &value) {
    Hotkey hk;
    if (!parseHotkey(value, hk)) return std::string();
    size_t plus = value.size() >= 2 ? value.rfind('+', value.size() - 2) : std::string::npos;  // "Ctrl++"
    std::string mods = plus == std::string::npos ? std::string() : value.substr(0, plus + 1);
    std::string key = plus == std::string::npos ? value : value.substr(plus + 1);
    if (hk.keysym > 0x20 && hk.keysym < 0x7f)  // z → Z, at → @ (config.hotkey_display)
        key = std::string(1, char(std::toupper(static_cast<int>(hk.keysym))));
    else if (!key.empty()) key[0] = char(std::toupper(static_cast<unsigned char>(key[0])));  // space → Space
    return mods + key;
}

std::string toggleTooltip(const std::string &toggleHotkey, bool english) {
    std::string t = uiText("Chuyển Việt/Anh", english);
    std::string label = hotkeyLabel(toggleHotkey);
    return label.empty() ? t : t + " (" + label + ")";
}

std::string textToolHelperPath() {
    const char *env = std::getenv("VIETTELEX_TEXT_TOOL");
    if (env && *env) return env;
    return VT_TEXT_TOOL_PATH;
}

bool textToolAvailable() { return executable(textToolHelperPath()); }

bool runTextTool(TextTool t, const std::string &in, std::string &out, int timeoutMs) {
    out.clear();
    if (in.empty() || utf8Chars(in) > kTextToolMaxChars || !hasLetterOrDigit(in)) return false;
    std::string helper = textToolHelperPath();
    if (!executable(helper)) return false;
    std::string result;
    int rc = runProcess({helper, textToolId(t)}, in, result, timeoutMs);
    if (rc != 0 || result.empty() || result == in) return false;
    out = std::move(result);
    return true;
}

bool selectionFromSurrounding(const std::string &text, unsigned cursor, unsigned anchor, std::string &out) {
    if (cursor == anchor) return false;
    size_t len = utf8Chars(text);
    unsigned a = cursor < anchor ? cursor : anchor, b = cursor < anchor ? anchor : cursor;
    if (b > len) return false;
    size_t from = byteOffset(text, a), to = byteOffset(text, b);
    out = text.substr(from, to - from);
    return !out.empty();
}

bool primaryAdjacentToCursor(const std::string &text, unsigned cursor, const std::string &primary) {
    if (primary.empty() || cursor > utf8Chars(text)) return false;
    size_t at = byteOffset(text, cursor);
    const size_t n = primary.size();
    if (at >= n && text.compare(at - n, n, primary) == 0) return true;
    return text.size() - at >= n && text.compare(at, n, primary) == 0;
}

bool selectionAtCaret(const std::string &text, unsigned cursor, unsigned anchor,
                      const std::function<bool(std::string &)> &readPrimary) {
    if (anchor != cursor) return true;
    std::string p;
    if (!readPrimary || !readPrimary(p)) return false;
    return primaryAdjacentToCursor(text, cursor, p);
}

bool selectionAtCaretProbe(const std::string &text, unsigned cursor, unsigned anchor, bool &anchorSeen,
                           const std::string *cachedPrimary, bool liveTool,
                           const std::function<bool(std::string &)> &readLive) {
    if (anchor != cursor) {
        anchorSeen = true;
        return true;
    }
    if (anchorSeen) return false;
    if (cachedPrimary) {
        if (!primaryAdjacentToCursor(text, cursor, *cachedPrimary)) return false;
        if (!liveTool) return true;
    }
    std::string p;
    if (!readLive || !readLive(p)) return false;
    return primaryAdjacentToCursor(text, cursor, p);
}

namespace {
std::vector<std::vector<std::string>> primaryCommands() {
    std::vector<std::vector<std::string>> cmds;
    const char *wl = std::getenv("WAYLAND_DISPLAY");
    const char *x = std::getenv("DISPLAY");
    if (wl && *wl) {
        std::string p = which("wl-paste");
        if (!p.empty()) cmds.push_back({p, "--primary", "--no-newline", "--type", "text/plain;charset=utf-8"});
    }
    if (x && *x) {
        std::string p = which("xclip");
        if (!p.empty()) cmds.push_back({p, "-o", "-selection", "primary"});
        p = which("xsel");
        if (!p.empty()) cmds.push_back({p, "-o", "-p"});
    }
    return cmds;
}
}  // namespace

bool primarySelectionToolAvailable() { return !primaryCommands().empty(); }

bool readPrimarySelection(std::string &out, int timeoutMs) {
    out.clear();
    // The first tool that answers (exit 0) is the answer — empty = nothing selected; the next
    // tool would only spend another timeout saying the same.
    for (const auto &c : primaryCommands()) {
        std::string s;
        if (runProcess(c, "", s, timeoutMs, kTextToolMaxChars * 4 + 16) == 0) {
            out = std::move(s);
            return !out.empty();
        }
    }
    return false;
}

// MARK: - TextToolRunner

TextToolRunner::TextToolRunner(Post post)
    : post_(std::move(post)), busy_(std::make_shared<std::atomic<bool>>(false)),
      alive_(std::make_shared<std::atomic<bool>>(true)) {}

TextToolRunner::~TextToolRunner() { alive_->store(false); }

bool TextToolRunner::start(TextTool tool, Source source, Done done) {
    bool expected = false;
    if (!busy_->compare_exchange_strong(expected, true)) return false;
    auto busy = busy_;
    auto alive = alive_;
    Post post = post_;
    try {
        std::thread([tool, source = std::move(source), done = std::move(done), busy, alive, post]() mutable {
            std::string input, result;
            bool changed = false;
            try {
                if (source && source(input)) changed = runTextTool(tool, input, result);
            } catch (...) {
                changed = false;
            }
            if (!alive->load()) {
                busy->store(false);
                return;
            }
            post([done = std::move(done), busy, alive, changed, input = std::move(input),
                  result = std::move(result)]() {
                busy->store(false);
                if (alive->load() && done) done(changed, input, result);
            });
        }).detach();
    } catch (...) {
        busy_->store(false);
        return false;
    }
    return true;
}

}  // namespace viettelex
