// Copyright (c) 2024 and onwards The McBopomofo Authors.
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

#include <cmath>
#include <memory>
#include <algorithm>
#include <string>
#include <utility>

#include "McBopomofoLM.h"
#include "gtest/gtest.h"

namespace McBopomofo {

constexpr char kPrimaryLMData[] = R"(
# format org.openvanilla.mcbopomofo.sorted
ㄇㄧㄥˊ 明 -3.07936356
ㄇㄧㄥˊ 名 -3.12166252
ㄇㄧㄥˊ 銘 -4.43019121
ㄇㄧㄥˊ-ㄘˊ 名詞 -4.61364867
ㄇㄧㄥˊ-ㄘˋ 名次 -5.47446950
ㄉㄨㄥˋ 動 -2.83459585
ㄉㄨㄥˋ 洞 -4.31757780
ㄉㄨㄥˋ-ㄗㄨㄛˋ 動作 -4.17449149
ㄐㄧㄣ-ㄊㄧㄢ 今天 -3.28959497
ㄐㄧㄣ-ㄊㄧㄢ MACRO@DATE_TODAY_SHORT -8
ㄐㄧㄣ-ㄊㄧㄢ MACRO@DATE_TODAY_MEDIUM -8
ㄔㄥˊ-ㄕˋ 城市 -3.98856498
ㄔㄥˊ-ㄕˋ 程式 -4.07624939
ㄔㄥˊ-ㄕˋ 成事 -5.88664994
ㄙㄜˋ-ㄍㄨˇ 澀谷 -6.78973993
ㄙㄜˋ-ㄍㄨˇ 渋谷 -6.78973993
)";

constexpr char kAssociatedPhrasesV2Data[] = R"(
# format org.openvanilla.mcbopomofo.sorted
名-ㄇㄧㄥˊ-下-ㄒㄧㄚˋ -5.7106
名-ㄇㄧㄥˊ-不-ㄅㄨˊ-見-ㄐㄧㄢˋ-經-ㄐㄧㄥ-傳-ㄓㄨㄢˋ -5.9904
)";

constexpr char kUserPhrasesData[] = R"(
茗 ㄇㄧㄥˊ
丼 ㄉㄨㄥˋ
名刺 ㄇㄧㄥˊ-ㄘˋ
程式 ㄔㄥˊ-ㄕˋ
)";

constexpr char kRankedUserPhrasesData[] = R"(
首選 ㄉㄨㄥˋ
次選 ㄉㄨㄥˋ
)";

constexpr char kCandidateOrderData[] = R"(
# reading followed by the values that should come first
ㄇㄧㄥˊ 銘 名
)";

constexpr char kExcludedPhrasesData[] = R"(
動作 ㄉㄨㄥˋ-ㄗㄨㄛˋ
)";

constexpr char kPhreaseReplacementMapData[] = R"(
動作 动作
澀谷 渋谷
)";

TEST(McBopomofoLMTest, PrimaryLanguageModel) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));

  EXPECT_TRUE(lm.hasUnigrams("ㄇㄧㄥˊ-ㄘˊ"));
  EXPECT_FALSE(lm.hasUnigrams("ㄉㄨㄥˋ-ㄘˊ"));
  auto unigrams = lm.getUnigrams("ㄇㄧㄥˊ-ㄘˊ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "名詞");
  EXPECT_LT(unigrams[0].score(), 0);
}

TEST(McBopomofoLMTest, AssociatedPhrasesV2) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(
      kAssociatedPhrasesV2Data, sizeof(kAssociatedPhrasesV2Data));
  lm.loadAssociatedPhrasesV2(std::move(db));

  auto phrases = lm.findAssociatedPhrasesV2("名", {"ㄇㄧㄥˊ"});
  EXPECT_FALSE(phrases.empty());
  EXPECT_EQ(phrases[0].value, "名下");
  EXPECT_EQ(phrases[0].readings,
            (std::vector<std::string>{"ㄇㄧㄥˊ", "ㄒㄧㄚˋ"}));

  EXPECT_TRUE(lm.findAssociatedPhrasesV2("銘", {"ㄇㄧㄥˊ"}).empty());
}

TEST(McBopomofoLMTest, UserPhrases) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));
  lm.loadUserPhrases(kUserPhrasesData, sizeof(kUserPhrasesData));

  auto unigrams = lm.getUnigrams("ㄇㄧㄥˊ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "茗");
}

TEST(McBopomofoLMTest, ExcludedPhrases) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));

  auto unigrams = lm.getUnigrams("ㄉㄨㄥˋ-ㄗㄨㄛˋ");
  EXPECT_FALSE(unigrams.empty());

  lm.loadExcludedPhrases(kExcludedPhrasesData, sizeof(kExcludedPhrasesData));
  unigrams = lm.getUnigrams("ㄉㄨㄥˋ-ㄗㄨㄛˋ");
  EXPECT_TRUE(unigrams.empty());
}

TEST(McBopomofoLMTest, PhraseReplacementMap) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));
  lm.loadPhraseReplacementMap(kPhreaseReplacementMapData,
                              sizeof(kPhreaseReplacementMapData));
  auto unigrams = lm.getUnigrams("ㄉㄨㄥˋ-ㄗㄨㄛˋ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "動作");

  lm.setPhraseReplacementEnabled(true);
  unigrams = lm.getUnigrams("ㄉㄨㄥˋ-ㄗㄨㄛˋ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "动作");
}

TEST(McBopomofoLMTest, PhraseReplacementMapDeduplicates) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));
  lm.loadPhraseReplacementMap(kPhreaseReplacementMapData,
                              sizeof(kPhreaseReplacementMapData));
  auto unigrams = lm.getUnigrams("ㄙㄜˋ-ㄍㄨˇ");
  EXPECT_EQ(unigrams.size(), 2);

  lm.setPhraseReplacementEnabled(true);
  unigrams = lm.getUnigrams("ㄙㄜˋ-ㄍㄨˇ");
  ASSERT_EQ(unigrams.size(), 1);
  EXPECT_EQ(unigrams[0].value(), "渋谷");
}

TEST(McBopomofoLMTest, UserPhrasesOverrideDefaultLanguageModelPhrases) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));
  auto unigrams = lm.getUnigrams("ㄔㄥˊ-ㄕˋ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "城市");

  lm.loadUserPhrases(kUserPhrasesData, sizeof(kUserPhrasesData));
  unigrams = lm.getUnigrams("ㄔㄥˊ-ㄕˋ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "程式");
}

TEST(McBopomofoLMTest, MonoSyllableUserPhrasesNeedRewrite) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));
  lm.loadUserPhrases(kUserPhrasesData, sizeof(kUserPhrasesData));

  auto unigrams = lm.getUnigrams("ㄉㄨㄥˋ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "丼");
  // This user unigram's score is recomputed and must be < kUserUnigramScore.
  EXPECT_LT(unigrams[0].score(), UserPhrasesLM::kUserUnigramScore);
  EXPECT_GT(unigrams[0].score(), unigrams[1].score());
  // The delta between the two should be minuscule.
  EXPECT_LT(std::abs(unigrams[0].score() - unigrams[1].score()), 0.000001);
}

TEST(McBopomofoLMTest, MonoSyllableUserPhraseRewritePreservesUserOrder) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));
  lm.loadUserPhrases(kRankedUserPhrasesData, sizeof(kRankedUserPhrasesData));

  auto unigrams = lm.getUnigrams("ㄉㄨㄥˋ");
  ASSERT_GE(unigrams.size(), 2);
  EXPECT_EQ(unigrams[0].value(), "首選");
  EXPECT_EQ(unigrams[1].value(), "次選");
  EXPECT_GT(unigrams[0].score(), unigrams[1].score());
}

TEST(McBopomofoLMTest, MultipleSyllableUserPhrasesNeedNoRewrite) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));
  lm.loadUserPhrases(kUserPhrasesData, sizeof(kUserPhrasesData));

  auto unigrams = lm.getUnigrams("ㄇㄧㄥˊ-ㄘˋ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "名刺");
  // This user unigram's score is not recomputed, so is still kUserUnigramScore.
  EXPECT_EQ(unigrams[0].score(), UserPhrasesLM::kUserUnigramScore);
  EXPECT_EQ(unigrams[1].value(), "名次");
  EXPECT_LT(unigrams[1].score(), 0);
}

TEST(McBopomofoLMTest, CandidateOrderMovesListedValuesToTheFront) {
  McBopomofoLM lm;
  lm.loadLanguageModel(std::make_unique<ParselessPhraseDB>(
      kPrimaryLMData, sizeof(kPrimaryLMData)));

  auto before = lm.getUnigrams("ㄇㄧㄥˊ");
  ASSERT_EQ(before.size(), 3);
  EXPECT_EQ(before[0].value(), "明");
  EXPECT_EQ(before[1].value(), "名");
  EXPECT_EQ(before[2].value(), "銘");

  lm.loadCandidateOrder(kCandidateOrderData, sizeof(kCandidateOrderData));

  auto after = lm.getUnigrams("ㄇㄧㄥˊ");
  ASSERT_EQ(after.size(), 3);
  EXPECT_EQ(after[0].value(), "銘");
  EXPECT_EQ(after[1].value(), "名");
  // 明 was not listed, so it falls in behind the listed values.
  EXPECT_EQ(after[2].value(), "明");
}

TEST(McBopomofoLMTest, CandidateOrderKeepsTheSameScoreSet) {
  McBopomofoLM lm;
  lm.loadLanguageModel(std::make_unique<ParselessPhraseDB>(
      kPrimaryLMData, sizeof(kPrimaryLMData)));
  auto before = lm.getUnigrams("ㄇㄧㄥˊ");
  std::vector<double> beforeScores;
  for (const auto& unigram : before) {
    beforeScores.push_back(unigram.score());
  }
  std::sort(beforeScores.begin(), beforeScores.end());

  lm.loadCandidateOrder(kCandidateOrderData, sizeof(kCandidateOrderData));
  auto after = lm.getUnigrams("ㄇㄧㄥˊ");
  std::vector<double> afterScores;
  for (const auto& unigram : after) {
    afterScores.push_back(unigram.score());
  }
  std::sort(afterScores.begin(), afterScores.end());

  // Reordering must not invent or lose scores. The top score in particular has
  // to survive, otherwise the grid would start segmenting sentences
  // differently just because the user reordered a candidate list.
  EXPECT_EQ(beforeScores, afterScores);
  EXPECT_EQ(after[0].score(), *std::max_element(beforeScores.begin(),
                                                beforeScores.end()));
  // The list is still ordered by descending score after the rewrite.
  for (size_t i = 1; i < after.size(); ++i) {
    EXPECT_LE(after[i].score(), after[i - 1].score());
  }
}

TEST(McBopomofoLMTest, CandidateOrderLeavesUnlistedReadingsAlone) {
  McBopomofoLM lm;
  lm.loadLanguageModel(std::make_unique<ParselessPhraseDB>(
      kPrimaryLMData, sizeof(kPrimaryLMData)));
  lm.loadCandidateOrder(kCandidateOrderData, sizeof(kCandidateOrderData));

  auto unigrams = lm.getUnigrams("ㄉㄨㄥˋ");
  ASSERT_EQ(unigrams.size(), 2);
  EXPECT_EQ(unigrams[0].value(), "動");
  EXPECT_EQ(unigrams[1].value(), "洞");
}

TEST(McBopomofoLMTest, CandidateOrderAppliesOnTopOfUserPhrases) {
  McBopomofoLM lm;
  lm.loadLanguageModel(std::make_unique<ParselessPhraseDB>(
      kPrimaryLMData, sizeof(kPrimaryLMData)));
  lm.loadUserPhrases(kUserPhrasesData, sizeof(kUserPhrasesData));

  auto before = lm.getUnigrams("ㄇㄧㄥˊ");
  ASSERT_EQ(before.size(), 4);
  // The user phrase 茗 is promoted to the front by the user phrase rewrite.
  EXPECT_EQ(before[0].value(), "茗");

  constexpr char kOrderOverUserPhrase[] = "ㄇㄧㄥˊ 銘 茗\n";
  lm.loadCandidateOrder(kOrderOverUserPhrase, sizeof(kOrderOverUserPhrase) - 1);

  auto after = lm.getUnigrams("ㄇㄧㄥˊ");
  ASSERT_EQ(after.size(), 4);
  EXPECT_EQ(after[0].value(), "銘");
  EXPECT_EQ(after[1].value(), "茗");
}

TEST(McBopomofoLMTest, ExternalConverterWhenNotSetThenEnablingItIsNoOp) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));
  lm.setExternalConverterEnabled(true);

  auto unigrams = lm.getUnigrams("ㄇㄧㄥˊ-ㄘˊ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "名詞");
}

TEST(McBopomofoLMTest, ExternalConverter) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));

  auto unigrams = lm.getUnigrams("ㄇㄧㄥˊ-ㄘˊ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "名詞");

  lm.setExternalConverterEnabled(true);
  lm.setExternalConverter([](const auto& value) { return value + "!"; });

  unigrams = lm.getUnigrams("ㄇㄧㄥˊ-ㄘˊ");
  ASSERT_FALSE(unigrams.empty());
  EXPECT_EQ(unigrams[0].value(), "名詞!");
}

TEST(McBopomofoLMTest, ExternalConverterConversionResultsAreDeduplicated) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));

  auto unigrams = lm.getUnigrams("ㄇㄧㄥˊ");
  ASSERT_GT(unigrams.size(), 1);

  lm.setExternalConverterEnabled(true);
  lm.setExternalConverter([](const auto&) { return "!"; });

  unigrams = lm.getUnigrams("ㄇㄧㄥˊ");
  ASSERT_EQ(unigrams.size(), 1);
  EXPECT_EQ(unigrams[0].value(), "!");
}

TEST(McBopomofoLMTest, DefaultMacroConverterIsNoOp) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));

  ASSERT_EQ(lm.convertMacro("MACRO@DATE_TODAY_SHORT"),
            "MACRO@DATE_TODAY_SHORT");
}

TEST(McBopomofoLMTest, MacroValueNotRecognizedByMacroConverterIsFiltered) {
  McBopomofoLM lm;
  auto db = std::make_unique<ParselessPhraseDB>(kPrimaryLMData,
                                                sizeof(kPrimaryLMData));
  lm.loadLanguageModel(std::move(db));

  lm.setMacroConverter([](const std::string& macro) {
    if (macro == "MACRO@DATE_TODAY_SHORT") {
      return std::string("6/10/21");
    }
    return macro;
  });

  auto unigrams = lm.getUnigrams("ㄐㄧㄣ-ㄊㄧㄢ");
  ASSERT_EQ(unigrams.size(), 2);  // only one macro is supported
  EXPECT_EQ(unigrams[0].value(), "今天");
  EXPECT_EQ(unigrams[1].value(), "6/10/21");
}

}  // namespace McBopomofo
