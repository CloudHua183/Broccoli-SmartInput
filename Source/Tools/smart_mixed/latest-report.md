# Smart mixed input evaluation

- Syllables: 429; English words (tier <= 35): 37613, of which 2-4 letters: 2459
- Legacy dictionary: macOS /usr/share/dict/words (web2, as shipped up to v1.2.1)
- Generated: 2026-11-22

| rules | zh false positives (usage-weighted) | zh false positives (distinct) | en auto | en broken mid-word | en auto (2-4 letters) | en left for Tab, Tab fixes | word+syllable: first key swallowed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| legacy | 0.0% | 0.0% | 36.4% | 46.8% | 0.1% | 0.0% | 0.0% |
| current | 0.0% | 0.0% | 99.8% | 0.0% | 96.6% | 0.2% | 0.9% |

## Examples (current rules)

- zh false positives: 
- en broken mid-word: 
- en left for Tab: ad, ah, ai, an, ar, as, at, av, ax, bd, be, bv, by, co, cs, cv, dc, dm, do, eh
- first key swallowed: achieve+ㄩ, achieve+ㄩㄢ, achieve+ㄎㄜ, advise+ㄎㄜ, affix+ㄍㄜ, affix+ㄍㄨㄛ, affix+ㄍㄨㄥ, amount+ㄍㄜ, amount+ㄍㄨㄛ, amount+ㄍㄨㄥ, archer+ㄗㄞ, archer+ㄗ, archer+ㄗㄨㄛ, auditor+ㄗㄞ, auditor+ㄗ, auditor+ㄗㄨㄛ, authenticate+ㄎㄜ, betray+ㄍㄜ, betray+ㄇㄣ, betray+ㄍㄨㄛ

## Examples (legacy rules)

- zh false positives: 
- en broken mid-word: abandoned, abandoning, abandonment, abandons, abating, abbreviated, abbreviates, abbreviating, abbreviations, abdicated, abdicates, abdicating, abdications, abdomens, abducted, abducting, abducts, aberrations, abetted, abetting
