# Broccoli SmartInput 接手入口

本 repo 是以 McBopomofo 小麥注音為基底的「花椰輸入法」實驗版，目標是在 macOS 上完成繁體注音的智慧中英混合輸入 MVP。

## 目前專案位置

- 本機程式碼：`/Users/cloudhuamacmini/Desktop/Projects/IME/McBopomofo`
- Obsidian / 專案文件目錄：`/Users/cloudhuamacmini/Desktop/Projects/IME/docs`
- GitHub repo：`https://github.com/CloudHua183/Broccoli-SmartInput`
- 主要分支：`smart-mixed-user-phrases`
- 目前基準 commit：`44d7c4d Fix smart mixed input numeric and bopomofo handling`
- 目前版本：`v1.0.2`

## 本次更新重點

- Google Apps Script Web App 已完成部署，可作為雲端詞庫回寫端點。
- `patch-source.json` 已加入上傳 URL，支援多台電腦先下載、再合併、最後回寫同一份雲端詞庫。
- 網站與安裝包版本已對齊到 `v1.0.2`。

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

## Drive Patch / 多台電腦同步

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
  "smartMixedASCIIWordsURL": "https://drive.google.com/uc?export=download&id=1PaH_srJBr0tcjooqaw1QeMCm4DnOJlQw",
  "userPhrasesURL": "https://drive.google.com/uc?export=download&id=1Gp48qRsqXBXxtUdoPcTL-i5N3RBC2w5d"
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
