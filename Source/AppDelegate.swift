// Copyright (c) 2022 and onwards The McBopomofo Authors.
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

import Cocoa
import FSEventStreamHelper
import InputMethodKit

private let kCheckUpdateAutomatically = "CheckUpdateAutomatically"
private let kNextUpdateCheckDateKey = "NextUpdateCheckDate"
private let kUpdateInfoEndpointKey = "UpdateInfoEndpoint"
private let kUpdateInfoSiteKey = "UpdateInfoSite"
private let kNextCheckInterval: TimeInterval = 86400.0
private let kTimeoutInterval: TimeInterval = 60.0
private let kBroccoliPatchSmartMixedASCIIWordsURLKey = "BroccoliPatchSmartMixedASCIIWordsURL"
private let kBroccoliPatchUserPhrasesURLKey = "BroccoliPatchUserPhrasesURL"
private let kBroccoliPatchReleaseAPIURLKey = "BroccoliPatchReleaseAPIURL"
private let kBroccoliPatchReleasePageURLKey = "BroccoliPatchReleasePageURL"
private let kBroccoliPatchSourceConfigFileName = "patch-source.json"

private let kDefaultBroccoliPatchReleaseAPIURL =
    "https://api.github.com/repos/CloudHua183/Broccoli-SmartInput/releases/latest"
private let kDefaultBroccoliPatchReleasePageURL =
    "https://github.com/CloudHua183/Broccoli-SmartInput/releases/latest"

struct VersionUpdateReport {
    var siteUrl: URL?
    var currentShortVersion: String = ""
    var currentVersion: String = ""
    var remoteShortVersion: String = ""
    var remoteVersion: String = ""
    var versionDescription: String = ""
}

enum VersionUpdateApiResult {
    case shouldUpdate(report: VersionUpdateReport)
    case noNeedToUpdate
    case ignored
}

enum VersionUpdateApiError: Error, LocalizedError {
    case connectionError(message: String)

    var errorDescription: String? {
        switch self {
        case .connectionError(let message):
            return String(format: NSLocalizedString("There may be no internet connection or the server failed to respond.\n\nError message: %@", comment: ""), message)
        }
    }
}

struct VersionUpdateApi {
    static func check(forced: Bool, callback: @escaping (Result<VersionUpdateApiResult, Error>) -> ()) -> URLSessionTask? {
        guard let infoDict = Bundle.main.infoDictionary,
              let updateInfoURLString = infoDict[kUpdateInfoEndpointKey] as? String,
              let updateInfoURL = URL(string: (updateInfoURLString + (forced ? "?manual=yes" : ""))) else {
            return nil
        }

        let request = URLRequest(url: updateInfoURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: kTimeoutInterval)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    forced ?
                            callback(.failure(VersionUpdateApiError.connectionError(message: error.localizedDescription))) :
                            callback(.success(.ignored))
                }
                return
            }

            do {
                guard let plist = try PropertyListSerialization.propertyList(from: data ?? Data(), options: [], format: nil) as? [AnyHashable: Any],
                      let remoteVersion = plist[kCFBundleVersionKey] as? String,
                      let infoDict = Bundle.main.infoDictionary else {
                    DispatchQueue.main.async {
                        forced ? callback(.success(.noNeedToUpdate)) : callback(.success(.ignored))
                    }
                    return
                }

                // TODO: Validate info (e.g. bundle identifier)
                // TODO: Use HTML to display change log, need a new key like UpdateInfoChangeLogURL for this

                let currentVersion = infoDict[kCFBundleVersionKey as String] as? String ?? ""
                let result = currentVersion.compare(remoteVersion, options: .numeric, range: nil, locale: nil)

                if result != .orderedAscending {
                    DispatchQueue.main.async {
                        forced ? callback(.success(.noNeedToUpdate)) : callback(.success(.ignored))
                    }
                    return
                }

                guard let siteInfoURLString = plist[kUpdateInfoSiteKey] as? String,
                      let siteInfoURL = URL(string: siteInfoURLString) else {
                    DispatchQueue.main.async {
                        forced ? callback(.success(.noNeedToUpdate)) : callback(.success(.ignored))
                    }
                    return
                }

                var report = VersionUpdateReport(siteUrl: siteInfoURL)
                var versionDescription = ""
                let versionDescriptions = plist["Description"] as? [AnyHashable: Any]
                if let versionDescriptions = versionDescriptions {
                    var locale = "en"
                    let supportedLocales = ["en", "zh-Hant", "zh-Hans"]
                    let preferredTags = Bundle.preferredLocalizations(from: supportedLocales)
                    if let first = preferredTags.first {
                        locale = first
                    }
                    versionDescription = versionDescriptions[locale] as? String ?? versionDescriptions["en"] as? String ?? ""
                    if !versionDescription.isEmpty {
                        versionDescription = "\n\n" + versionDescription
                    }
                }
                report.currentShortVersion = infoDict["CFBundleShortVersionString"] as? String ?? ""
                report.currentVersion = currentVersion
                report.remoteShortVersion = plist["CFBundleShortVersionString"] as? String ?? ""
                report.remoteVersion = remoteVersion
                report.versionDescription = versionDescription
                DispatchQueue.main.async {
                    callback(.success(.shouldUpdate(report: report)))
                }
            } catch {
                DispatchQueue.main.async {
                    forced ? callback(.success(.noNeedToUpdate)) : callback(.success(.ignored))
                }
            }
        }
        task.resume()
        return task
    }
}

enum BroccoliPatchError: Error, LocalizedError {
    case badURL(String)
    case missingPatchSourceConfig(String)
    case network(String)
    case invalidDictionary(String)
    case fileWrite(String)
    case noReleaseAsset
    case noReleaseFound

    var errorDescription: String? {
        switch self {
        case .badURL(let value):
            return "Invalid URL: \(value)"
        case .missingPatchSourceConfig(let path):
            return """
            Patch dictionary source is not configured.

            Create this file:
            \(path)

            Example:
            {
              "smartMixedASCIIWordsURL": "https://drive.google.com/uc?export=download&id=GOOGLE_FILE_ID_1",
              "userPhrasesURL": "https://drive.google.com/uc?export=download&id=GOOGLE_FILE_ID_2"
            }
            """
        case .network(let message):
            return message
        case .invalidDictionary(let message):
            return message
        case .fileWrite(let message):
            return message
        case .noReleaseAsset:
            return "No downloadable .dmg, .pkg, or .zip asset was found in the latest GitHub release."
        case .noReleaseFound:
            return "No GitHub release was found."
        }
    }
}

struct BroccoliPatchSyncReport {
    var updatedFiles: [String] = []
    var backupFiles: [String] = []
}

struct BroccoliPatchRelease {
    let tagName: String
    let htmlURL: URL
    let assetURL: URL?
    let assetName: String?
}

struct BroccoliPatchDictionarySource {
    let smartMixedASCIIWordsURL: String
    let userPhrasesURL: String
}

enum BroccoliPatchManager {
    private static var releaseAPIURLString: String {
        UserDefaults.standard.string(forKey: kBroccoliPatchReleaseAPIURLKey)
            ?? kDefaultBroccoliPatchReleaseAPIURL
    }

    static var releasePageURL: URL {
        URL(
            string: UserDefaults.standard.string(forKey: kBroccoliPatchReleasePageURLKey)
                ?? kDefaultBroccoliPatchReleasePageURL
        )!
    }

    static var patchSourceConfigPath: String {
        (LanguageModelManager.dataFolderPath as NSString).appendingPathComponent(kBroccoliPatchSourceConfigFileName)
    }

    static func syncDictionaries() throws -> BroccoliPatchSyncReport {
        guard LanguageModelManager.checkIfUserLanguageModelFilesExist() else {
            throw BroccoliPatchError.fileWrite("Cannot create or access \(LanguageModelManager.dataFolderPath).")
        }

        let source = try dictionarySource()
        let smartWords = try downloadText(from: source.smartMixedASCIIWordsURL)
        let userPhrases = try downloadText(from: source.userPhrasesURL)
        try validateSmartMixedWords(smartWords)
        try validateUserPhrases(userPhrases)

        var report = BroccoliPatchSyncReport()
        try writeSyncedFile(smartWords, to: LanguageModelManager.smartMixedASCIIWordsDataPath, report: &report)
        try writeSyncedFile(userPhrases, to: LanguageModelManager.userPhrasesDataPathMcBopomofo, report: &report)
        LanguageModelManager.loadUserPhrases(enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
        return report
    }

    private static func dictionarySource() throws -> BroccoliPatchDictionarySource {
        if
            let smartWordsURL = UserDefaults.standard.string(forKey: kBroccoliPatchSmartMixedASCIIWordsURLKey),
            let userPhrasesURL = UserDefaults.standard.string(forKey: kBroccoliPatchUserPhrasesURLKey),
            !smartWordsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !userPhrasesURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return BroccoliPatchDictionarySource(
                smartMixedASCIIWordsURL: smartWordsURL,
                userPhrasesURL: userPhrasesURL)
        }

        let configPath = patchSourceConfigPath
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw BroccoliPatchError.missingPatchSourceConfig(configPath)
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BroccoliPatchError.invalidDictionary("Invalid patch-source.json: expected a JSON object.")
            }
            guard
                let smartWordsURL = json["smartMixedASCIIWordsURL"] as? String,
                let userPhrasesURL = json["userPhrasesURL"] as? String,
                !smartWordsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !userPhrasesURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw BroccoliPatchError.invalidDictionary("Invalid patch-source.json: smartMixedASCIIWordsURL and userPhrasesURL are required.")
            }
            return BroccoliPatchDictionarySource(
                smartMixedASCIIWordsURL: smartWordsURL,
                userPhrasesURL: userPhrasesURL)
        } catch let error as BroccoliPatchError {
            throw error
        } catch {
            throw BroccoliPatchError.invalidDictionary("Cannot read patch-source.json: \(error.localizedDescription)")
        }
    }

    static func latestRelease() throws -> BroccoliPatchRelease {
        let content = try downloadData(from: releaseAPIURLString)
        guard
            let json = try JSONSerialization.jsonObject(with: content) as? [String: Any],
            let tagName = json["tag_name"] as? String,
            let htmlURLString = json["html_url"] as? String,
            let htmlURL = URL(string: htmlURLString)
        else {
            throw BroccoliPatchError.noReleaseFound
        }

        let assets = json["assets"] as? [[String: Any]] ?? []
        let asset = assets.first { item in
            guard let name = item["name"] as? String else {
                return false
            }
            let lower = name.lowercased()
            return lower.hasSuffix(".dmg") || lower.hasSuffix(".pkg") || lower.hasSuffix(".zip")
        }
        let assetName = asset?["name"] as? String
        let assetURL = (asset?["browser_download_url"] as? String).flatMap(URL.init(string:))
        return BroccoliPatchRelease(tagName: tagName, htmlURL: htmlURL, assetURL: assetURL, assetName: assetName)
    }

    static func downloadLatestReleaseAsset() throws -> URL {
        let release = try latestRelease()
        guard let assetURL = release.assetURL, let assetName = release.assetName else {
            throw BroccoliPatchError.noReleaseAsset
        }

        let data = try downloadData(from: assetURL.absoluteString)
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let destination = downloads.appendingPathComponent(assetName)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func downloadText(from urlString: String) throws -> String {
        let data = try downloadData(from: urlString)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BroccoliPatchError.network("Downloaded content is not UTF-8: \(urlString)")
        }
        return text
    }

    private static func downloadData(from urlString: String) throws -> Data {
        guard let url = URL(string: urlString) else {
            throw BroccoliPatchError.badURL(urlString)
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: kTimeoutInterval)
        request.setValue("Broccoli-SmartInput", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(BroccoliPatchError.network("No response from \(urlString)."))
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer {
                semaphore.signal()
            }
            if let error = error {
                result = .failure(BroccoliPatchError.network(error.localizedDescription))
                return
            }
            if let response = response as? HTTPURLResponse, !(200 ..< 300).contains(response.statusCode) {
                result = .failure(BroccoliPatchError.network("HTTP \(response.statusCode): \(urlString)"))
                return
            }
            result = .success(data ?? Data())
        }.resume()
        semaphore.wait()
        return try result.get()
    }

    private static func validateSmartMixedWords(_ content: String) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let lines = content.components(separatedBy: .newlines)
        var validWordCount = 0
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.rangeOfCharacter(from: allowed.inverted) != nil {
                throw BroccoliPatchError.invalidDictionary("Invalid smart word at line \(index + 1): \(trimmed)")
            }
            validWordCount += 1
        }
        if validWordCount == 0 {
            throw BroccoliPatchError.invalidDictionary("smart-mixed-ascii-words.txt does not contain any usable words.")
        }
    }

    private static func validateUserPhrases(_ content: String) throws {
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count < 2 {
                throw BroccoliPatchError.invalidDictionary("Invalid user phrase at line \(index + 1): \(trimmed)")
            }
        }
    }

    private static func writeSyncedFile(_ content: String, to path: String, report: inout BroccoliPatchSyncReport) throws {
        let manager = FileManager.default
        let fileURL = URL(fileURLWithPath: path)
        let folderURL = fileURL.deletingLastPathComponent()
        do {
            try manager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            if manager.fileExists(atPath: path) {
                let backupURL = folderURL.appendingPathComponent("\(fileURL.lastPathComponent).backup-\(backupTimestamp())")
                try manager.copyItem(at: fileURL, to: backupURL)
                report.backupFiles.append(backupURL.path)
            }
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            report.updatedFiles.append(path)
        } catch {
            throw BroccoliPatchError.fileWrite(error.localizedDescription)
        }
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

@objc(AppDelegate)
class AppDelegate: NSObject, NSApplicationDelegate, NonModalAlertWindowControllerDelegate {

    @IBOutlet weak var window: NSWindow?
    private var preferencesWindowController: PreferencesWindowController?
    private var checkTask: URLSessionTask?
    private var updateNextStepURL: URL?
    private var fsStreamHelper: FSEventStreamHelper?
    private var serviceProvider = ServiceProvider()
    private var serviceProviderHelper = ServiceProviderInputHelper()

    func updateUserPhrases() {
        LanguageModelManager.loadUserPhrases(enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
        LanguageModelManager.loadUserPhraseReplacement()

        fsStreamHelper?.delegate = nil
        fsStreamHelper?.stop()
        fsStreamHelper = FSEventStreamHelper(path: LanguageModelManager.dataFolderPath, queue: DispatchQueue(label: "User Phrases"))
        fsStreamHelper?.delegate = self
        _ = fsStreamHelper?.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LanguageModelManager.setupDataModelValueConverter()
        updateUserPhrases()

        if UserDefaults.standard.object(forKey: kCheckUpdateAutomatically) == nil {
            UserDefaults.standard.set(true, forKey: kCheckUpdateAutomatically)
            UserDefaults.standard.synchronize()
        }

        if UserDefaults.standard.object(forKey: kBeepUponInputErrorKey) == nil {
            UserDefaults.standard.set(true, forKey: kBeepUponInputErrorKey)
            UserDefaults.standard.synchronize()
        }

        NotificationCenter.default.addObserver(forName: .userPhraseLocationDidChange, object: nil, queue: OperationQueue.main) { notification in
            self.updateUserPhrases()
        }

        serviceProvider.delegate = (serviceProviderHelper as! any ServiceProviderDelegate)
        NSApp.servicesProvider = serviceProvider

        enableBopomofoFontAnnotationSupportMenuItemIfRelevantFontsInstalled()

        checkForUpdate()
    }

    @objc func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(windowNibName: "preferences")
        }
        preferencesWindowController?.window?.center()
        preferencesWindowController?.window?.orderFront(self)
    }

    @objc(checkForUpdate)
    func checkForUpdate() {
        checkForUpdate(forced: false)
    }

    @objc(checkForUpdateForced:)
    func checkForUpdate(forced: Bool) {
        if checkTask != nil {
            // busy
            return
        }

        // time for update?
        if !forced {
            if UserDefaults.standard.bool(forKey: kCheckUpdateAutomatically) == false {
                return
            }
            let now = Date()
            let date = UserDefaults.standard.object(forKey: kNextUpdateCheckDateKey) as? Date ?? now
            if now.compare(date) == .orderedAscending {
                return
            }
        }

        let nextUpdateDate = Date(timeInterval: kNextCheckInterval, since: Date())
        UserDefaults.standard.set(nextUpdateDate, forKey: kNextUpdateCheckDateKey)

        checkTask = VersionUpdateApi.check(forced: forced) { result in
            defer {
                self.checkTask = nil
            }
            switch result {
            case .success(let apiResult):
                switch apiResult {
                case .shouldUpdate(let report):
                    self.updateNextStepURL = report.siteUrl
                    let content = String(format: NSLocalizedString("You're currently using McBopomofo %@ (%@), a new version %@ (%@) is now available. Do you want to visit McBopomofo's website to download the version?%@", comment: ""),
                            report.currentShortVersion,
                            report.currentVersion,
                            report.remoteShortVersion,
                            report.remoteVersion,
                            report.versionDescription)
                    NonModalAlertWindowController.shared.show(title: NSLocalizedString("New Version Available", comment: ""), content: content, confirmButtonTitle: NSLocalizedString("Visit Website", comment: ""), cancelButtonTitle: NSLocalizedString("Not Now", comment: ""), cancelAsDefault: false, delegate: self)
                case .noNeedToUpdate:
                    NonModalAlertWindowController.shared.show(title: NSLocalizedString("Check for Update Completed", comment: ""), content: NSLocalizedString("McBopomofo is up to date.", comment: ""), confirmButtonTitle: NSLocalizedString("OK", comment: ""), cancelButtonTitle: nil, cancelAsDefault: false, delegate: self)
                case .ignored:
                    break
                }
            case .failure(let error):
                switch error {
                case VersionUpdateApiError.connectionError(let message):
                    let title = NSLocalizedString("Update Check Failed", comment: "")
                    let content = String(format: NSLocalizedString("There may be no internet connection or the server failed to respond.\n\nError message: %@", comment: ""), message)
                    let buttonTitle = NSLocalizedString("Dismiss", comment: "")
                    NonModalAlertWindowController.shared.show(title: title, content: content, confirmButtonTitle: buttonTitle, cancelButtonTitle: nil, cancelAsDefault: false, delegate: nil)
                default:
                    break
                }
            }
        }
    }

    func nonModalAlertWindowControllerDidConfirm(_ controller: NonModalAlertWindowController) {
        if let updateNextStepURL = updateNextStepURL {
            NSWorkspace.shared.open(updateNextStepURL)
        }
        updateNextStepURL = nil
    }

    func nonModalAlertWindowControllerDidCancel(_ controller: NonModalAlertWindowController) {
        updateNextStepURL = nil
    }
}

extension AppDelegate: FSEventStreamHelperDelegate {
    func helper(_ helper: FSEventStreamHelper, didReceive events: [FSEventStreamHelper.Event]) {
        DispatchQueue.main.async {
            LanguageModelManager.loadUserPhrases(enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
            LanguageModelManager.loadUserPhraseReplacement()
        }
    }
}

extension AppDelegate {
    private func open(userFileAt path: String) {
        func checkIfUserFilesExist() -> Bool {
            if !LanguageModelManager.checkIfUserLanguageModelFilesExist() {
                let content = String(format: NSLocalizedString("Please check the permission of the path at \"%@\".", comment: ""), LanguageModelManager.dataFolderPath)
                NonModalAlertWindowController.shared.show(title: NSLocalizedString("Failed to Create the User Phrase File", comment: ""), content: content, confirmButtonTitle: NSLocalizedString("OK", comment: ""), cancelButtonTitle: nil, cancelAsDefault: false, delegate: nil)
                return false
            }
            return true
        }

        if !checkIfUserFilesExist() {
            return
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    @objc func openUserPhrases(_ sender: Any?) {
        open(userFileAt: LanguageModelManager.userPhrasesDataPathMcBopomofo)
    }

    @objc func openUserPhrasesPlainBopomofo(_ sender: Any?) {
        open(userFileAt: LanguageModelManager.userPhrasesDataPathPlainBopomofo)
    }

    @objc func openExcludedPhrasesPlainBopomofo(_ sender: Any?) {
        open(userFileAt: LanguageModelManager.excludedPhrasesDataPathPlainBopomofo)
    }

    @objc func openExcludedPhrasesMcBopomofo(_ sender: Any?) {
        open(userFileAt: LanguageModelManager.excludedPhrasesDataPathMcBopomofo)
    }

    @objc func openPhraseReplacementMcBopomofo(_ sender: Any?) {
        open(userFileAt: LanguageModelManager.phraseReplacementDataPathMcBopomofo)
    }

    @objc func syncBroccoliPatchDictionaries(_ sender: Any?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try BroccoliPatchManager.syncDictionaries()
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let report):
                    let fileList = report.updatedFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
                    NonModalAlertWindowController.shared.show(
                        title: "雲端詞庫同步完成",
                        content: "已更新：\(fileList)",
                        confirmButtonTitle: NSLocalizedString("OK", comment: ""),
                        cancelButtonTitle: nil,
                        cancelAsDefault: false,
                        delegate: nil)
                case .failure(let error):
                    NonModalAlertWindowController.shared.show(
                        title: "雲端詞庫同步失敗",
                        content: error.localizedDescription,
                        confirmButtonTitle: NSLocalizedString("OK", comment: ""),
                        cancelButtonTitle: nil,
                        cancelAsDefault: false,
                        delegate: nil)
                }
            }
        }
    }

    @objc func openBroccoliLatestRelease(_ sender: Any?) {
        NSWorkspace.shared.open(BroccoliPatchManager.releasePageURL)
    }

    @objc func downloadBroccoliLatestRelease(_ sender: Any?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try BroccoliPatchManager.downloadLatestReleaseAsset()
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let destination):
                    NonModalAlertWindowController.shared.show(
                        title: "GitHub 最新 Release 已下載",
                        content: destination.path,
                        confirmButtonTitle: NSLocalizedString("OK", comment: ""),
                        cancelButtonTitle: nil,
                        cancelAsDefault: false,
                        delegate: nil)
                    NSWorkspace.shared.open(destination)
                case .failure(let error):
                    NonModalAlertWindowController.shared.show(
                        title: "GitHub Release 下載失敗",
                        content: error.localizedDescription,
                        confirmButtonTitle: NSLocalizedString("OK", comment: ""),
                        cancelButtonTitle: nil,
                        cancelAsDefault: false,
                        delegate: nil)
                }
            }
        }
    }
}

extension AppDelegate {
    private func enableBopomofoFontAnnotationSupportMenuItemIfRelevantFontsInstalled() {
        guard !Preferences.bopomofoFontAnnotationSupportMenuItemEnabledByInstalledFontsCheck_V1
        else {
            return
        }

        Preferences.bopomofoFontAnnotationSupportMenuItemEnabledByInstalledFontsCheck_V1 = true

        let supportedFontNames = [
            "BpmfGenRyuMin-B",
            "BpmfGenRyuMin-EL",
            "BpmfGenRyuMin-H",
            "BpmfGenRyuMin-L",
            "BpmfGenRyuMin-M",
            "BpmfGenRyuMin-R",
            "BpmfGenRyuMin-SB",
            "BpmfGenSekiGothic-B",
            "BpmfGenSekiGothic-H",
            "BpmfGenSekiGothic-L",
            "BpmfGenSekiGothic-M",
            "BpmfGenSekiGothic-R",
            "BpmfGenSenRounded-B",
            "BpmfGenSenRounded-EL",
            "BpmfGenSenRounded-H",
            "BpmfGenSenRounded-L",
            "BpmfGenSenRounded-M",
            "BpmfGenSenRounded-R",
            "BpmfGenWanMin-EL",
            "BpmfGenWanMin-L",
            "BpmfGenWanMin-M",
            "BpmfGenWanMin-R",
            "BpmfGenWanMin-SB",
            "BpmfGenYoGothic-B",
            "BpmfGenYoGothic-EL",
            "BpmfGenYoGothic-H",
            "BpmfGenYoGothic-L",
            "BpmfGenYoGothic-M",
            "BpmfGenYoGothic-N",
            "BpmfGenYoGothic-R",
            "BpmfGenYoMin-B",
            "BpmfGenYoMin-EL",
            "BpmfGenYoMin-H",
            "BpmfGenYoMin-L",
            "BpmfGenYoMin-M",
            "BpmfGenYoMin-R",
            "BpmfGenYoMin-SB",
            "BpmfHuninn-Regular",
            "BpmfIansui-Regular",
            "BpmfZihiBox-R",
            "BpmfZihiKaiStd-Regular",
            "BpmfZihiOnly-R",
            "BpmfZihiSans-Bold",
            "BpmfZihiSans-ExtraLight",
            "BpmfZihiSans-Heavy",
            "BpmfZihiSans-Light",
            "BpmfZihiSans-Medium",
            "BpmfZihiSans-Regular",
            "BpmfZihiSerif-Bold",
            "BpmfZihiSerif-ExtraLight",
            "BpmfZihiSerif-Heavy",
            "BpmfZihiSerif-Light",
            "BpmfZihiSerif-Medium",
            "BpmfZihiSerif-Regular",
            "BpmfZihiSerif-SemiBold",
        ]

        var hasSupportingFont = false
        let allFonts = Set(NSFontManager.shared.availableFonts)
        for fontName in supportedFontNames {
            if allFonts.contains(fontName) {
                hasSupportingFont = true
                break
            }
        }

        if hasSupportingFont {
            Preferences.showBopomofoFontAnnotationSupportItemInInputMenu = true
        }
    }
}
