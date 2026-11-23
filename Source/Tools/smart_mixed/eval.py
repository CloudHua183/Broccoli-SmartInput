#!/usr/bin/env python3
"""Smart mixed input evaluation (A8): legacy rules vs. the current classifier.

Builds two corpora from the repository's own data and runs the SmartMixedEval
binary (built with the engine: cmake -DENABLE_TEST=ON) on each:

  zh  every toneless syllable in Source/Data/data.txt, weighted by how often
      single characters with that reading occur, typed on the standard
      (Dachen) layout. A conversion here is a false positive.
  en  common English words (lexicon tier <= --max-tier), lowercase letters
      only, split into all lengths and short words (2-4 letters).

Example (from the repository root, after building the engine):
  python3 Source/Tools/smart_mixed/eval.py \\
      --binary build/Engine/SmartMixedEval \\
      --legacy-dictionary /usr/share/dict/words \\
      --report Source/Tools/smart_mixed/latest-report.md
"""

import argparse
import collections
import json
import os
import subprocess
import tempfile

TONES = "ˊˇˋ˙"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DATA = os.path.join(ROOT, "Source", "Data")


def strip_tone(syllable):
    return "".join(ch for ch in syllable if ch not in TONES)


def load_readings(data_path):
    readings = set()
    weights = collections.Counter()
    with open(data_path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#"):
                continue
            fields = line.split()
            if len(fields) < 3 or fields[0].startswith("_"):
                continue
            reading, _value, score = fields[0], fields[1], fields[2]
            for syllable in reading.split("-"):
                toneless = strip_tone(syllable)
                if toneless:
                    readings.add(toneless)
            if "-" not in reading:
                try:
                    weights[strip_tone(reading)] += 10 ** float(score)
                except ValueError:
                    pass
    return readings, weights


def load_english(lexicon_path, max_tier):
    words = []
    with open(lexicon_path, encoding="utf-8") as f:
        for line in f:
            fields = line.split()
            if len(fields) != 2 or fields[0].startswith("#"):
                continue
            word, tier = fields[0], int(fields[1])
            if tier <= max_tier and word.isalpha() and word.isascii():
                words.append(word.lower())
    return sorted(set(words))


def run(binary, args, corpus_lines):
    with tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False,
                                     encoding="utf-8") as corpus:
        corpus.write("\n".join(corpus_lines) + "\n")
        corpus_path = corpus.name
    try:
        cmd = [binary, "--corpus", corpus_path] + args
        out = subprocess.run(cmd, check=True, capture_output=True, text=True)
        return json.loads(out.stdout)
    finally:
        os.unlink(corpus_path)


def pct(x):
    return f"{100 * x:.1f}%"


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--binary", required=True)
    p.add_argument("--data", default=os.path.join(DATA, "data.txt"))
    p.add_argument("--dictionary",
                   default=os.path.join(DATA, "smart-mixed-english-lexicon.txt"))
    p.add_argument("--known", default=os.path.join(DATA, "smart-mixed-ascii-words.txt"))
    p.add_argument("--legacy-dictionary",
                   help="word list the legacy rules used (/usr/share/dict/words)")
    p.add_argument("--max-tier", type=int, default=35)
    p.add_argument("--report", help="write a Markdown report here")
    a = p.parse_args()

    readings, weights = load_readings(a.data)
    english = load_english(a.dictionary, a.max_tier)

    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False,
                                     encoding="utf-8") as rf:
        rf.write("\n".join(sorted(readings)) + "\n")
        readings_path = rf.name
    common = ["--dictionary", a.dictionary, "--known", a.known,
              "--readings", readings_path]
    if a.legacy_dictionary:
        common += ["--legacy-dictionary", a.legacy_dictionary]

    try:
        zh_lines = [f"zh\t{r}\t{weights.get(r, 0) or 1e-9:.12g}" for r in sorted(readings)]
        zh_flat = [f"zh\t{r}\t1" for r in sorted(readings)]
        en_all = [f"en\t{w}\t1" for w in english]
        en_short = [f"en\t{w}\t1" for w in english if 2 <= len(w) <= 4]
        # Word typed straight into a common syllable, e.g. "meeting" + 開.
        top_syllables = [r for r, _ in weights.most_common(60)]
        pairs = [f"pair\t{w}\t{r}" for w in english[::25] for r in top_syllables]
        results = {
            "zh_weighted": run(a.binary, common, zh_lines),
            "zh_distinct": run(a.binary, common, zh_flat),
            "en_all": run(a.binary, common, en_all),
            "en_short": run(a.binary, common, en_short),
            "pairs": run(a.binary, common, pairs),
        }
    finally:
        os.unlink(readings_path)

    rows = []
    for name in ("legacy", "current"):
        rows.append(
            f"| {name} | {pct(results['zh_weighted'][name]['zh_false_positive_rate'])} "
            f"| {pct(results['zh_distinct'][name]['zh_false_positive_rate'])} "
            f"| {pct(results['en_all'][name]['en_auto_rate'])} "
            f"| {pct(results['en_all'][name]['en_broken_rate'])} "
            f"| {pct(results['en_short'][name]['en_auto_rate'])} "
            f"| {pct(results['en_all'][name]['en_tab_fixable_rate'])} "
            f"| {pct(results['pairs'][name]['pair_swallow_rate'])} |")
    report = [
        "# Smart mixed input evaluation",
        "",
        f"- Syllables: {len(readings)}; English words (tier <= {a.max_tier}): "
        f"{len(english)}, of which 2-4 letters: {len(en_short)}",
        f"- Legacy dictionary: {a.legacy_dictionary or '(bundled lexicon)'}",
        "",
        "| rules | zh false positives (usage-weighted) | zh false positives (distinct) "
        "| en auto | en broken mid-word | en auto (2-4 letters) | en left for Tab, Tab fixes | word+syllable: first key swallowed |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
        *rows,
        "",
        "## Examples (current rules)",
        "",
        "- zh false positives: " + ", ".join(results["zh_distinct"]["current"]["zh_false_positive_examples"][:20]),
        "- en broken mid-word: " + ", ".join(results["en_all"]["current"]["en_broken_examples"][:20]),
        "- en left for Tab: " + ", ".join(results["en_all"]["current"]["en_never_examples"][:20]),
        "- first key swallowed: " + ", ".join(results["pairs"]["current"]["pair_swallow_examples"][:20]),
        "",
        "## Examples (legacy rules)",
        "",
        "- zh false positives: " + ", ".join(results["zh_distinct"]["legacy"]["zh_false_positive_examples"][:20]),
        "- en broken mid-word: " + ", ".join(results["en_all"]["legacy"]["en_broken_examples"][:20]),
        "",
    ]
    text = "\n".join(report)
    print(text)
    if a.report:
        with open(a.report, "w", encoding="utf-8") as f:
            f.write(text)


if __name__ == "__main__":
    main()
