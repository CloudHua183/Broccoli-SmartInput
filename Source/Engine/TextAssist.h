// Copyright (c) 2026 and onwards The Broccoli SmartInput Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

// Small text helpers for Broccoli SmartInput that have no Cocoa dependency:
// automatic spacing between CJK and ASCII text (T03), and the typing guard that
// pauses input when keys are mashed (T09).

#ifndef SRC_ENGINE_TEXTASSIST_H_
#define SRC_ENGINE_TEXTASSIST_H_

#include <cstddef>
#include <deque>
#include <string>
#include <string_view>

namespace McBopomofo {
namespace TextAssist {

// Inserts a half-width space wherever a CJK character directly touches an
// ASCII letter or digit, e.g. "用API呼叫" -> "用 API 呼叫". Existing spaces and
// punctuation are left alone, and so is a single letter joined to Chinese
// ("T恤", "A股"). Invalid UTF-8 is returned unchanged.
std::string ApplyAutoSpacing(std::string_view utf8);

// Detects key mashing (a cat on the keyboard, a toddler) and asks the caller
// to swallow keys for a while.
class TypingGuard {
 public:
  struct Config {
    // This many distinct keys pressed within `burstWindow` seconds trips the
    // guard. Fast human typing rarely has more than 3-4 keys in 60 ms.
    size_t burstDistinctKeys = 6;
    double burstWindow = 0.06;
    // This many consecutive auto-repeat events of a printable key trips it.
    size_t repeatLimit = 15;
    // Keys are swallowed for this long after the last mashing key.
    double lockSeconds = 2.0;
    // While locked, a key arriving within this gap of the previous one counts
    // as continued mashing and extends the lock.
    double mashingGap = 0.35;
  };

  TypingGuard() = default;
  explicit TypingGuard(Config config) : config_(config) {}

  enum class Result { kAllow, kBlock, kStartedBlocking };

  // `timestamp` in seconds; `keyCode` identifies the physical key;
  // `isRepeat` is NSEvent.isARepeat. Pass only printable, non-space keys.
  Result feed(double timestamp, int keyCode, bool isRepeat);

  bool locked(double timestamp) const { return timestamp < lockedUntil_; }
  void reset();

 private:
  struct Press {
    double time;
    int keyCode;
  };
  Config config_;
  std::deque<Press> recent_;
  size_t repeats_ = 0;
  double lockedUntil_ = 0;
  double lastTime_ = 0;
};

}  // namespace TextAssist
}  // namespace McBopomofo

#endif  // SRC_ENGINE_TEXTASSIST_H_
