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

#include <algorithm>
#include <cctype>
#include <sstream>

namespace McBopomofo {
namespace SmartMixed {

namespace {

bool IsAlnum(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9');
}

bool HasVowel(std::string_view s) {
  for (char c : s) {
    switch (std::tolower(static_cast<unsigned char>(c))) {
      case 'a':
      case 'e':
      case 'i':
      case 'o':
      case 'u':
      case 'y':
        return true;
      default:
        break;
    }
  }
  return false;
}

bool StartsWith(const std::string& s, const std::string& prefix) {
  return s.size() >= prefix.size() &&
         s.compare(0, prefix.size(), prefix) == 0;
}

bool KnownContains(const Context& c, const std::string& lower) {
  return c.known != nullptr && c.known->contains(lower);
}
bool KnownHasPrefix(const Context& c, const std::string& lower) {
  return c.known != nullptr && c.known->hasPrefix(lower);
}
bool DictContains(const Context& c, const std::string& lower) {
  return c.dictionary != nullptr && c.dictionary->contains(lower);
}
bool DictHasProperPrefix(const Context& c, const std::string& lower) {
  return c.dictionary != nullptr && c.dictionary->hasProperPrefix(lower);
}

}  // namespace

std::string ToLower(std::string_view s) {
  std::string lower(s);
  std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return lower;
}

bool IsASCIIAlnum(std::string_view s) {
  if (s.empty()) {
    return false;
  }
  return std::all_of(s.begin(), s.end(), IsAlnum);
}

// MARK: - Lexicon

bool Lexicon::add(std::string_view word, int tier) {
  if (!IsASCIIAlnum(word)) {
    return false;
  }
  entries_.push_back(LexiconEntry{ToLower(word), std::string(word), tier});
  finalized_ = false;
  return true;
}

size_t Lexicon::addLines(std::string_view data, int defaultTier) {
  size_t accepted = 0;
  std::istringstream stream{std::string(data)};
  std::string line;
  while (std::getline(stream, line)) {
    std::istringstream fields(line);
    std::string word;
    if (!(fields >> word) || word[0] == '#') {
      continue;
    }
    int tier = defaultTier;
    std::string tierField;
    if (fields >> tierField) {
      try {
        tier = std::stoi(tierField);
      } catch (...) {
        tier = defaultTier;
      }
    }
    if (add(word, tier)) {
      ++accepted;
    }
  }
  return accepted;
}

void Lexicon::finalize() {
  if (finalized_) {
    return;
  }
  // stable_sort keeps insertion order among equal keys, so the first spelling
  // added survives a tie.
  std::stable_sort(entries_.begin(), entries_.end(),
                   [](const LexiconEntry& a, const LexiconEntry& b) {
                     if (a.key != b.key) return a.key < b.key;
                     return a.tier < b.tier;
                   });
  entries_.erase(std::unique(entries_.begin(), entries_.end(),
                             [](const LexiconEntry& a, const LexiconEntry& b) {
                               return a.key == b.key;
                             }),
                 entries_.end());
  entries_.shrink_to_fit();
  finalized_ = true;
}

std::vector<LexiconEntry>::const_iterator Lexicon::lowerBound(
    const std::string& key) const {
  return std::lower_bound(
      entries_.begin(), entries_.end(), key,
      [](const LexiconEntry& e, const std::string& k) { return e.key < k; });
}

bool Lexicon::contains(std::string_view word) const {
  return find(word).has_value();
}

std::optional<LexiconEntry> Lexicon::find(std::string_view word) const {
  if (word.empty() || !finalized_) {
    return std::nullopt;
  }
  std::string key = ToLower(word);
  auto it = lowerBound(key);
  if (it != entries_.end() && it->key == key) {
    return *it;
  }
  return std::nullopt;
}

bool Lexicon::hasPrefix(std::string_view prefix) const {
  if (prefix.empty() || !finalized_) {
    return false;
  }
  std::string key = ToLower(prefix);
  auto it = lowerBound(key);
  return it != entries_.end() && StartsWith(it->key, key);
}

bool Lexicon::hasProperPrefix(std::string_view prefix) const {
  if (prefix.empty() || !finalized_) {
    return false;
  }
  std::string key = ToLower(prefix);
  auto it = lowerBound(key);
  if (it != entries_.end() && it->key == key) {
    ++it;
  }
  return it != entries_.end() && StartsWith(it->key, key);
}

std::vector<LexiconEntry> Lexicon::completions(std::string_view prefix,
                                               size_t limit) const {
  std::vector<LexiconEntry> result;
  if (prefix.empty() || !finalized_ || limit == 0) {
    return result;
  }
  // Short prefixes can match thousands of words; looking at the first few
  // thousand alphabetically is enough to find common ones and bounds the cost
  // of a keystroke.
  constexpr size_t kScanLimit = 4096;
  std::string key = ToLower(prefix);
  size_t scanned = 0;
  for (auto it = lowerBound(key);
       it != entries_.end() && StartsWith(it->key, key) && scanned < kScanLimit;
       ++it, ++scanned) {
    result.push_back(*it);
  }
  std::stable_sort(result.begin(), result.end(),
                   [](const LexiconEntry& a, const LexiconEntry& b) {
                     if (a.tier != b.tier) return a.tier < b.tier;
                     if (a.key.size() != b.key.size())
                       return a.key.size() < b.key.size();
                     return a.key < b.key;
                   });
  if (result.size() > limit) {
    result.resize(limit);
  }
  return result;
}

// MARK: - LearnedChoices

void LearnedChoices::recordASCII(std::string_view word) {
  if (!IsASCIIAlnum(word)) return;
  std::string key = ToLower(word);
  bopomofo_.erase(key);
  ascii_.insert(key);
}

void LearnedChoices::recordBopomofo(std::string_view run) {
  if (!IsASCIIAlnum(run)) return;
  std::string key = ToLower(run);
  ascii_.erase(key);
  bopomofo_.insert(key);
}

bool LearnedChoices::prefersASCII(std::string_view word) const {
  return ascii_.count(ToLower(word)) > 0;
}

bool LearnedChoices::prefersBopomofo(std::string_view run) const {
  return bopomofo_.count(ToLower(run)) > 0;
}

void LearnedChoices::clear() {
  ascii_.clear();
  bopomofo_.clear();
}

void LearnedChoices::load(std::string_view data) {
  clear();
  std::istringstream stream{std::string(data)};
  std::string line;
  while (std::getline(stream, line)) {
    while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) {
      line.pop_back();
    }
    if (line.size() < 2) continue;
    std::string_view body(line.c_str() + 1, line.size() - 1);
    if (line[0] == '+') {
      recordASCII(body);
    } else if (line[0] == '-') {
      recordBopomofo(body);
    }
  }
}

std::string LearnedChoices::serialize() const {
  std::string out =
      "# Broccoli SmartInput: smart mixed input choices learned on this Mac.\n"
      "# +word = accept as English, -keys = keep as Bopomofo.\n";
  for (const auto& w : ascii_) out += "+" + w + "\n";
  for (const auto& r : bopomofo_) out += "-" + r + "\n";
  return out;
}

// MARK: - Classifier

RunAnalysis AnalyzeRun(std::string_view run, const Context& context) {
  RunAnalysis analysis;
  const auto* layout = context.layout != nullptr
                           ? context.layout
                           : Formosa::Mandarin::BopomofoKeyboardLayout::
                                 StandardLayout();
  Formosa::Mandarin::BopomofoReadingBuffer buffer(layout);
  for (char c : run) {
    size_t before =
        layout->keySequenceFromSyllable(buffer.syllable()).size();
    if (!buffer.combineKey(c)) {
      analysis.clean = false;
      analysis.overwrote = true;
      continue;
    }
    size_t after = layout->keySequenceFromSyllable(buffer.syllable()).size();
    if (after <= before) {
      analysis.overwrote = true;
    }
  }
  std::string normalized = layout->keySequenceFromSyllable(buffer.syllable());
  analysis.clean = !analysis.overwrote && normalized == std::string(run);
  analysis.composed = buffer.syllable().composedString();
  if (context.readingExists) {
    analysis.readingExists =
        !analysis.composed.empty() && context.readingExists(analysis.composed);
  }
  return analysis;
}

Decision LegacyDecide(std::string_view run, const Context& context) {
  std::string lower = ToLower(run);
  size_t len = lower.size();
  // Mirrors KeyHandler's _smartMixedPendingKeyRunShouldConvertToASCII as of
  // v1.2.1, with /usr/share/dict/words replaced by `dictionary`.
  if (len >= 3 && KnownContains(context, lower)) {
    return Decision::kConvertToASCII;
  }
  bool dictPrefix = len >= 2 && DictHasProperPrefix(context, lower);
  if (dictPrefix && len < 6) {
    return Decision::kKeepBopomofo;
  }
  if (len >= 6 && DictContains(context, lower)) {
    return Decision::kConvertToASCII;
  }
  if (dictPrefix) {
    return Decision::kKeepBopomofo;
  }
  if (KnownHasPrefix(context, lower)) {
    return Decision::kKeepBopomofo;
  }
  if (len >= 6 && HasVowel(lower)) {
    return Decision::kConvertToASCII;
  }
  return Decision::kKeepBopomofo;
}

Decision Decide(std::string_view run, const Context& context) {
  std::string lower = ToLower(run);
  size_t len = lower.size();
  if (len < 2 || !IsASCIIAlnum(lower)) {
    return Decision::kKeepBopomofo;
  }

  // What the user taught us wins over every heuristic.
  if (context.learned != nullptr) {
    if (context.learned->prefersBopomofo(lower)) {
      return Decision::kKeepBopomofo;
    }
    if (context.learned->prefersASCII(lower)) {
      return Decision::kConvertToASCII;
    }
  }

  // The whitelist is an explicit list of English words, as before.
  if (len >= 3 && KnownContains(context, lower)) {
    return Decision::kConvertToASCII;
  }

  // Hanyu Pinyin keys are letters by design; letter patterns tell nothing.
  if (context.layout ==
      Formosa::Mandarin::BopomofoKeyboardLayout::HanyuPinyinLayout()) {
    return LegacyDecide(run, context);
  }

  RunAnalysis analysis = AnalyzeRun(lower, context);

  // Still a valid Chinese syllable: keep Bopomofo. If it was English after
  // all, Tab accepts the suggestion (see BestCompletion).
  if (analysis.clean && analysis.readingExists) {
    return Decision::kKeepBopomofo;
  }

  bool knownPrefix = KnownHasPrefix(context, lower);
  bool dictWord = DictContains(context, lower);
  bool dictPrefix = DictHasProperPrefix(context, lower);
  bool englishShaped = dictWord || dictPrefix || knownPrefix;

  if (analysis.overwrote) {
    // A key replaced an earlier component: strong evidence the user is not
    // composing a syllable.
    if (len >= 3 && englishShaped) {
      return Decision::kConvertToASCII;
    }
    if (len >= 4 && HasVowel(lower)) {
      return Decision::kConvertToASCII;
    }
    return Decision::kKeepBopomofo;
  }

  // Keys out of canonical order, or a syllable that does not exist: weaker
  // evidence, so ask for more letters before converting.
  if (len >= 3 && dictWord) {
    return Decision::kConvertToASCII;
  }
  if (len >= 4 && englishShaped) {
    return Decision::kConvertToASCII;
  }
  if (len >= 6 && HasVowel(lower)) {
    return Decision::kConvertToASCII;
  }
  return Decision::kKeepBopomofo;
}

bool CanContinue(std::string_view sequence, char next, const Context& context) {
  if (sequence.empty() || !IsAlnum(next)) {
    return false;
  }
  std::string candidate = std::string(sequence) + next;
  std::string lower = ToLower(candidate);
  if (KnownHasPrefix(context, lower)) {
    return true;
  }
  if (context.dictionary != nullptr) {
    if (context.dictionary->contains(ToLower(sequence))) {
      // The word is already complete ("achieve"). Typing straight on into
      // Chinese is common, so only keep going toward a common word
      // ("achieved"), not a rare one ("achiever" + ㄐ...).
      auto best = context.dictionary->completions(lower, 1);
      if (!best.empty() && best[0].tier <= kCommonTier) {
        return true;
      }
    } else if (DictHasProperPrefix(context, lower) || DictContains(context, lower)) {
      return true;
    }
  }
  if (context.learned != nullptr && context.learned->prefersASCII(lower)) {
    return true;
  }

  bool uppercaseAcronym = true;
  bool hasDigit = false;
  for (char c : sequence) {
    unsigned char u = static_cast<unsigned char>(c);
    if (std::isdigit(u)) hasDigit = true;
    if (std::isalpha(u) && !std::isupper(u)) uppercaseAcronym = false;
  }
  if (std::isdigit(static_cast<unsigned char>(next))) {
    return hasDigit || uppercaseAcronym;
  }
  return uppercaseAcronym && std::isupper(static_cast<unsigned char>(next));
}

namespace {
// Whitelists are often typed in lowercase ("github"); when the dictionary
// knows a proper casing ("GitHub"), use that.
std::string PreferredCasing(const LexiconEntry& entry, const Context& context) {
  bool allLower = std::none_of(entry.word.begin(), entry.word.end(), [](char c) {
    return std::isupper(static_cast<unsigned char>(c));
  });
  if (allLower && context.dictionary != nullptr) {
    if (auto cased = context.dictionary->find(entry.key); cased.has_value()) {
      return cased->word;
    }
  }
  return entry.word;
}
}  // namespace

std::optional<std::string> BestCompletion(std::string_view prefix,
                                          const Context& context) {
  if (prefix.size() < 2 || !IsASCIIAlnum(prefix)) {
    return std::nullopt;
  }
  std::string key = ToLower(prefix);

  struct Found {
    std::optional<LexiconEntry> exact;
    std::optional<LexiconEntry> longer;  // most common, then shortest
  };
  auto search = [&key](const Lexicon* lexicon) {
    Found found;
    if (lexicon == nullptr || lexicon->empty()) {
      return found;
    }
    for (const auto& e : lexicon->completions(key, 16)) {
      if (e.key == key) {
        found.exact = e;
      } else if (!found.longer.has_value()) {
        found.longer = e;
      }
    }
    return found;
  };
  Found known = search(context.known);
  Found dictionary = search(context.dictionary);

  // What was typed is a word: keep it. Only an uncommon typed word gives way
  // to a more common longer one. Tiers below kCommonTier mark curated terms
  // (casing), not frequency, so "google" never replaces "go".
  if (known.exact.has_value()) {
    return PreferredCasing(*known.exact, context);
  }
  if (dictionary.exact.has_value()) {
    if (dictionary.exact->tier > kCommonTier && dictionary.longer.has_value() &&
        dictionary.longer->tier < dictionary.exact->tier) {
      return PreferredCasing(*dictionary.longer, context);
    }
    return PreferredCasing(*dictionary.exact, context);
  }
  if (known.longer.has_value()) {
    return PreferredCasing(*known.longer, context);
  }
  if (dictionary.longer.has_value()) {
    return PreferredCasing(*dictionary.longer, context);
  }
  if (context.learned != nullptr && context.learned->prefersASCII(key)) {
    return std::string(prefix);
  }
  return std::nullopt;
}

}  // namespace SmartMixed
}  // namespace McBopomofo
