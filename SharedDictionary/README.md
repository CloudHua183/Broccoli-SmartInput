# Broccoli SmartInput Private Dictionary Sync

> **Superseded. Do not deploy the Apps Script web app for a new setup.**
>
> Multi-machine dictionary sync now runs through **iCloud Drive**, not through
> a Google Apps Script web app. Run `script/migrate_to_icloud_dictionary.sh`
> on each Mac: it copies the dictionaries into
> `~/Library/Mobile Documents/com~apple~CloudDocs/BroccoliSmartInput`, points
> `UseCustomUserPhraseLocation` / `CustomUserPhraseLocation` at that folder,
> and retires `patch-source.json`. The input method already watches its
> dictionary folder with FSEvents, so a file synced in by iCloud is reloaded
> automatically. No application code is involved.
>
> **Why the change.** The input method cannot authenticate to Google, so the
> web app deployment had to allow anonymous access. That made the deployment
> URL alone sufficient to overwrite either dictionary, since
> `DriveApp.setContent()` replaces the whole file, and the fork's sync merges
> the remote copy into the local one and writes it back, so a single poisoned
> upload would spread to every machine and persist. Letting iCloud Drive do
> the syncing removes the network-facing surface entirely: the files are
> reachable only from a Mac signed in to the owner's Apple Account.
>
> The rest of this document describes the retired Apps Script setup. It is
> kept for reference and for anyone who still has the old deployment running
> and needs to shut it down. If you do keep it, the `SHARED_SECRET` gate
> below is mandatory.

This folder documents dictionary sync for Broccoli SmartInput.

The real dictionary files are private and must not be committed to this public
GitHub repo. Keep only example files here.

## Retiring an existing Apps Script deployment

1. Apps Script editor, Deploy, Manage deployments: **archive** the old
   deployment. Creating a new deployment does not disable the old URL.
2. Google Drive: set the two dictionary files back to private. Their file ids
   were published in this repository, so consider making fresh copies to get
   new ids.
3. Delete or rename `~/Library/Application Support/McBopomofo/patch-source.json`
   on every machine. The migration script does this for you.

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

## Deployment Notes

Keep the real deployment URL and Drive file IDs out of this repository.
Record them only in the local, git-ignored `SharedDictionary/patch-source.json`.
The Web App URL has this shape:

```text
https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec
```

Script Properties have this shape:

```text
SMART_MIXED_ASCII_WORDS_FILE_ID=GOOGLE_DRIVE_FILE_ID_FOR_SMART_MIXED_ASCII_WORDS
USER_PHRASES_FILE_ID=GOOGLE_DRIVE_FILE_ID_FOR_DATA_TXT
SHARED_SECRET=A_LONG_RANDOM_STRING
```

## Why the shared secret is required

The deployment has to allow anonymous access, because the input method uploads
without an OAuth token. That means anyone who learns the deployment URL can
reach `doPost`, and `DriveApp.setContent()` replaces the whole dictionary
rather than appending to it. The `SHARED_SECRET` script property is what
actually gates writes.

Apps Script web apps cannot read custom HTTP headers, so the secret travels as
a query parameter on the upload URL in the local, git-ignored
`patch-source.json`. Generate one with:

```bash
openssl rand -hex 32
```

`doPost` fails closed: if `SHARED_SECRET` is not set on the script, every
upload is rejected instead of being silently accepted.

Treat the deployment URL, the Drive file IDs and the secret as credentials.
None of them belong in this repository, in a release, or on the public site.

For `v1.0.9`, the Web App access setting was corrected from owner-only access to public web-app access so background uploads from Broccoli SmartInput no longer fail with HTTP 401. A full local `patch sync` run was verified after the access change, including both uploads.

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
