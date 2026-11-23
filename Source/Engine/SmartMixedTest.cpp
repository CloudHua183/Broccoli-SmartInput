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

#include "SmartMixed.h"

#include <set>
#include <string>

#include "gtest/gtest.h"

namespace McBopomofo {
namespace SmartMixed {

namespace {

Lexicon MakeLexicon(std::initializer_list<std::pair<const char*, int>> words) {
  Lexicon lexicon;
  for (const auto& [w, tier] : words) {
    lexicon.add(w, tier);
  }
  lexicon.finalize();
  return lexicon;
}

const Formosa::Mandarin::BopomofoKeyboardLayout* Standard() {
  return Formosa::Mandarin::BopomofoKeyboardLayout::StandardLayout();
}

}  // namespace

TEST(SmartMixedLexiconTest, ExactAndPrefixLookupsIgnoreCase) {
  Lexicon lexicon = MakeLexicon({{"meet", 35}, {"meeting", 35}, {"GitHub", 0}});
  EXPECT_TRUE(lexicon.contains("MEET"));
  EXPECT_TRUE(lexicon.contains("github"));
  EXPECT_FALSE(lexicon.contains("mee"));
  EXPECT_TRUE(lexicon.hasPrefix("mee"));
  EXPECT_TRUE(lexicon.hasPrefix("meet"));
  EXPECT_TRUE(lexicon.hasProperPrefix("meet"));
  EXPECT_FALSE(lexicon.hasProperPrefix("meeting"));
  EXPECT_FALSE(lexicon.hasPrefix("x"));
  EXPECT_EQ(lexicon.find("GITHUB")->word, "GitHub");
}

TEST(SmartMixedLexiconTest, DuplicatesKeepLowestTierAndFirstSpelling) {
  Lexicon lexicon;
  lexicon.add("Zoom", 0);
  lexicon.add("zoom", 40);
  lexicon.add("API", 0);
  lexicon.add("api", 0);
  lexicon.finalize();
  EXPECT_EQ(lexicon.size(), 2u);
  EXPECT_EQ(lexicon.find("zoom")->word, "Zoom");
  EXPECT_EQ(lexicon.find("zoom")->tier, 0);
  EXPECT_EQ(lexicon.find("api")->word, "API");
}

TEST(SmartMixedLexiconTest, RejectsNonAlphanumericWords) {
  Lexicon lexicon;
  EXPECT_FALSE(lexicon.add("e-mail", 0));
  EXPECT_FALSE(lexicon.add("", 0));
  EXPECT_FALSE(lexicon.add("咖啡", 0));
  EXPECT_TRUE(lexicon.add("AI2026", 0));
}

TEST(SmartMixedLexiconTest, AddLinesParsesTiersAndComments) {
  Lexicon lexicon;
  size_t accepted = lexicon.addLines(
      "# comment\nmeeting 35\n\nAPI\nbad-word 10\nchrome\t60\n", 0);
  lexicon.finalize();
  EXPECT_EQ(accepted, 3u);
  EXPECT_EQ(lexicon.find("meeting")->tier, 35);
  EXPECT_EQ(lexicon.find("api")->tier, 0);
  EXPECT_EQ(lexicon.find("chrome")->tier, 60);
}

TEST(SmartMixedLexiconTest, CompletionsOrderByTierThenLength) {
  Lexicon lexicon = MakeLexicon(
      {{"information", 35}, {"informal", 50}, {"inform", 40}, {"infor", 90}});
  auto found = lexicon.completions("info", 3);
  ASSERT_EQ(found.size(), 3u);
  EXPECT_EQ(found[0].word, "information");
  EXPECT_EQ(found[1].word, "inform");
  EXPECT_EQ(found[2].word, "informal");
}

TEST(SmartMixedLearnedChoicesTest, RoundTripsAndLastChoiceWins) {
  LearnedChoices learned;
  learned.recordASCII("Meeting");
  learned.recordBopomofo("su");
  learned.recordBopomofo("call");
  learned.recordASCII("call");
  EXPECT_TRUE(learned.prefersASCII("meeting"));
  EXPECT_TRUE(learned.prefersASCII("call"));
  EXPECT_FALSE(learned.prefersBopomofo("call"));
  EXPECT_TRUE(learned.prefersBopomofo("SU"));

  LearnedChoices restored;
  restored.load(learned.serialize());
  EXPECT_TRUE(restored.prefersASCII("meeting"));
  EXPECT_TRUE(restored.prefersASCII("call"));
  EXPECT_TRUE(restored.prefersBopomofo("su"));
  EXPECT_FALSE(restored.prefersBopomofo("call"));
}

TEST(SmartMixedAnalyzeRunTest, DetectsCleanOverwrittenAndReorderedRuns) {
  Context context;
  context.layout = Standard();

  // su = ㄋㄧ: a normal syllable typed in order.
  RunAnalysis su = AnalyzeRun("su", context);
  EXPECT_TRUE(su.clean);
  EXPECT_FALSE(su.overwrote);
  EXPECT_EQ(su.composed, "ㄋㄧ");

  // meet: the second e (ㄍ) replaces the first; m = ㄩ comes before a
  // consonant, so the keys are also out of order.
  RunAnalysis meet = AnalyzeRun("meet", context);
  EXPECT_FALSE(meet.clean);
  EXPECT_TRUE(meet.overwrote);

  // ap = ㄇㄣ, which must stay Bopomofo.
  RunAnalysis ap = AnalyzeRun("ap", context);
  EXPECT_TRUE(ap.clean);
  EXPECT_EQ(ap.composed, "ㄇㄣ");
}

TEST(SmartMixedAnalyzeRunTest, UsesReadingExistsCallback) {
  Context context;
  context.layout = Standard();
  context.readingExists = [](const std::string& reading) {
    return reading == "ㄋㄧ";
  };
  EXPECT_TRUE(AnalyzeRun("su", context).readingExists);
  EXPECT_FALSE(AnalyzeRun("ap", context).readingExists);
}

class SmartMixedDecideTest : public ::testing::Test {
 protected:
  void SetUp() override {
    known_ = MakeLexicon({{"API", 0}, {"app", 0}, {"call", 0}, {"AI", 0}});
    dictionary_ = MakeLexicon({{"meet", 35},
                               {"meeting", 35},
                               {"meetings", 35},
                               {"chrome", 50},
                               {"test", 35},
                               {"testing", 35},
                               {"the", 35},
                               {"go", 35},
                               {"cup", 35}});
    context_.known = &known_;
    context_.dictionary = &dictionary_;
    context_.learned = &learned_;
    context_.layout = Standard();
    // Syllables the tests rely on as real Mandarin readings.
    context_.readingExists = [](const std::string& reading) {
      static const std::set<std::string> kReadings = {"ㄋㄧ", "ㄇㄣ", "ㄕㄟ",
                                                      "ㄇ"};
      return kReadings.count(reading) > 0;
    };
  }

  Decision decide(const std::string& keys) {
    // Feed one key at a time, as KeyHandler does, and report the first
    // conversion.
    for (size_t i = 1; i <= keys.size(); ++i) {
      if (Decide(keys.substr(0, i), context_) == Decision::kConvertToASCII) {
        return Decision::kConvertToASCII;
      }
    }
    return Decision::kKeepBopomofo;
  }

  Lexicon known_;
  Lexicon dictionary_;
  LearnedChoices learned_;
  Context context_;
};

TEST_F(SmartMixedDecideTest, KeepsRealSyllables) {
  EXPECT_EQ(decide("su"), Decision::kKeepBopomofo);   // ㄋㄧ
  EXPECT_EQ(decide("ap"), Decision::kKeepBopomofo);   // ㄇㄣ, prefix of API
  EXPECT_EQ(decide("go"), Decision::kKeepBopomofo);   // ㄕㄟ: Tab decides
}

TEST_F(SmartMixedDecideTest, ConvertsWhitelistAndClearlyEnglishRuns) {
  EXPECT_EQ(decide("api"), Decision::kConvertToASCII);
  EXPECT_EQ(decide("meet"), Decision::kConvertToASCII);
  EXPECT_EQ(decide("chrome"), Decision::kConvertToASCII);
  EXPECT_EQ(decide("cup"), Decision::kConvertToASCII);  // ㄏㄧㄣ is no syllable
}

TEST_F(SmartMixedDecideTest, ConvertsShortLowercaseWordsTheLegacyRulesMissed) {
  // "test" is not whitelisted and shorter than six letters: the old rules kept
  // it as Bopomofo forever.
  EXPECT_EQ(LegacyDecide("test", context_), Decision::kKeepBopomofo);
  EXPECT_EQ(decide("test"), Decision::kConvertToASCII);
}

TEST_F(SmartMixedDecideTest, LearnedChoicesOverrideHeuristics) {
  learned_.recordBopomofo("api");
  EXPECT_EQ(Decide("api", context_), Decision::kKeepBopomofo);
  learned_.recordASCII("go");
  EXPECT_EQ(Decide("go", context_), Decision::kConvertToASCII);
}

TEST_F(SmartMixedDecideTest, PinyinLayoutFallsBackToLegacyRules) {
  context_.layout =
      Formosa::Mandarin::BopomofoKeyboardLayout::HanyuPinyinLayout();
  EXPECT_EQ(Decide("ni", context_), Decision::kKeepBopomofo);
  EXPECT_EQ(Decide("api", context_), Decision::kConvertToASCII);
}

TEST_F(SmartMixedDecideTest, ContinuesDictionaryWordsAfterConversion) {
  // The old continuation only looked at the whitelist, so "meeting" + "s"
  // dropped back into Bopomofo.
  EXPECT_TRUE(CanContinue("meeting", 's', context_));
  EXPECT_TRUE(CanContinue("test", 'i', context_));
  EXPECT_TRUE(CanContinue("API", '2', context_));
  EXPECT_TRUE(CanContinue("AI2026", '7', context_));
  EXPECT_FALSE(CanContinue("call", 'x', context_));
  EXPECT_FALSE(CanContinue("call", '-', context_));
}

TEST_F(SmartMixedDecideTest, CompleteWordsOnlyContinueTowardCommonWords) {
  Lexicon dictionary = MakeLexicon(
      {{"achieve", 35}, {"achieved", 35}, {"achiever", 60}});
  context_.dictionary = &dictionary;
  EXPECT_TRUE(CanContinue("achieve", 'd', context_));
  // "r" is more likely the ㄐ of the next Chinese syllable than "achiever".
  EXPECT_FALSE(CanContinue("achieve", 'r', context_));
  // Inside a word the dictionary is followed as before.
  EXPECT_TRUE(CanContinue("achi", 'e', context_));
}

TEST_F(SmartMixedDecideTest, BestCompletionPrefersWholeWordsAndCasing) {
  EXPECT_EQ(BestCompletion("meet", context_).value_or(""), "meet");
  // A whitelisted longer word does not replace a typed dictionary word.
  Lexicon knownWithGoogle = MakeLexicon({{"google", 0}});
  const Lexicon* savedKnown = context_.known;
  context_.known = &knownWithGoogle;
  EXPECT_EQ(BestCompletion("go", context_).value_or(""), "go");
  EXPECT_EQ(BestCompletion("goo", context_).value_or(""), "google");
  context_.known = savedKnown;
  EXPECT_EQ(BestCompletion("meeti", context_).value_or(""), "meeting");
  EXPECT_EQ(BestCompletion("ap", context_).value_or(""), "API");
  EXPECT_EQ(BestCompletion("chr", context_).value_or(""), "chrome");
  EXPECT_FALSE(BestCompletion("zq", context_).has_value());
  // A lowercase whitelist entry takes the dictionary's casing.
  Lexicon known = MakeLexicon({{"github", 0}});
  Lexicon dictionary = MakeLexicon({{"GitHub", 30}});
  context_.known = &known;
  context_.dictionary = &dictionary;
  EXPECT_EQ(BestCompletion("github", context_).value_or(""), "GitHub");
  EXPECT_EQ(BestCompletion("gith", context_).value_or(""), "GitHub");
  EXPECT_FALSE(BestCompletion("m", context_).has_value());
}

}  // namespace SmartMixed
}  // namespace McBopomofo
