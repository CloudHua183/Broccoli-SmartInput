# Broccoli SmartInput Shared Dictionary

This folder is the public GitHub source for dictionaries shared across Broccoli SmartInput installs.

## Files

- `smart-mixed-ascii-words.txt`: shared English/product-name allowlist for smart mixed input.
- `data.txt`: shared McBopomofo user phrase dictionary.

## Sync On Another Mac

From the installed input method:

```bash
/Users/$USER/Library/Input\ Methods/McBopomofo.app/Contents/MacOS/McBopomofo patch sync
```

Or use the input method menu item:

```text
同步 GitHub 詞庫
```

The sync command downloads this folder from GitHub, validates both files, backs up local files, and writes them into:

```text
~/Library/Application Support/McBopomofo/data.txt
~/Library/Application Support/McBopomofo/smart-mixed-ascii-words.txt
```
