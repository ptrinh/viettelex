// caret_hints.cpp — see caret_hints.h.
#include "viettelex/caret_hints.h"

#include "viettelex/keys.h"
#include "viettelex/text_tools.h"

#include "telexcore.h"

#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

namespace viettelex {

namespace {

// UTF-8 → code points (invalid bytes become U+FFFD).
std::vector<uint32_t> decode(const std::string &s) {
    std::vector<uint32_t> out;
    for (size_t i = 0; i < s.size();) {
        unsigned char b = static_cast<unsigned char>(s[i]);
        size_t n = b < 0x80 ? 1 : (b >> 5) == 6 ? 2 : (b >> 4) == 14 ? 3 : (b >> 3) == 30 ? 4 : 0;
        if (n == 0 || i + n > s.size()) {
            out.push_back(0xfffd);
            ++i;
            continue;
        }
        uint32_t cp = n == 1 ? b : n == 2 ? (b & 0x1f) : n == 3 ? (b & 0x0f) : (b & 0x07);
        for (size_t k = 1; k < n; ++k) cp = (cp << 6) | (static_cast<unsigned char>(s[i + k]) & 0x3f);
        out.push_back(cp);
        i += n;
    }
    return out;
}

std::string encode(uint32_t cp) {
    std::string o;
    if (cp < 0x80) o += char(cp);
    else if (cp < 0x800) { o += char(0xc0 | (cp >> 6)); o += char(0x80 | (cp & 0x3f)); }
    else if (cp < 0x10000) {
        o += char(0xe0 | (cp >> 12)); o += char(0x80 | ((cp >> 6) & 0x3f)); o += char(0x80 | (cp & 0x3f));
    } else {
        o += char(0xf0 | (cp >> 18)); o += char(0x80 | ((cp >> 12) & 0x3f));
        o += char(0x80 | ((cp >> 6) & 0x3f)); o += char(0x80 | (cp & 0x3f));
    }
    return o;
}

uint32_t lowerCp(uint32_t c) {
    if (c >= 'A' && c <= 'Z') return c + 0x20;
    if (c >= 0xc0 && c <= 0xde && c != 0xd7) return c + 0x20;
    if (c >= 0x100 && c <= 0x17f && c % 2 == 0 && c != 0x130 && c != 0x138) return c + 1;  // Ă Đ Ĩ Ũ …
    if (c == 0x1a0 || c == 0x1af) return c + 1;                                           // Ơ Ư
    if (c >= 0x1ea0 && c <= 0x1ef9 && c % 2 == 0) return c + 1;                           // Ạ … Ỹ
    return c;
}

// Swift Character.isLetter for the scripts a Vietnamese IME produces.
bool isLetterCp(uint32_t c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= 0xc0 && c <= 0x24f && c != 0xd7 && c != 0xf7) ||
           (c >= 0x1e00 && c <= 0x1eff);
}

bool isAsciiLetters(const std::string &s) {
    for (unsigned char c : s)
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))) return false;
    return !s.empty();
}

bool isDigitCp(uint32_t c) { return c >= '0' && c <= '9'; }

size_t cpCount(const std::string &s) {
    size_t n = 0;
    for (unsigned char c : s)
        if ((c & 0xc0) != 0x80) ++n;
    return n;
}

// Blocks SIGPIPE on this thread while the helper's pipes are used (a helper that just exited
// must not kill the IM process); consumes a pending one before restoring.
class PipeGuard {
public:
    PipeGuard() {
        sigset_t s;
        sigemptyset(&s);
        sigaddset(&s, SIGPIPE);
        pthread_sigmask(SIG_BLOCK, &s, &old_);
    }
    ~PipeGuard() {
        sigset_t s;
        sigemptyset(&s);
        sigaddset(&s, SIGPIPE);
        struct timespec zero = {0, 0};
        while (sigtimedwait(&s, nullptr, &zero) > 0) {
        }
        pthread_sigmask(SIG_SETMASK, &old_, nullptr);
    }

private:
    sigset_t old_;
};

}  // namespace

namespace hints {

KeyAction keyAction(CaretSuggestion::Kind kind, uint32_t keysym, uint32_t mods) {
    bool plain = (mods & (VT_MOD_SHIFT | VT_MOD_CTRL | VT_MOD_ALT | VT_MOD_SUPER)) == 0;
    if (keysym == ks::Escape && plain) return KeyAction::DismissConsume;
    if (!plain) return KeyAction::DismissPass;
    if (keysym == ks::Tab) return KeyAction::Accept;
    if (kind == CaretSuggestion::Kind::Math && (keysym == ks::Return || keysym == ks::KP_Enter))
        return KeyAction::Accept;
    return KeyAction::DismissPass;
}

std::string label(const CaretSuggestion &s) {
    return s.display + (s.kind == CaretSuggestion::Kind::Math ? "   Tab / Enter" : "   Tab");
}

std::string escape(const std::string &s) {
    std::string o;
    o.reserve(s.size());
    for (char c : s) {
        switch (c) {
        case '\\': o += "\\\\"; break;
        case '\t': o += "\\t"; break;
        case '\n': o += "\\n"; break;
        case '\r': o += "\\r"; break;
        default: o += c;
        }
    }
    return o;
}

static std::string unescape(const std::string &s) {
    std::string o;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] != '\\' || i + 1 == s.size()) {
            o += s[i];
            continue;
        }
        char n = s[++i];
        o += n == 't' ? '\t' : n == 'n' ? '\n' : n == 'r' ? '\r' : n;
    }
    return o;
}

std::string request(const std::vector<std::string> &fields) {
    std::string o;
    for (size_t i = 0; i < fields.size(); ++i) {
        if (i) o += '\t';
        o += escape(fields[i]);
    }
    return o;
}

bool parseAnswer(const std::string &line, CaretSuggestion &out) {
    std::vector<std::string> f;
    size_t start = 0;
    while (true) {
        size_t t = line.find('\t', start);
        f.push_back(unescape(line.substr(start, t == std::string::npos ? std::string::npos : t - start)));
        if (t == std::string::npos) break;
        start = t + 1;
    }
    const bool predict = !f.empty() && f[0] == "predict";
    if (f.size() != 4 || f[1].empty() || f[3].empty()) return false;
    CaretSuggestion s;
    if (f[0] == "math") s.kind = CaretSuggestion::Kind::Math;
    else if (f[0] == "number") s.kind = CaretSuggestion::Kind::Number;
    else if (f[0] == "typo") s.kind = CaretSuggestion::Kind::Typo;
    else if (f[0] == "tones") s.kind = CaretSuggestion::Kind::Tones;
    else if (f[0] == "date") s.kind = CaretSuggestion::Kind::Date;
    else if (predict) s.kind = CaretSuggestion::Kind::Predict;
    else return false;
    // Math only inserts; Predict replaces the word being typed or inserts the next word.
    if (s.kind == CaretSuggestion::Kind::Math ? !f[2].empty() : (!predict && f[2].empty())) return false;
    s.display = f[1];
    s.replace = f[2];
    s.insert = f[3];
    out = std::move(s);
    return true;
}

std::string lower(const std::string &s) {
    std::string o;
    for (uint32_t c : decode(s)) o += encode(lowerCp(c));
    return o;
}

bool numberWorthChecking(uint32_t boundary, const std::string &run, const std::string &prevRun) {
    if (boundary != ' ' || run.empty()) return false;
    auto hasDigit = [](const std::string &s) {
        for (unsigned char c : s)
            if (isDigitCp(c)) return true;
        return false;
    };
    if (hasDigit(run)) return true;
    return cpCount(run) <= 6 && hasDigit(prevRun);
}

bool dateCandidate(uint32_t boundary, const std::string &prevRun, const std::string &run) {
    if (boundary != ' ' || run.empty() || cpCount(run) > 9) return false;
    std::string p = lower(prevRun), w = lower(run);
    if (w == "âl" || w == "tết") return true;  // âm lịch / Tết kế tiếp, từ trước bất kỳ
    if (prevRun.empty()) return false;
    if ((p == "hôm" && (w == "nay" || w == "qua")) || (p == "ngày" && (w == "mai" || w == "âm")) ||
        (p == "bây" && w == "giờ") || (p == "âm" && w == "lịch"))
        return true;
    return (w == "today" || w == "tomorrow" || w == "yesterday" || w == "now") && isAsciiLetters(prevRun);
}

bool typoWorthChecking(uint32_t boundary, const std::string &raw, const std::string &word) {
    // AutoCorrect.triggers — not . : ' " (domains, times, "don't").
    if (!(boundary == ' ' || boundary == 0xa0 || boundary == ',' || boundary == ';' || boundary == '!' ||
          boundary == '?' || boundary == ')'))
        return false;
    if (raw.size() < 3 || raw.size() > 10 || !isAsciiLetters(raw) || word.empty()) return false;
    for (uint32_t c : decode(word))
        if (!isLetterCp(c)) return false;
    return !vt_is_valid_syllable(word.c_str(), true);
}

bool typoKnownEnglish(const std::string &raw) {
    if (raw.empty() || raw.size() > 16 || !isAsciiLetters(raw)) return false;
    char lower[17];
    size_t n = 0;
    for (char c : raw) lower[n++] = (c >= 'A' && c <= 'Z') ? char(c - 'A' + 'a') : c;
    lower[n] = '\0';
    return vt_is_english_word(lower);
}

ToneTrigger ToneTracker::feed(const std::string &chunk, uint32_t b) {
    constexpr int kMin = 3, kMax = 40;
    if (b == '\n' || b == '\r') {
        count_ = 0;
        return ToneTrigger::None;
    }
    if (b == ' ' || b == '\t' || b == 0xa0) {
        if (chunk.empty()) return ToneTrigger::None;
        char l = chunk.back();
        if (l == '.' || l == '!' || l == '?') {
            count_ = 0;
            return ToneTrigger::None;
        }
        count_ = vt_is_unaccented_syllable(chunk.c_str()) ? std::min(count_ + 1, kMax) : 0;
        return count_ >= kMin ? ToneTrigger::Pause : ToneTrigger::None;
    }
    if (b == '.' || b == '!' || b == '?') {
        bool ok = !chunk.empty() && vt_is_unaccented_syllable(chunk.c_str());
        int n = ok ? count_ + 1 : 0;
        count_ = 0;
        return n >= kMin ? ToneTrigger::SentenceEnd : ToneTrigger::None;
    }
    return ToneTrigger::None;
}

bool Rejected::contains(const std::string &w) const { return set_.count(lower(w)) != 0; }

void Rejected::add(const std::string &w) {
    std::string k = lower(w);
    if (k.empty() || !set_.insert(k).second) return;
    order_.push_back(k);
    while (order_.size() > cap_) {
        set_.erase(order_.front());
        order_.pop_front();
    }
}

// MARK: Học từ bạn gõ (LearnedModel.swift)

bool learnable(const std::string &w) {
    std::vector<uint32_t> cps = decode(w);
    if (cps.empty() || cps.size() > 12) return false;
    int run = 0;
    uint32_t prev = 0;
    for (uint32_t c : cps) {
        if (!isLetterCp(c)) return false;
        run = c == prev ? run + 1 : 1;
        if (run >= 3) return false;
        prev = c;
    }
    return true;
}

bool LearnTracker::commit(const std::string &word, uint32_t boundary, bool standsAlone, int weight, Event &out) {
    const bool had = pending_;
    if (had) out = held_;
    pending_ = false;
    const std::string w = lower(word);
    if (!standsAlone || !learnable(w)) {
        prev1_.clear();
        prev2_.clear();
        return had;
    }
    held_ = Event{w, prev1_, prev2_, weight, word};
    pending_ = true;
    if (boundary == ' ') {
        prev2_ = prev1_;
        prev1_ = w;
    } else {
        prev1_.clear();
        prev2_.clear();
    }
    return had;
}

void LearnTracker::replacePending(const std::string &fixed) {
    if (!pending_) return;
    const std::string f = lower(fixed);
    if (!learnable(f)) return discard();
    if (prev1_ == held_.word) prev1_ = f;
    held_.word = f;
    held_.form = fixed;
}

void LearnTracker::discard() {
    pending_ = false;
    prev1_.clear();
    prev2_.clear();
}

bool LearnTracker::breakContext(Event &out) {
    const bool had = pending_;
    if (had) out = held_;
    discard();
    return had;
}

std::string learnRequest(const LearnTracker::Event &e) {
    return request({"learn", e.form.empty() ? e.word : e.form, e.prev1, e.prev2, std::to_string(e.weight)});
}

}  // namespace hints

// MARK: - HintService

HintService::HintService(Post post, std::string helperPath)
    : post_(std::move(post)), helper_(helperPath.empty() ? textToolHelperPath() : std::move(helperPath)),
      alive_(std::make_shared<std::atomic<bool>>(true)) {}

HintService::~HintService() {
    alive_->store(false);
    {
        std::lock_guard<std::mutex> l(mu_);
        stop_ = true;
        next_.reset();
        oneway_.clear();
    }
    cv_.notify_all();
    // No query in flight: close the helper's stdin and give it a moment to save what it learned
    // (Học từ bạn gõ — it writes on EOF), then fall through to the kill below.
    {
        std::unique_lock<std::mutex> pl(procMu_, std::try_to_lock);
        if (pl.owns_lock() && pid_ > 0 && in_ >= 0) {
            close(in_);
            in_ = -1;
            for (int i = 0; i < 30; ++i) {  // ≤ 300 ms
                int st = 0;
                if (waitpid(pid_, &st, WNOHANG) == pid_) {
                    pid_ = -1;
                    break;
                }
                usleep(10000);
            }
        }
    }
    int pid = pid_;
    if (pid > 0) kill(pid, SIGKILL);  // unblocks a query in flight
    if (worker_.joinable()) worker_.join();
    std::lock_guard<std::mutex> l(procMu_);
    stopHelper();
}

bool HintService::available() const { return access(helper_.c_str(), X_OK) == 0; }

void HintService::startWorker() {
    if (worker_.joinable()) return;
    try {
        worker_ = std::thread([this] { loop(); });
    } catch (...) {
        next_.reset();
        oneway_.clear();
    }
}

void HintService::submit(HintRequest req, Done done) {
    {
        std::lock_guard<std::mutex> l(mu_);
        if (stop_) return;
        if (req.oneway) {
            if (req.line.empty() || oneway_.size() >= 256) return;  // the helper is stuck: drop
            oneway_.push_back(std::move(req.line));
        } else {
            next_.reset(new Job{std::move(req), std::move(done)});
        }
        startWorker();
    }
    cv_.notify_all();
}

void HintService::loop() {
    while (true) {
        std::unique_ptr<Job> job;
        std::deque<std::string> lines;
        {
            std::unique_lock<std::mutex> l(mu_);
            auto ready = [this] { return stop_ || next_ || !oneway_.empty(); };
            // While a helper exists, wake up now and then to reap it once it quit on idle.
            while (!ready()) {
                if (pid_ > 0) {
                    if (!cv_.wait_for(l, std::chrono::milliseconds(kReapEveryMs), ready)) {
                        l.unlock();
                        reapExitedHelper();
                        l.lock();
                    }
                } else {
                    cv_.wait(l, ready);
                }
            }
            if (stop_) return;
            lines.swap(oneway_);
        }
        // One-way lines first, in order (answers ignored).
        for (const std::string &line : lines) {
            std::string ignored;
            query(line, ignored, 1000);
        }
        {
            std::unique_lock<std::mutex> l(mu_);
            if (stop_) return;
            if (!next_) continue;
            job = std::move(next_);
            if (job->req.delayMs > 0) {
                // A pause trigger: wait it out; a newer request (or stop) wins.
                bool superseded = cv_.wait_for(l, std::chrono::milliseconds(job->req.delayMs),
                                               [this] { return stop_ || next_; });
                if (stop_) return;
                if (superseded) continue;
            }
        }
        auto current = [&job] { return !job->req.liveGen || job->req.liveGen->load() == job->req.gen; };
        if (!current()) continue;
        std::string ans;
        CaretSuggestion s;
        bool got = !job->req.line.empty() && query(job->req.line, ans) && hints::parseAnswer(ans, s);
        if (!got && !job->req.fallback.empty() && current()) {
            // No other suggestion: the fallback (word prediction) after its own pause.
            int wait = job->req.fallbackDelayMs - job->req.delayMs;
            if (wait > 0) {
                std::unique_lock<std::mutex> l(mu_);
                bool superseded =
                    cv_.wait_for(l, std::chrono::milliseconds(wait), [this] { return stop_ || next_; });
                if (stop_) return;
                if (superseded) continue;
            }
            got = current() && query(job->req.fallback, ans) && hints::parseAnswer(ans, s);
        }
        if (!got || !current()) continue;
        if (!alive_->load()) return;
        auto alive = alive_;
        Done done = std::move(job->done);
        post_([alive, done, s]() {
            if (alive->load() && done) done(true, s);
        });
    }
}

void HintService::stopHelper() {
    if (in_ >= 0) close(in_);
    if (out_ >= 0) close(out_);
    in_ = out_ = -1;
    buf_.clear();
    int pid = pid_;
    if (pid > 0) {
        int st = 0;
        if (waitpid(pid, &st, WNOHANG) == 0) {
            kill(pid, SIGKILL);
            waitpid(pid, &st, 0);
        }
    }
    pid_ = -1;
}

bool HintService::reapExitedHelper() {
    std::lock_guard<std::mutex> l(procMu_);
    int pid = pid_;
    if (pid <= 0) return false;
    int st = 0;
    if (waitpid(pid, &st, WNOHANG) != pid) return false;
    pid_ = -1;  // already reaped: stopHelper must not wait for it again
    stopHelper();
    return true;
}

bool HintService::ensureHelper() {
    if (pid_ > 0) return true;
    if (!available()) return false;
    if (failures_ >= kMaxFailures && std::chrono::steady_clock::now() < noSpawnUntil_) return false;
    int inPipe[2], outPipe[2];
    if (pipe2(inPipe, O_CLOEXEC) != 0) return false;
    if (pipe2(outPipe, O_CLOEXEC) != 0) {
        close(inPipe[0]);
        close(inPipe[1]);
        return false;
    }
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, inPipe[0], 0);
    posix_spawn_file_actions_adddup2(&fa, outPipe[1], 1);
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    std::string arg = "--serve";
    char *argv[] = {const_cast<char *>(helper_.c_str()), const_cast<char *>(arg.c_str()), nullptr};
    pid_t pid = -1;
    int rc = posix_spawn(&pid, helper_.c_str(), &fa, nullptr, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    close(inPipe[0]);
    close(outPipe[1]);
    if (rc != 0) {
        close(inPipe[1]);
        close(outPipe[0]);
        return false;
    }
    fcntl(inPipe[1], F_SETFL, O_NONBLOCK);
    fcntl(outPipe[0], F_SETFL, O_NONBLOCK);
    in_ = inPipe[1];
    out_ = outPipe[0];
    buf_.clear();
    pid_ = pid;
    return true;
}

bool HintService::query(const std::string &line, std::string &answer, int timeoutMs) {
    answer.clear();
    std::lock_guard<std::mutex> l(procMu_);
    PipeGuard guard;
    auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
    auto left = [&deadline] {
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now()).count();
        return int(ms < 0 ? 0 : ms);
    };
    std::string msg = line + "\n";
    // Two attempts: the helper may have exited on idle right before this request.
    for (int attempt = 0; attempt < 2; ++attempt) {
        if (!ensureHelper()) return false;
        bool broken = false;
        size_t written = 0;
        while (written < msg.size()) {
            struct pollfd p = {in_, POLLOUT, 0};
            int pr = poll(&p, 1, left());
            if (pr < 0 && errno == EINTR) continue;
            if (pr <= 0) {  // timeout
                stopHelper();
                return false;
            }
            ssize_t w = write(in_, msg.data() + written, msg.size() - written);
            if (w > 0) written += size_t(w);
            else if (w < 0 && errno != EAGAIN && errno != EINTR) {
                broken = true;
                break;
            }
        }
        while (!broken) {
            size_t nl = buf_.find('\n');
            if (nl != std::string::npos) {
                answer = buf_.substr(0, nl);
                buf_.erase(0, nl + 1);
                failures_ = 0;
                return true;
            }
            struct pollfd p = {out_, POLLIN, 0};
            int pr = poll(&p, 1, left());
            if (pr < 0 && errno == EINTR) continue;
            if (pr <= 0) {  // timeout: a stuck helper is killed, the next request respawns it
                stopHelper();
                return false;
            }
            char tmp[4096];
            ssize_t r = read(out_, tmp, sizeof tmp);
            if (r > 0) {
                buf_.append(tmp, size_t(r));
                if (buf_.size() > (1u << 20)) broken = true;
            } else if (r == 0 || (errno != EAGAIN && errno != EINTR)) {
                broken = true;
            }
        }
        stopHelper();
        // Died (or closed its pipe) without answering. Once is normal — it quits after 2 idle
        // minutes, maybe right before this request — but in a row it is a helper that cannot
        // start: back off instead of spawning twice per word forever.
        if (++failures_ >= kMaxFailures) {
            int n = failures_ - kMaxFailures;
            long ms = long(kBackoffBaseMs) << (n < 5 ? n : 5);
            if (ms > kBackoffMaxMs) ms = kBackoffMaxMs;
            noSpawnUntil_ = std::chrono::steady_clock::now() + std::chrono::milliseconds(ms);
            return false;
        }
        if (left() == 0) return false;
    }
    return false;
}

}  // namespace viettelex
