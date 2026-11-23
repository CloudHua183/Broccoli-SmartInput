# Smart mixed input tools

Offline tools for the smart mixed (Chinese/English) classifier in
`Source/Engine/SmartMixed.{h,cpp}`. Nothing here ships in the app.

## Rebuild the English lexicon (A2)

`Source/Data/smart-mixed-english-lexicon.txt` is generated. To change it, edit
`Source/Data/smart-mixed-tech-terms.txt` or the size band, then:

```bash
git clone --depth 1 https://github.com/en-wl/wordlist.git /tmp/wordlist
python3 Source/Tools/smart_mixed/build_english_lexicon.py \
    --scowl /tmp/wordlist/data/scowl-pre.txt \
    --terms Source/Data/smart-mixed-tech-terms.txt \
    --output Source/Data/smart-mixed-english-lexicon.txt
```

The script only reads `scowl-pre.txt` as text. Sizes above 80 carry extra
copyright terms (UKACD); the default `--max-size 60` stays well below that.
Keep the ESDB notice at the top of the generated file.

## Evaluate the classifier (A8)

```bash
cmake -S Source -B build -DENABLE_TEST=ON
cmake --build build --target SmartMixedEval
python3 Source/Tools/smart_mixed/eval.py \
    --binary build/Engine/SmartMixedEval \
    --legacy-dictionary /usr/share/dict/words \
    --report Source/Tools/smart_mixed/latest-report.md
```

Compares the v1.2.1 rules with the current classifier on every syllable in
`data.txt` (false positives), common English words (auto-detected, broken
mid-word, left for Tab) and English words typed straight into a Chinese
syllable (first key swallowed). Run it before and after any change to
`SmartMixed.cpp`; do not merge a change that makes a column worse without a
reason. `latest-report.md` holds the last run.
