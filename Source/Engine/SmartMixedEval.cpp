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

// Offline evaluation driver for the smart mixed classifier (A8).
//
// Simulates the keystrokes KeyHandler sees on the standard (Dachen) layout and
// reports, for the legacy rules and the current classifier:
//   - zh: syllables typed as Bopomofo that would wrongly turn into English;
//   - en: English words that end up as English automatically, break into
//         Bopomofo part-way, or stay Bopomofo (and whether Tab could fix it).
//
// Usage:
//   SmartMixedEval --dictionary smart-mixed-english-lexicon.txt
//                  --known smart-mixed-ascii-words.txt
//                  --legacy-dictionary /usr/share/dict/words
//                  --readings readings.tsv --corpus corpus.tsv
// readings.tsv: "<toneless syllable>" per line (the syllables that exist).
// corpus.tsv:   "zh<TAB><toneless syllable>[<TAB>weight]",
//               "en<TAB><word>[<TAB>weight]", or
//               "pair<TAB><word><TAB><toneless syllable>": the word typed
//               straight into the syllable with no space. Counts how often
//               the syllable's first key is swallowed into the English word.
// Output is one JSON object on stdout.

#include <cctype>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "SmartMixed.h"

using McBopomofo::SmartMixed::BestCompletion;
using McBopomofo::SmartMixed::CanContinue;
using McBopomofo::SmartMixed::Context;
using McBopomofo::SmartMixed::Decide;
using McBopomofo::SmartMixed::Decision;
using McBopomofo::SmartMixed::LegacyDecide;
using McBopomofo::SmartMixed::Lexicon;
using McBopomofo::SmartMixed::ToLower;

namespace {

std::string ReadFile(const std::string& path) {
  std::ifstream f(path);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

std::string JsonEscape(const std::string& s) {
  std::string out;
  for (char c : s) {
    if (c == '"' || c == '\\') out.push_back('\\');
    out.push_back(c);
  }
  return out;
}

// The continuation rule shipped up to v1.2.1: whitelist prefixes or acronyms.
bool LegacyCanContinue(const std::string& sequence, char next,
                       const Context& context) {
  std::string lower = ToLower(sequence + next);
  if (context.known != nullptr && context.known->hasPrefix(lower)) {
    return true;
  }
  bool acronym = true;
  bool hasDigit = false;
  for (char c : sequence) {
    unsigned char u = static_cast<unsigned char>(c);
    if (std::isdigit(u)) hasDigit = true;
    if (std::isalpha(u) && !std::isupper(u)) acronym = false;
  }
  if (std::isdigit(static_cast<unsigned char>(next))) {
    return hasDigit || acronym;
  }
  return acronym && std::isupper(static_cast<unsigned char>(next));
}

struct Stats {
  double zhTotal = 0, zhFalsePositive = 0;
  double enTotal = 0, enAuto = 0, enBroken = 0, enNever = 0, enTabFix = 0;
  double pairTotal = 0, pairSwallowed = 0;
  std::vector<std::string> pairExamples;
  std::vector<std::string> zhExamples, brokenExamples, neverExamples;
};

enum class EnOutcome { kAuto, kBroken, kNever };

template <typename DecideFn, typename ContinueFn>
EnOutcome SimulateEnglish(const std::string& word, const Context& context,
                          DecideFn decide, ContinueFn canContinue) {
  const auto* layout = context.layout;
  std::string run;
  std::string sequence;
  bool converted = false;
  for (char c : word) {
    if (!converted) {
      bool valid = !layout->keyToComponents(c).empty();
      if (valid && std::isalpha(static_cast<unsigned char>(c))) {
        run.push_back(c);
        if (decide(run, context) == Decision::kConvertToASCII) {
          converted = true;
          sequence = run;
          run.clear();
        }
      } else {
        run.clear();
      }
    } else {
      if (!canContinue(sequence, c, context)) {
        return EnOutcome::kBroken;
      }
      sequence.push_back(c);
    }
  }
  return converted ? EnOutcome::kAuto : EnOutcome::kNever;
}

template <typename DecideFn>
bool SimulateZhFalsePositive(const std::string& keys, const Context& context,
                             DecideFn decide) {
  std::string run;
  for (char c : keys) {
    if (std::isalpha(static_cast<unsigned char>(c))) {
      run.push_back(c);
      if (decide(run, context) == Decision::kConvertToASCII) {
        return true;
      }
    } else {
      run.clear();
    }
  }
  return false;
}

void Add(std::vector<std::string>* v, const std::string& s) {
  if (v->size() < 40) v->push_back(s);
}

void PrintStats(const char* name, const Stats& s, bool last) {
  auto rate = [](double a, double b) { return b > 0 ? a / b : 0.0; };
  auto list = [](const std::vector<std::string>& v) {
    std::string out = "[";
    for (size_t i = 0; i < v.size(); ++i) {
      if (i) out += ", ";
      out += "\"" + JsonEscape(v[i]) + "\"";
    }
    return out + "]";
  };
  std::cout << "  \"" << name << "\": {\n"
            << "    \"zh_false_positive_rate\": " << rate(s.zhFalsePositive, s.zhTotal) << ",\n"
            << "    \"en_auto_rate\": " << rate(s.enAuto, s.enTotal) << ",\n"
            << "    \"en_broken_rate\": " << rate(s.enBroken, s.enTotal) << ",\n"
            << "    \"en_never_rate\": " << rate(s.enNever, s.enTotal) << ",\n"
            << "    \"en_tab_fixable_rate\": " << rate(s.enTabFix, s.enTotal) << ",\n"
            << "    \"pair_swallow_rate\": " << rate(s.pairSwallowed, s.pairTotal) << ",\n"
            << "    \"pair_swallow_examples\": " << list(s.pairExamples) << ",\n"
            << "    \"zh_false_positive_examples\": " << list(s.zhExamples) << ",\n"
            << "    \"en_broken_examples\": " << list(s.brokenExamples) << ",\n"
            << "    \"en_never_examples\": " << list(s.neverExamples) << "\n"
            << "  }" << (last ? "\n" : ",\n");
}

}  // namespace

int main(int argc, char** argv) {
  std::map<std::string, std::string> args;
  for (int i = 1; i + 1 < argc; i += 2) {
    args[argv[i]] = argv[i + 1];
  }
  for (const char* required : {"--dictionary", "--known", "--readings", "--corpus"}) {
    if (!args.count(required)) {
      std::cerr << "missing " << required << "\n";
      return 2;
    }
  }

  Lexicon dictionary;
  dictionary.addLines(ReadFile(args["--dictionary"]), 50);
  dictionary.finalize();
  Lexicon known;
  known.addLines(ReadFile(args["--known"]), 0);
  known.finalize();
  Lexicon legacyDictionary;
  if (args.count("--legacy-dictionary")) {
    std::istringstream in(ReadFile(args["--legacy-dictionary"]));
    std::string w;
    while (in >> w) {
      if (w.size() >= 3) legacyDictionary.add(ToLower(w), 50);
    }
    legacyDictionary.finalize();
  }

  std::set<std::string> readings;
  {
    std::istringstream in(ReadFile(args["--readings"]));
    std::string r;
    while (std::getline(in, r)) {
      if (!r.empty()) readings.insert(r);
    }
  }

  Context current;
  current.known = &known;
  current.dictionary = &dictionary;
  current.layout = Formosa::Mandarin::BopomofoKeyboardLayout::StandardLayout();
  current.readingExists = [&readings](const std::string& r) {
    return readings.count(r) > 0;
  };
  Context legacy = current;
  legacy.dictionary = args.count("--legacy-dictionary") ? &legacyDictionary : &dictionary;

  auto legacyDecide = [](const std::string& run, const Context& c) {
    return LegacyDecide(run, c);
  };
  auto currentDecide = [](const std::string& run, const Context& c) {
    return Decide(run, c);
  };
  auto currentContinue = [](const std::string& s, char n, const Context& c) {
    return CanContinue(s, n, c);
  };

  Stats legacyStats, currentStats;
  std::istringstream corpus(ReadFile(args["--corpus"]));
  std::string line;
  while (std::getline(corpus, line)) {
    std::istringstream fields(line);
    std::string kind, item, weightField;
    if (!std::getline(fields, kind, '\t') || !std::getline(fields, item, '\t')) {
      continue;
    }
    double weight = 1.0;
    if (std::getline(fields, weightField, '\t') && !weightField.empty() &&
        kind != "pair") {
      weight = std::stod(weightField);
    }
    if (kind == "pair") {
      // item = word; the syllable is in the third column.
      std::string syllableText = weightField;
      auto syllable = Formosa::Mandarin::BopomofoSyllable::FromComposedString(syllableText);
      std::string keys = current.layout->keySequenceFromSyllable(syllable);
      if (keys.empty()) continue;
      std::string word = ToLower(item);
      auto check = [&](Stats* stats, const Context& c, auto decide, auto canContinue) {
        // Only words that end up English on their own are relevant.
        if (SimulateEnglish(word, c, decide, canContinue) != EnOutcome::kAuto) return;
        stats->pairTotal += 1;
        if (canContinue(word, keys[0], c)) {
          stats->pairSwallowed += 1;
          Add(&stats->pairExamples, word + "+" + syllableText);
        }
      };
      check(&legacyStats, legacy, legacyDecide, LegacyCanContinue);
      check(&currentStats, current, currentDecide, currentContinue);
      continue;
    }
    if (kind == "zh") {
      auto syllable = Formosa::Mandarin::BopomofoSyllable::FromComposedString(item);
      std::string keys = current.layout->keySequenceFromSyllable(syllable);
      legacyStats.zhTotal += weight;
      currentStats.zhTotal += weight;
      if (SimulateZhFalsePositive(keys, legacy, legacyDecide)) {
        legacyStats.zhFalsePositive += weight;
        Add(&legacyStats.zhExamples, item + "=" + keys);
      }
      if (SimulateZhFalsePositive(keys, current, currentDecide)) {
        currentStats.zhFalsePositive += weight;
        Add(&currentStats.zhExamples, item + "=" + keys);
      }
    } else if (kind == "en") {
      std::string word = ToLower(item);
      bool tabFixable = false;
      if (auto c = BestCompletion(word, current); c.has_value()) {
        tabFixable = ToLower(*c) == word;
      }
      struct Run {
        Stats* stats;
        EnOutcome outcome;
        bool tab;
      };
      Run runs[] = {
          {&legacyStats, SimulateEnglish(word, legacy, legacyDecide, LegacyCanContinue), false},
          {&currentStats, SimulateEnglish(word, current, currentDecide, currentContinue), tabFixable},
      };
      for (auto& r : runs) {
        r.stats->enTotal += weight;
        switch (r.outcome) {
          case EnOutcome::kAuto:
            r.stats->enAuto += weight;
            break;
          case EnOutcome::kBroken:
            r.stats->enBroken += weight;
            Add(&r.stats->brokenExamples, word);
            break;
          case EnOutcome::kNever:
            r.stats->enNever += weight;
            if (r.tab) r.stats->enTabFix += weight;
            Add(&r.stats->neverExamples, word);
            break;
        }
      }
    }
  }

  std::cout << "{\n";
  PrintStats("legacy", legacyStats, false);
  PrintStats("current", currentStats, true);
  std::cout << "}\n";
  return 0;
}
