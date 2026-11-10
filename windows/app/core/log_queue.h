// log_queue.h — debug-log lines written off the keyboard hook's thread (2026-11 audit). With
// "Ghi nhật ký gỡ lỗi" on, every hooked key logged a line, and each line was a synchronous
// open / size / rotate / write / close of debug.log inside the low-level hook callback: a
// slow disk (antivirus, a network profile) held every key system-wide, and past
// LowLevelHooksTimeout Windows removed the hook. The hook thread now only queues the line
// (time taken at the key) and one writer, scheduled when the queue becomes non-empty,
// writes the batch in order. Nothing about the log format changes.
//
// Not thread-safe by itself: the caller holds one lock around push / take / dropped.
#pragma once
#include <cstddef>
#include <utility>
#include <vector>

namespace vtx {

template <class Item>
class DeferredLines {
public:
    static constexpr size_t kMaxQueued = 1024;  // a stuck writer must not grow memory without end

    // Queues `item`. True = no writer is scheduled: the caller schedules one now.
    bool push(Item item) {
        if (items_.size() >= kMaxQueued) {
            ++dropped_;
        } else {
            items_.push_back(std::move(item));
        }
        if (scheduled_) return false;
        scheduled_ = true;
        return true;
    }
    // The writer: the next batch, oldest first. Empty = nothing left, and no writer is
    // scheduled any more (the next push schedules one).
    std::vector<Item> take() {
        std::vector<Item> out;
        out.swap(items_);
        if (out.empty()) scheduled_ = false;
        return out;
    }
    // Scheduling the writer failed: the lines stay queued for the next push (or the flush
    // at exit).
    void scheduleFailed() { scheduled_ = false; }
    // Lines not queued because the queue was full (reported once by the writer, then reset).
    size_t takeDropped() {
        const size_t d = dropped_;
        dropped_ = 0;
        return d;
    }
    size_t size() const { return items_.size(); }
    bool scheduled() const { return scheduled_; }

private:
    std::vector<Item> items_;
    size_t dropped_ = 0;
    bool scheduled_ = false;
};

}  // namespace vtx
