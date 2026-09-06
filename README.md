# Broccoli SmartInput 接手入口

本 repo 是以 McBopomofo 小麥注音 3.1（2496）為基底的「花椰輸入法」實驗版，目標是在 macOS 上完成繁體注音的智慧中英混合輸入 MVP。

## 目前專案位置

- 本機程式碼：`/Users/cloudhuamacmini/Desktop/Projects/IME/McBopomofo`
- Obsidian / 專案文件目錄：`/Users/cloudhuamacmini/Desktop/Projects/IME/docs`
- GitHub repo：`https://github.com/CloudHua183/Broccoli-SmartInput`
- 主要分支：`upgrade/mcbopomofo-3.1`（升級前的 1.0.10 狀態保存在標籤 `broccoli-pre-upstream-3.1`）
- 上游基底：官方 tag `3.1`（`e965b78`，build 2496）
- 目前版本：`v1.1.0`
- 最低系統需求：macOS 13 Ventura

## 本次更新重點

- 基底升級到小麥注音 3.1（2496），採「以官方 3.1 為新基底、再逐一移植花椰客製」的方式，而非用新版覆蓋舊分支。
- 花椰功能全數保留並逐子系統驗證：品牌與在地化、安裝與發行、雲端詞庫同步與使用者詞操作、智慧中英混輸、引擎的游標前候選與使用者詞排序。
- 停用上游更新檢查，避免花椰使用者被導向安裝官方小麥注音；改用選單的「開啟 / 下載 GitHub 最新 Release」。
- 最低系統需求提高到 macOS 13 Ventura，與上游一致。
- 修正一個既有的 `reading_grid_test` 錯誤斷言；C++ 引擎測試 125/125 通過。

## Obsidian 文件索引

下次繼續專案時，先讀這些文件即可，不需要另外詢問 Obsidian 目錄。

- `/Users/cloudhuamacmini/Desktop/Projects/IME/docs/08_Broccoli_SmartInput_專案狀態.md`
  - 目前最重要的接手文件。
  - 記錄已完成功能、未完成功能、熱鍵、測試狀態、GitHub repo 與下一步建議。

- `/Users/cloudhuamacmini/Desktop/Projects/IME/docs/07_ASUS_Smart_Input_功能優先順序_PRD.md`
  - 原始 PRD。
  - 記錄 ASUS Smart Input 類功能的 P0/P1/P2/P3/P4 優先順序與驗收條件。

- `/Users/cloudhuamacmini/Desktop/Projects/IME/docs/mixed-input-design.md`
  - 混輸演算法設計草案。
  - 記錄 token 模型、使用者詞庫、英文判斷規則、自動完成、框選查詢與 MVP 驗收案例。

- `/Users/cloudhuamacmini/Desktop/Projects/IME/docs/project-brief.md`
  - 專案早期研究摘要。
  - 記錄 vChewing、McBopomofo 等候選基底的比較，以及為何先選 McBopomofo 做 MVP。

- `/Users/cloudhuamacmini/Desktop/Projects/IME/docs/implementation-plan.md`
  - 實作路線草案。
  - 記錄 vChewing 路線與 McBopomofo 路線的分階段執行方式。

## 目前已完成

- 選定 McBopomofo 作為 P0 MVP 基底。
- 輸入法顯示名稱改為「花椰輸入法」。
- 初版智慧中英混合輸入：支援大寫起始英文片段，例如 `Meeting`、`API`、`AI2026`，也支援部分小寫英文 run，例如 `call`、`meeting`、`api`。
- 指定英文白名單抽成檔案：`Source/Data/smart-mixed-ascii-words.txt`。
- 使用者詞庫 `~/Library/Application Support/McBopomofo/data.txt` 可參與英文 prefix 判斷。
- `Control + Shift + 數字` 可把游標前 N 個字元加入使用者詞庫；同一位置重複按可刪除。
- 已修正 `ㄇㄣ` 被誤判成 `ap` 的問題。
- 已修正使用者詞庫同音多詞時，第一順位未穩定優先的問題。
- 已新增個人安裝包腳本：`script/package_personal_installer.sh`。

## 目前尚未完成

- 候選列中的「作為英文 / 作為注音」切換 UI。
- 小寫英文自然混輸的完整 scanner 抽檔與 correction memory，例如短詞 `ai`、大小寫 canonical。
- correction memory 與排序權重學習。
- 使用者詞庫管理 UI。
- 自動完成、快捷文字本、英文大小寫修正。
- 框選查詢 companion app。
- Apple Developer 簽章與 notarization。

## 調整候選字順序

候選字視窗開著時，用 **`Option` + `↑` / `↓`** 把反白的候選字上移或下移一位。順序寫進詞庫資料夾的 `candidate-order.txt`，跟著多機同步走。

格式是一行一個讀音，後面接要排在前面的值：

```text
ㄗㄤˋ 藏 臟 葬
```

沒列出的值排在列出的值後面，維持原本的相對順序。

### 為什麼用 Option 而不是 Control

`Control` + 方向鍵被 macOS 的 Mission Control 佔用，在系統層就被攔截，根本不會傳到輸入法。

### 只能在同一個讀音內調整

候選清單同時包含較長詞組（來自跨越多個字的節點）的候選，那些屬於不同讀音。跨讀音的相對位置無法用「一個讀音一行」的檔案表達，所以碰到不同讀音的鄰居會發出錯誤提示音。

### 分數處理

重排之後會把原本那組分數依序重新指派，**最高分維持不變**。這很重要：如果直接讓低分候選排到第一位，格點運算會拿它的分數去算，整句的斷詞可能因此改變。現在改的只是「先給你看哪一個」，不是「句子怎麼斷」。

## 多台電腦同步

詞庫資料夾可以指向任何會自動同步的位置，輸入法本身完全不連網。`AppDelegate` 用 FSEvents 監看該資料夾，同步進來的變動會自動重新載入，不需要任何額外程式碼。

### 同一個 Apple 帳號：iCloud 雲碟

```bash
./script/migrate_to_icloud_dictionary.sh
```

複製詞庫到 `~/Library/Mobile Documents/com~apple~CloudDocs/BroccoliSmartInput`，設定 `CustomUserPhraseLocation`，停用舊的 `patch-source.json`。原始檔保留為備份，可重複執行。

### 不同 Apple 帳號：私有 git repo（本專案現行做法）

iCloud 雲碟的共享資料夾在此環境無法建立——macOS 在產生共享連結時回報「無法與輔助應用程式通訊」，屬 `sharingd` 層的故障，非本專案可控。改用私有 git repo：

```bash
./script/setup_dict_sync.sh git@github.com:YOUR_NAME/YOUR_DICT_REPO.git
```

**repo 的工作目錄就是詞庫資料夾**，輸入法直接讀寫它，所以不存在「哪一份才是最新」的問題。`script/dict_sync.sh` 由 launchd 每 900 秒執行一次：commit 本機變更、合併遠端、去重、推送。

`.gitattributes` 把詞庫標為 `merge=union`，兩台各自新增不同的詞會**兩邊都保留**而不是產生衝突；接著的去重步驟會移除重複行並**保留原始順序**，因為使用者詞的排序會影響候選字優先度。

比起 iCloud，git 這條路多了**版本歷史**——詞庫被誤改時可以回溯到任何一次同步。

紀錄檔：`~/Library/Logs/BroccoliSmartInput/dict-sync.log`

### 為什麼不再用 Google Apps Script

輸入法無法向 Google 驗證身分，所以那個 Web App 部署必須開放匿名存取。等於只要知道部署 URL 就能覆寫詞庫（`setContent()` 是整檔覆寫），而同步流程是「下載→合併進本機→回寫」，一次污染會擴散到所有機器並持續存在。該端點與相關 Drive 檔案已於 2026-09-02 全數移除。

## Drive Patch / 多台電腦同步（已停用，僅供參考）

公開 repo 不存放真正的個人詞庫。GitHub 只保留範例檔：

- `SharedDictionary/smart-mixed-ascii-words.example.txt`
  - 指定英文 / 產品名白名單範例。
- `SharedDictionary/data.example.txt`
  - 使用者詞庫範例。
- `SharedDictionary/patch-source.example.json`
  - Google Drive 下載 URL 與可選寫回 URL 設定範例。

真正的私人檔案放在 Google Drive：

```text
smart-mixed-ascii-words.txt
data.txt
```

目前 Drive 位置：

```text
Folder: https://drive.google.com/drive/folders/1nSXOhRm3tdukXhgp5MRMPZGL-oYcRdwv
smart-mixed-ascii-words.txt: 1PaH_srJBr0tcjooqaw1QeMCm4DnOJlQw
data.txt: 1Gp48qRsqXBXxtUdoPcTL-i5N3RBC2w5d
```

每台電腦需建立本機設定檔：

```text
~/Library/Application Support/McBopomofo/patch-source.json
```

格式：

```json
{
  "smartMixedASCIIWordsURL": "https://drive.google.com/uc?export=download&id=GOOGLE_DRIVE_FILE_ID_FOR_SMART_MIXED_ASCII_WORDS",
  "userPhrasesURL": "https://drive.google.com/uc?export=download&id=GOOGLE_DRIVE_FILE_ID_FOR_DATA_TXT"
}
```

安裝後，每台電腦可用輸入法選單執行：

```text
同步雲端詞庫
```

如果你只是剛剛手動改了本機詞庫檔，想讓輸入法立刻重新吃到內容，就用：

```text
重新載入使用者詞彙
```

也可用 CLI：

```bash
/Users/$USER/Library/Input\ Methods/McBopomofo.app/Contents/MacOS/McBopomofo patch sync
```

同步雲端詞庫的實際流程是：

1. 先從 `patch-source.json` 指定的 Google Drive 下載最新詞庫。
2. 驗證格式，並和本機詞庫做增量合併。
3. 如果也設定了 Google Apps Script writeback URL，就把合併後結果寫回雲端。
4. 再備份本機舊檔並覆蓋：

```text
~/Library/Application Support/McBopomofo/data.txt
~/Library/Application Support/McBopomofo/smart-mixed-ascii-words.txt
```

白話一點說：

- `重新載入使用者詞彙` = 只重讀本機檔案，讓你剛編輯完的內容立刻生效，不碰雲端。
- `同步雲端詞庫` = 先抓雲端、再合併本機、必要時回寫雲端，適合要把本機新增詞彙分享給其他電腦時使用。
- 本地新增詞彙不會自動上傳；真正上傳雲端的時機是你手動執行 `同步雲端詞庫`，而且已設定 upload URL。

GitHub Release patch 功能：

```bash
/Users/$USER/Library/Input\ Methods/McBopomofo.app/Contents/MacOS/McBopomofo patch check-release
/Users/$USER/Library/Input\ Methods/McBopomofo.app/Contents/MacOS/McBopomofo patch download-release
/Users/$USER/Library/Input\ Methods/McBopomofo.app/Contents/MacOS/McBopomofo patch open-release
```

輸入法選單也有：

```text
開啟 GitHub 最新 Release…
下載 GitHub 最新 Release…
```

注意：Drive 若設定成「知道連結的人可以存取」，連結外流時仍可能被讀取或編輯；但至少不會被公開 GitHub repo 直接列出。

## 常用本機指令

推送目前分支：

```bash
cd /Users/cloudhuamacmini/Desktop/Projects/IME/McBopomofo
git remote set-url myrepo https://github.com/CloudHua183/Broccoli-SmartInput.git
git push -u myrepo smart-mixed-user-phrases
```

跑目前已驗證的 focused tests：

```bash
cd /Users/cloudhuamacmini/Desktop/Projects/IME/McBopomofo
xcodebuild test -project McBopomofo.xcodeproj -scheme McBopomofo -destination platform=macOS,arch=arm64 -derivedDataPath /Users/cloudhuamacmini/Desktop/Projects/IME/McBopomofo/DerivedData -only-testing:McBopomofoTests/KeyHandlerBopomofoTests/testSmartMixedASCIISequenceKeepsContinuousTrailingDigitsInChineseContext -only-testing:McBopomofoTests/KeyHandlerBopomofoTests/testSmartMixedASCIISequenceDoesNotHijackBopomofoPrefix
```

建立個人安裝包：

```bash
cd /Users/cloudhuamacmini/Desktop/Projects/IME/McBopomofo
./script/package_personal_installer.sh
```

## 重要檔案

- `Source/KeyHandler.mm`
  - 智慧中英混輸的 key handling 與 ASCII sequence 判斷。

- `Source/InputMethodController.swift`
  - `Control + Shift + 數字` 加入 / 刪除使用者詞庫與提示視窗。

- `Source/LanguageModelManager.mm`
  - 使用者詞庫讀寫、ASCII 詞 prefix 查詢、白名單讀取。

- `Source/Data/smart-mixed-ascii-words.txt`
  - 指定英文白名單，一行一個詞。

- `McBopomofoTests/KeyHandlerBopomofoTests.swift`
  - 智慧混輸相關測試。

- `script/package_personal_installer.sh`
  - 個人安裝包產生腳本。

## 最近幾次排查的收穫摘要

- 目前在 Chrome + Canva 可正常切換並顯示花椰輸入法選單，代表輸入法 bundle 本身與選單建構邏輯正常。
- Telegram、Hermes、Arc + Canva 異常時，診斷紀錄沒有進入 `activateServer`、`setValue`、`menu()`，代表問題不在按鍵攔截，而是那些 App 根本沒有連到新版輸入法 controller。
- 問題與這些 App 長時間不關閉有關。當輸入法被重裝或重新註冊後，部分 App 仍保留舊的 InputMethodKit 連線，所以畫面上雖然看到輸入法被勾選，但下方服務選單不出現，實際上也無法輸入。
- 已在安裝流程補上更保守的 Release build、LaunchServices 重新註冊，以及 `TextInputMenuAgent` / `imklaunchagent` 這一層的刷新，能降低更新後殘留舊連線的機率。
- 若某個 App 在更新輸入法後仍只顯示勾選、卻沒有花椰輸入法功能項目，最有效的處理是「完全關閉該 App 再重開」，而不是只切換輸入法來源。
