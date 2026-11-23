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

// Smart mixed (Chinese/English) input: the pieces that decide whether a run of
// keys typed on a Bopomofo keyboard was meant as English.
//
// Everything here is plain C++ with no Cocoa dependency, so it can be unit
// tested with the engine's ctest suite and driven by the offline evaluation
// tool (Tools/smart_mixed_eval). KeyHandler.mm only adapts it.

#ifndef SRC_ENGINE_SMARTMIXED_H_
#define SRC_ENGINE_SMARTMIXED_H_

#include <cstddef>
#include <functional>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "Mandarin/Mandarin.h"

namespace McBopomofo {
namespace SmartMixed {

// Lower tier means more common. Whitelist words and words the user added are
// tier 0; the bundled dictionary uses its source frequency band (35 = most
// common in SCOWL/ESDB terms, larger = rarer).
constexpr int kWhitelistTier = 0;
constexpr int kDefaultTier = 50;
// Words at or below this tier count as common English (ESDB size 35 and the
// project's own term list).
constexpr int kCommonTier = 35;

struct LexiconEntry {
  std::string key;   // lowercase, used for lookup
  std::string word;  // canonical spelling, e.g. "GitHub", "API"
  int tier = kDefaultTier;
};

// An immutable-after-finalize, sorted word list with O(log n) exact and prefix
// lookups. Replaces the per-keystroke file scans and the NSString prefix set.
class Lexicon {
 public:
  // Adds a word. Only ASCII letters and digits are accepted; anything else is
  // ignored and false is returned.
  bool add(std::string_view word, int tier);

  // Parses "word" or "word<whitespace>tier" lines. '#' starts a comment line.
  // Returns the number of words accepted. Call finalize() afterwards.
  size_t addLines(std::string_view data, int defaultTier);

  // Sorts and de-duplicates. When a key appears twice the lowest tier wins;
  // on a tie, the spelling added first wins.
  void finalize();

  bool contains(std::string_view word) const;
  // True if some entry starts with `prefix` (an exact match counts).
  bool hasPrefix(std::string_view prefix) const;
  // True if some entry starts with `prefix` and is longer than it.
  bool hasProperPrefix(std::string_view prefix) const;
  std::optional<LexiconEntry> find(std::string_view word) const;
  // Entries starting with `prefix`, most common first, then shortest.
  std::vector<LexiconEntry> completions(std::string_view prefix,
                                        size_t limit) const;

  size_t size() const { return entries_.size(); }
  bool empty() const { return entries_.empty(); }

 private:
  std::vector<LexiconEntry>::const_iterator lowerBound(
      const std::string& key) const;

  std::vector<LexiconEntry> entries_;
  bool finalized_ = true;
};

// What the user taught the input method about specific runs: words accepted
// as English with Tab, and runs that were turned back into Bopomofo.
class LearnedChoices {
 public:
  void recordASCII(std::string_view word);
  void recordBopomofo(std::string_view run);
  bool prefersASCII(std::string_view word) const;
  bool prefersBopomofo(std::string_view run) const;
  void clear();

  // Format: one entry per line, "+word" for English, "-run" for Bopomofo.
  void load(std::string_view data);
  std::string serialize() const;

  bool empty() const { return ascii_.empty() && bopomofo_.empty(); }

 private:
  std::set<std::string> ascii_;
  std::set<std::string> bopomofo_;
};

struct Context {
  // Whitelist + user ASCII phrases. May be null.
  const Lexicon* known = nullptr;
  // The bundled English dictionary. May be null or empty while loading.
  const Lexicon* dictionary = nullptr;
  const LearnedChoices* learned = nullptr;
  const Formosa::Mandarin::BopomofoKeyboardLayout* layout = nullptr;
  // Whether a composed Bopomofo syllable (without tone) exists with any tone
  // in the language model. When unset every syllable is assumed to exist.
  std::function<bool(const std::string& composedReading)> readingExists;
};

enum class Decision { kKeepBopomofo, kConvertToASCII };

// How a run of keys behaves when fed into a Bopomofo reading buffer.
struct RunAnalysis {
  // The keys compose into a syllable in the order typed, with no key
  // replacing an earlier one.
  bool clean = true;
  // At least one key replaced a component an earlier key had set (e.g. two
  // consonants). This almost never happens when typing Chinese on purpose.
  bool overwrote = false;
  // The composed syllable exists in the language model (with some tone).
  bool readingExists = true;
  std::string composed;
};

RunAnalysis AnalyzeRun(std::string_view run, const Context& context);

// The rule cascade that shipped up to v1.2.1, kept as the evaluation baseline.
Decision LegacyDecide(std::string_view run, const Context& context);

// The evidence-based classifier (A3). `run` holds the letter keys typed since
// the reading buffer was last empty.
Decision Decide(std::string_view run, const Context& context);

// Whether an ASCII sequence already converted can take one more character.
bool CanContinue(std::string_view sequence, char next, const Context& context);

// The text Tab should produce for `prefix`, or nothing when no English word
// fits. Looks in the whitelist, then the dictionary, then learned words. A
// complete word is kept unless a longer completion is more common; canonical
// casing is kept ("github" -> "GitHub").
std::optional<std::string> BestCompletion(std::string_view prefix,
                                          const Context& context);

std::string ToLower(std::string_view s);
bool IsASCIIAlnum(std::string_view s);

}  // namespace SmartMixed
}  // namespace McBopomofo

#endif  // SRC_ENGINE_SMARTMIXED_H_
