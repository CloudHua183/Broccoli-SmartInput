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

#include "TextAssist.h"

#include <algorithm>
#include <set>
#include <vector>

namespace McBopomofo {
namespace TextAssist {

namespace {

// Decodes UTF-8 into code points. Returns false on malformed input.
bool Decode(std::string_view s, std::vector<char32_t>* out,
            std::vector<std::pair<size_t, size_t>>* spans) {
  size_t i = 0;
  while (i < s.size()) {
    unsigned char c = static_cast<unsigned char>(s[i]);
    size_t len = 0;
    char32_t cp = 0;
    if (c < 0x80) {
      len = 1;
      cp = c;
    } else if ((c >> 5) == 0x6) {
      len = 2;
      cp = c & 0x1F;
    } else if ((c >> 4) == 0xE) {
      len = 3;
      cp = c & 0x0F;
    } else if ((c >> 3) == 0x1E) {
      len = 4;
      cp = c & 0x07;
    } else {
      return false;
    }
    if (i + len > s.size()) return false;
    for (size_t k = 1; k < len; ++k) {
      unsigned char cc = static_cast<unsigned char>(s[i + k]);
      if ((cc >> 6) != 0x2) return false;
      cp = (cp << 6) | (cc & 0x3F);
    }
    out->push_back(cp);
    spans->emplace_back(i, len);
    i += len;
  }
  return true;
}

bool IsCJK(char32_t c) {
  return (c >= 0x2E80 && c <= 0x2FDF) ||    // radicals
         (c >= 0x3040 && c <= 0x30FF) ||    // kana
         (c >= 0x3100 && c <= 0x312F) ||    // bopomofo
         (c >= 0x31A0 && c <= 0x31BF) ||    // bopomofo extended
         (c >= 0x3400 && c <= 0x4DBF) ||    // ext A
         (c >= 0x4E00 && c <= 0x9FFF) ||    // unified
         (c >= 0xF900 && c <= 0xFAFF) ||    // compatibility
         (c >= 0x20000 && c <= 0x323AF);   // ext B and beyond
}

bool IsASCIIAlnum(char32_t c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9');
}

}  // namespace

std::string ApplyAutoSpacing(std::string_view utf8) {
  std::vector<char32_t> cps;
  std::vector<std::pair<size_t, size_t>> spans;
  if (!Decode(utf8, &cps, &spans)) {
    return std::string(utf8);
  }
  // A single letter joined to Chinese is usually one word ("T恤", "A股",
  // "X光", "卡拉OK" is two letters and does get spaced); leave those alone.
  auto isLoneLetter = [&cps](size_t start, size_t end) {
    if (end - start != 1) return false;
    char32_t c = cps[start];
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
  };
  auto runEnd = [&cps](size_t i) {
    while (i < cps.size() && IsASCIIAlnum(cps[i])) ++i;
    return i;
  };
  auto runStart = [&cps](size_t i) {
    while (i > 0 && IsASCIIAlnum(cps[i - 1])) --i;
    return i;
  };

  std::string out;
  out.reserve(utf8.size() + 8);
  for (size_t i = 0; i < cps.size(); ++i) {
    if (i > 0) {
      char32_t a = cps[i - 1];
      char32_t b = cps[i];
      if (IsCJK(a) && IsASCIIAlnum(b)) {
        if (!isLoneLetter(i, runEnd(i))) out.push_back(' ');
      } else if (IsASCIIAlnum(a) && IsCJK(b)) {
        if (!isLoneLetter(runStart(i - 1), i)) out.push_back(' ');
      }
    }
    out.append(utf8.substr(spans[i].first, spans[i].second));
  }
  return out;
}

void TypingGuard::reset() {
  recent_.clear();
  repeats_ = 0;
  lockedUntil_ = 0;
  lastTime_ = 0;
}

TypingGuard::Result TypingGuard::feed(double timestamp, int keyCode,
                                      bool isRepeat) {
  double previous = lastTime_;
  lastTime_ = timestamp;

  if (timestamp < lockedUntil_) {
    if (timestamp - previous <= config_.mashingGap) {
      lockedUntil_ = std::max(lockedUntil_, timestamp + config_.lockSeconds);
    }
    return Result::kBlock;
  }

  repeats_ = isRepeat ? repeats_ + 1 : 0;

  recent_.push_back(Press{timestamp, keyCode});
  while (!recent_.empty() &&
         timestamp - recent_.front().time > config_.burstWindow) {
    recent_.pop_front();
  }
  std::set<int> distinct;
  for (const auto& p : recent_) distinct.insert(p.keyCode);

  if (distinct.size() >= config_.burstDistinctKeys ||
      repeats_ >= config_.repeatLimit) {
    lockedUntil_ = timestamp + config_.lockSeconds;
    recent_.clear();
    repeats_ = 0;
    return Result::kStartedBlocking;
  }
  return Result::kAllow;
}

}  // namespace TextAssist
}  // namespace McBopomofo
