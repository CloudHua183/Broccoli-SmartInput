# Broccoli SmartInput Private Dictionary Sync

This folder documents dictionary sync for Broccoli SmartInput.

The real dictionary files are private and must not be committed to this public
GitHub repo. Store them in Google Drive and keep only example files here.

## Files

- `smart-mixed-ascii-words.example.txt`: example English/product-name allowlist.
- `data.example.txt`: example McBopomofo user phrase dictionary.
- `patch-source.example.json`: local config template for Google Drive download URLs.

## Private Files In Google Drive

Create these two private Google Drive files:

- `smart-mixed-ascii-words.txt`
- `data.txt`

Set sharing to "anyone with the link" only if link-based access is acceptable.
That is not strict privacy: anyone with the URL can read the files. For stronger
privacy, restrict access to specific Google accounts, but automatic sync then
needs OAuth instead of simple download URLs.

## Local Config

On every Mac, create:

```text
~/Library/Application Support/McBopomofo/patch-source.json
```

Use direct Google Drive download URLs:

```json
{
  "smartMixedASCIIWordsURL": "https://drive.google.com/uc?export=download&id=GOOGLE_FILE_ID_FOR_SMART_MIXED_ASCII_WORDS",
  "userPhrasesURL": "https://drive.google.com/uc?export=download&id=GOOGLE_FILE_ID_FOR_DATA_TXT"
}
```

## Sync On Another Mac

From the installed input method:

```bash
/Users/$USER/Library/Input\ Methods/McBopomofo.app/Contents/MacOS/McBopomofo patch sync
```

Or use the input method menu item:

```text
同步雲端詞庫
```

The sync command downloads the two URLs from `patch-source.json`, validates both
files, backs up local files, and writes them into:

```text
~/Library/Application Support/McBopomofo/data.txt
~/Library/Application Support/McBopomofo/smart-mixed-ascii-words.txt
```
