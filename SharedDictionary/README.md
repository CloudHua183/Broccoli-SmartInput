# Broccoli SmartInput Private Dictionary Sync

This folder documents dictionary sync for Broccoli SmartInput.

The real dictionary files are private and must not be committed to this public
GitHub repo. Store them in Google Drive and keep only example files here.

## Files

- `smart-mixed-ascii-words.example.txt`: example English/product-name allowlist.
- `data.example.txt`: example McBopomofo user phrase dictionary.
- `patch-source.example.json`: local config template for Google Drive download URLs and optional Apps Script writeback URLs.
- `GoogleAppsScriptWebApp.gs`: Apps Script web app template that writes the two cloud dictionary files back into Drive.

## Private Files In Google Drive

Create these two private Google Drive files:

- `smart-mixed-ascii-words.txt`
- `data.txt`

Set sharing to "anyone with the link" only if link-based access is acceptable.
That is not strict privacy: anyone with the URL can read the files. For stronger
privacy, restrict access to specific Google accounts, but automatic sync then
needs OAuth instead of simple download URLs.

If you want true multi-computer writeback, provide upload URLs as well. The app
downloads the latest cloud copy, merges local changes, uploads the merged
result, and then refreshes the local files. The recommended writeback endpoint
is a Google Apps Script Web App, because one deployment can update both files
by switching the `target` query parameter.

## Google Apps Script Web App

Create a script project, paste `GoogleAppsScriptWebApp.gs`, and set these
Script Properties:

- `SMART_MIXED_ASCII_WORDS_FILE_ID`
- `USER_PHRASES_FILE_ID`

Deploy the script as a Web App, then use the same deployment URL with:

- `?target=smart` for `smart-mixed-ascii-words.txt`
- `?target=user` for `data.txt`

The script validates the uploaded text, takes a script lock while writing, and
updates the matching Drive file in place.

## v1.0.8 Deployment Notes

The current deployed Web App URL is:

```text
https://script.google.com/macros/s/AKfycbyfr58LltoT7nAMR6IVoP6BjqPCc1Q3SNgIH1gsdOzwn7EW14uquQv3a4QB2RGxSE5Uog/exec
```

Current Script Properties:

```text
SMART_MIXED_ASCII_WORDS_FILE_ID=1PaH_srJBr0tcjooqaw1QeMCm4DnOJlQw
USER_PHRASES_FILE_ID=1Gp48qRsqXBXxtUdoPcTL-i5N3RBC2w5d
```

## Local Config

On every Mac, create:

```text
~/Library/Application Support/McBopomofo/patch-source.json
```

Use direct Google Drive download URLs:

```json
{
  "smartMixedASCIIWordsURL": "https://drive.google.com/uc?export=download&id=GOOGLE_FILE_ID_FOR_SMART_MIXED_ASCII_WORDS",
  "userPhrasesURL": "https://drive.google.com/uc?export=download&id=GOOGLE_FILE_ID_FOR_DATA_TXT",
  "smartMixedASCIIWordsUploadURL": "https://script.google.com/macros/s/DEPLOYMENT_ID/exec?target=smart",
  "userPhrasesUploadURL": "https://script.google.com/macros/s/DEPLOYMENT_ID/exec?target=user"
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
files, merges them with local changes, optionally uploads the merged result to
the Apps Script writeback URLs, backs up local files, and writes them into:

```text
~/Library/Application Support/McBopomofo/data.txt
~/Library/Application Support/McBopomofo/smart-mixed-ascii-words.txt
```

If upload URLs are omitted, sync behaves as read-only download plus local merge.
