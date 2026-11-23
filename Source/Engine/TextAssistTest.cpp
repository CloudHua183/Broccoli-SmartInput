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

#include "gtest/gtest.h"

namespace McBopomofo {
namespace TextAssist {

TEST(AutoSpacingTest, SpacesBetweenCJKAndASCII) {
  EXPECT_EQ(ApplyAutoSpacing("用API呼叫"), "用 API 呼叫");
  EXPECT_EQ(ApplyAutoSpacing("今天2026年"), "今天 2026 年");
  EXPECT_EQ(ApplyAutoSpacing("Meeting開始"), "Meeting 開始");
  EXPECT_EQ(ApplyAutoSpacing("開會call我"), "開會 call 我");
}

TEST(AutoSpacingTest, LeavesPunctuationSpacesAndPureTextAlone) {
  EXPECT_EQ(ApplyAutoSpacing("用 API 呼叫"), "用 API 呼叫");
  EXPECT_EQ(ApplyAutoSpacing("你好，API。"), "你好，API。");
  EXPECT_EQ(ApplyAutoSpacing("「API」"), "「API」");
  EXPECT_EQ(ApplyAutoSpacing("純中文"), "純中文");
  EXPECT_EQ(ApplyAutoSpacing("plain text"), "plain text");
  EXPECT_EQ(ApplyAutoSpacing(""), "");
  EXPECT_EQ(ApplyAutoSpacing("ㄅAPI"), "ㄅ API");
}

TEST(AutoSpacingTest, KeepsSingleLetterWordsTogether) {
  EXPECT_EQ(ApplyAutoSpacing("買T恤"), "買T恤");
  EXPECT_EQ(ApplyAutoSpacing("A股大漲"), "A股大漲");
  EXPECT_EQ(ApplyAutoSpacing("照X光"), "照X光");
  EXPECT_EQ(ApplyAutoSpacing("卡拉OK"), "卡拉 OK");
  EXPECT_EQ(ApplyAutoSpacing("第3章"), "第 3 章");
}

TEST(AutoSpacingTest, ReturnsInvalidUTF8Unchanged) {
  std::string invalid = "A\xE4\xB8";
  EXPECT_EQ(ApplyAutoSpacing(invalid), invalid);
}

TEST(TypingGuardTest, AllowsFastHumanTyping) {
  TypingGuard guard;
  // 15 keys per second with rolling overlaps, sustained for two seconds.
  double t = 0;
  for (int i = 0; i < 30; ++i) {
    EXPECT_EQ(guard.feed(t, i % 26, false), TypingGuard::Result::kAllow);
    t += 1.0 / 15.0;
  }
}

TEST(TypingGuardTest, BlocksAPawOnTheKeyboard) {
  TypingGuard guard;
  // Six different keys land within a few milliseconds.
  TypingGuard::Result last = TypingGuard::Result::kAllow;
  for (int i = 0; i < 6; ++i) {
    last = guard.feed(1.0 + i * 0.005, 10 + i, false);
  }
  EXPECT_EQ(last, TypingGuard::Result::kStartedBlocking);
  EXPECT_EQ(guard.feed(1.1, 3, false), TypingGuard::Result::kBlock);
  // Mashing keeps the lock going; a pause releases it.
  EXPECT_EQ(guard.feed(1.3, 4, false), TypingGuard::Result::kBlock);
  EXPECT_TRUE(guard.locked(3.0));
  EXPECT_EQ(guard.feed(4.0, 5, false), TypingGuard::Result::kAllow);
}

TEST(TypingGuardTest, BlocksLongAutoRepeat) {
  TypingGuard guard;
  TypingGuard::Result result = TypingGuard::Result::kAllow;
  guard.feed(0, 7, false);
  for (int i = 1; i <= 15; ++i) {
    result = guard.feed(0.5 + i * 0.03, 7, true);
  }
  EXPECT_EQ(result, TypingGuard::Result::kStartedBlocking);
}

TEST(TypingGuardTest, ResetUnlocks) {
  TypingGuard guard;
  for (int i = 0; i < 6; ++i) guard.feed(i * 0.001, i, false);
  EXPECT_TRUE(guard.locked(0.5));
  guard.reset();
  EXPECT_FALSE(guard.locked(0.5));
}

}  // namespace TextAssist
}  // namespace McBopomofo
