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
private let kBroccoliPatchSmartMixedASCIIWordsUploadURLKey = "BroccoliPatchSmartMixedASCIIWordsUploadURL"
private let kBroccoliPatchUserPhrasesUploadURLKey = "BroccoliPatchUserPhrasesUploadURL"
private let kBroccoliPatchReleaseAPIURLKey = "BroccoliPatchReleaseAPIURL"
private let kBroccoliPatchReleasePageURLKey = "BroccoliPatchReleasePageURL"
private let kBroccoliPatchSourceConfigFileName = "patch-source.json"

private let kDefaultBroccoliPatchReleaseAPIURL =
    "https://api.github.com/repos/CloudHua183/Broccoli-SmartInput/releases/latest"
private let kDefaultBroccoliPatchReleasePageURL =
    "https://github.com/CloudHua183/Broccoli-SmartInput/releases/latest"

enum BroccoliDiagnostics {
    static let logFileName = "diagnostics.log"

    // Deliberately not LanguageModelManager.dataFolderPath. That folder is now
    // an iCloud Drive folder, and the log would be synced to every machine and
    // to the cloud, where it does not belong: it grows without bound and it
    // records the bundle identifier of every application the user types in.
    // ~/Library/Logs is the conventional place for this and is never synced.
    static var logFolderURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
        return libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("BroccoliSmartInput", isDirectory: true)
    }

    static var logFileURL: URL {
        logFolderURL.appendingPathComponent(logFileName)
    }

    static func log(_ message: String, function: String = #function) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "[\(formatter.string(from: Date()))] \(function): \(message)\n"

        print(line, terminator: "")
        NSLog("%@", line.trimmingCharacters(in: .newlines))

        let url = logFileURL
        let directoryURL = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

        if !FileManager.default.fileExists(atPath: url.path) {
            try? line.data(using: .utf8)?.write(to: url, options: .atomic)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        handle.seekToEndOfFile()
        if let data = line.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
        handle.closeFile()
    }

    static func readLog() -> String {
        let url = logFileURL
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return "No diagnostics have been recorded yet.\nLog file: \(url.path)"
        }
        return text
    }

    static func reset() {
        let url = logFileURL
        try? FileManager.default.removeItem(at: url)
    }
}

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
            return String(
                format: NSLocalizedString(
                    "There may be no internet connection or the server failed to respond.\n\nError message: %@",
                    comment: ""), message)
        }
    }
}

struct VersionUpdateApi {
    static func check(
        forced: Bool, callback: @escaping (Result<VersionUpdateApiResult, Error>) -> Void
    ) -> URLSessionTask? {
        guard let infoDict = Bundle.main.infoDictionary,
            let updateInfoURLString = infoDict[kUpdateInfoEndpointKey] as? String,
            let updateInfoURL = URL(string: (updateInfoURLString + (forced ? "?manual=yes" : "")))
        else {
            return nil
        }

        let request = URLRequest(
            url: updateInfoURL, cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: kTimeoutInterval)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    forced
                        ? callback(
                            .failure(
                                VersionUpdateApiError.connectionError(
                                    message: error.localizedDescription)))
                        : callback(.success(.ignored))
                }
                return
            }

            do {
                guard
                    let plist = try PropertyListSerialization.propertyList(
                        from: data ?? Data(), options: [], format: nil) as? [AnyHashable: Any],
                    let remoteVersion = plist[kCFBundleVersionKey] as? String,
                    let infoDict = Bundle.main.infoDictionary
                else {
                    DispatchQueue.main.async {
                        forced ? callback(.success(.noNeedToUpdate)) : callback(.success(.ignored))
                    }
                    return
                }

                // TODO: Validate info (e.g. bundle identifier)
                // TODO: Use HTML to display change log, need a new key like UpdateInfoChangeLogURL for this

                let currentVersion = infoDict[kCFBundleVersionKey as String] as? String ?? ""
                let result = currentVersion.compare(
                    remoteVersion, options: .numeric, range: nil, locale: nil)

                if result != .orderedAscending {
                    DispatchQueue.main.async {
                        forced ? callback(.success(.noNeedToUpdate)) : callback(.success(.ignored))
                    }
                    return
                }

                guard let siteInfoURLString = plist[kUpdateInfoSiteKey] as? String,
                    let siteInfoURL = URL(string: siteInfoURLString)
                else {
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
                    versionDescription =
                        versionDescriptions[locale] as? String ?? versionDescriptions["en"]
                        as? String ?? ""
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
              "userPhrasesURL": "https://drive.google.com/uc?export=download&id=GOOGLE_FILE_ID_2",
              "smartMixedASCIIWordsUploadURL": "https://script.google.com/macros/s/DEPLOYMENT_ID/exec?target=smart",
              "userPhrasesUploadURL": "https://script.google.com/macros/s/DEPLOYMENT_ID/exec?target=user"
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

enum BroccoliPatchDictionaryKind {
    case smartMixedASCIIWords
    case userPhrases

    var cacheFileName: String {
        switch self {
        case .smartMixedASCIIWords:
            return ".broccoli-patch-base-smart-mixed-ascii-words.txt"
        case .userPhrases:
            return ".broccoli-patch-base-data.txt"
        }
    }
}

enum BroccoliPatchDictionaryLine {
    case blank
    case comment(String)
    case entry(key: String, canonical: String)
}

struct BroccoliPatchDictionarySnapshot {
    let lines: [BroccoliPatchDictionaryLine]
    let entryKeys: Set<String>

    static func parse(_ text: String, kind: BroccoliPatchDictionaryKind) -> BroccoliPatchDictionarySnapshot {
        var lines: [BroccoliPatchDictionaryLine] = []
        var entryKeys = Set<String>()

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                lines.append(.comment(trimmed))
                continue
            }

            switch kind {
            case .smartMixedASCIIWords:
                let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
                if trimmed.rangeOfCharacter(from: allowed.inverted) != nil {
                    continue
                }
                let key = trimmed.lowercased()
                entryKeys.insert(key)
                lines.append(.entry(key: key, canonical: trimmed))
            case .userPhrases:
                let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard components.count >= 2 else {
                    continue
                }
                let canonical = components.joined(separator: " ")
                let key = canonical.lowercased()
                entryKeys.insert(key)
                lines.append(.entry(key: key, canonical: canonical))
            }
        }

        return BroccoliPatchDictionarySnapshot(lines: lines, entryKeys: entryKeys)
    }
}

enum BroccoliPatchDictionaryMerger {
    static func cachePath(for kind: BroccoliPatchDictionaryKind, under folderPath: String) -> String {
        (folderPath as NSString).appendingPathComponent(kind.cacheFileName)
    }

    static func merge(
        kind: BroccoliPatchDictionaryKind,
        base: String?,
        local: String,
        remote: String
    ) -> String {
        if let base {
            return mergeThreeWay(
                kind: kind,
                base: base,
                local: local,
                remote: remote
            )
        }
        return mergeByUnion(
            kind: kind,
            left: remote,
            right: local
        )
    }

    static func loadCachedBaseSnapshot(kind: BroccoliPatchDictionaryKind) -> String? {
        let path = cachePath(for: kind, under: LanguageModelManager.dataFolderPath)
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    static func storeCachedBaseSnapshot(_ text: String, kind: BroccoliPatchDictionaryKind) throws {
        let path = cachePath(for: kind, under: LanguageModelManager.dataFolderPath)
        let fileURL = URL(fileURLWithPath: path)
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func mergeByUnion(
        kind: BroccoliPatchDictionaryKind,
        left: String,
        right: String
    ) -> String {
        let leftSnapshot = BroccoliPatchDictionarySnapshot.parse(left, kind: kind)
        let rightSnapshot = BroccoliPatchDictionarySnapshot.parse(right, kind: kind)
        var mergedKeys = leftSnapshot.entryKeys
        mergedKeys.formUnion(rightSnapshot.entryKeys)
        return renderMergedText(
            left: leftSnapshot,
            right: rightSnapshot,
            mergedKeys: mergedKeys,
            rightAdds: rightSnapshot.entryKeys.subtracting(leftSnapshot.entryKeys)
        )
    }

    private static func mergeThreeWay(
        kind: BroccoliPatchDictionaryKind,
        base: String,
        local: String,
        remote: String
    ) -> String {
        let baseSnapshot = BroccoliPatchDictionarySnapshot.parse(base, kind: kind)
        let localSnapshot = BroccoliPatchDictionarySnapshot.parse(local, kind: kind)
        let remoteSnapshot = BroccoliPatchDictionarySnapshot.parse(remote, kind: kind)

        var mergedKeys = remoteSnapshot.entryKeys
        let baseRemovedByRemote = baseSnapshot.entryKeys.subtracting(remoteSnapshot.entryKeys)
        let baseRemovedByLocal = baseSnapshot.entryKeys.subtracting(localSnapshot.entryKeys)
        mergedKeys.subtract(baseRemovedByRemote)
        mergedKeys.subtract(baseRemovedByLocal)
        mergedKeys.formUnion(localSnapshot.entryKeys.subtracting(baseSnapshot.entryKeys))

        return renderMergedText(
            left: remoteSnapshot,
            right: localSnapshot,
            mergedKeys: mergedKeys,
            rightAdds: localSnapshot.entryKeys.subtracting(baseSnapshot.entryKeys)
        )
    }

    private static func renderMergedText(
        left: BroccoliPatchDictionarySnapshot,
        right: BroccoliPatchDictionarySnapshot,
        mergedKeys: Set<String>,
        rightAdds: Set<String>
    ) -> String {
        var outputLines: [String] = []
        var seenKeys = Set<String>()
        var seenNonEntryLines = Set<String>()

        func appendLine(_ line: BroccoliPatchDictionaryLine) {
            switch line {
            case .blank:
                return
            case .comment(let comment):
                if seenNonEntryLines.insert(comment).inserted {
                    outputLines.append(comment)
                }
            case .entry(let key, let canonical):
                guard mergedKeys.contains(key), !seenKeys.contains(key) else {
                    return
                }
                seenKeys.insert(key)
                outputLines.append(canonical)
            }
        }

        for line in left.lines {
            appendLine(line)
        }

        for line in right.lines {
            switch line {
            case .entry(let key, let canonical):
                guard rightAdds.contains(key), !seenKeys.contains(key) else {
                    continue
                }
                seenKeys.insert(key)
                outputLines.append(canonical)
            default:
                appendLine(line)
            }
        }

        if outputLines.isEmpty {
            return ""
        }

        return outputLines.joined(separator: "\n") + "\n"
    }
}

struct BroccoliPatchSyncReport {
    var updatedFiles: [String] = []
    var uploadedFiles: [String] = []
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
    let smartMixedASCIIWordsUploadURL: String?
    let userPhrasesUploadURL: String?
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

        let localSmartWords = try String(contentsOfFile: LanguageModelManager.smartMixedASCIIWordsDataPath, encoding: .utf8)
        let localUserPhrases = try String(contentsOfFile: LanguageModelManager.userPhrasesDataPathMcBopomofo, encoding: .utf8)
        let smartBase = BroccoliPatchDictionaryMerger.loadCachedBaseSnapshot(kind: .smartMixedASCIIWords)
        let userBase = BroccoliPatchDictionaryMerger.loadCachedBaseSnapshot(kind: .userPhrases)
        let mergedSmartWords = BroccoliPatchDictionaryMerger.merge(
            kind: .smartMixedASCIIWords,
            base: smartBase,
            local: localSmartWords,
            remote: smartWords
        )
        let mergedUserPhrases = BroccoliPatchDictionaryMerger.merge(
            kind: .userPhrases,
            base: userBase,
            local: localUserPhrases,
            remote: userPhrases
        )

        var report = BroccoliPatchSyncReport()
        if let smartWordsUploadURL = source.smartMixedASCIIWordsUploadURL {
            try uploadText(mergedSmartWords, to: smartWordsUploadURL)
            report.uploadedFiles.append(LanguageModelManager.smartMixedASCIIWordsDataPath)
        }
        try writeSyncedFile(mergedSmartWords, to: LanguageModelManager.smartMixedASCIIWordsDataPath, report: &report)
        try BroccoliPatchDictionaryMerger.storeCachedBaseSnapshot(
            source.smartMixedASCIIWordsUploadURL == nil ? smartWords : mergedSmartWords,
            kind: .smartMixedASCIIWords
        )

        if let userPhrasesUploadURL = source.userPhrasesUploadURL {
            try uploadText(mergedUserPhrases, to: userPhrasesUploadURL)
            report.uploadedFiles.append(LanguageModelManager.userPhrasesDataPathMcBopomofo)
        }
        try writeSyncedFile(mergedUserPhrases, to: LanguageModelManager.userPhrasesDataPathMcBopomofo, report: &report)
        try BroccoliPatchDictionaryMerger.storeCachedBaseSnapshot(
            source.userPhrasesUploadURL == nil ? userPhrases : mergedUserPhrases,
            kind: .userPhrases
        )
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
                userPhrasesURL: userPhrasesURL,
                smartMixedASCIIWordsUploadURL: optionalUploadURL(for: kBroccoliPatchSmartMixedASCIIWordsUploadURLKey),
                userPhrasesUploadURL: optionalUploadURL(for: kBroccoliPatchUserPhrasesUploadURLKey))
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
                userPhrasesURL: userPhrasesURL,
                smartMixedASCIIWordsUploadURL: optionalUploadURL(json: json, key: "smartMixedASCIIWordsUploadURL"),
                userPhrasesUploadURL: optionalUploadURL(json: json, key: "userPhrasesUploadURL"))
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

    private static func uploadText(_ text: String, to urlString: String) throws {
        guard let url = URL(string: urlString) else {
            throw BroccoliPatchError.badURL(urlString)
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: kTimeoutInterval
        )
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let body = Data(text.utf8)
        let semaphore = DispatchSemaphore(value: 0)
        var responseError: Error?
        var responseStatusCode: Int?

        URLSession.shared.uploadTask(with: request, from: body) { _, response, error in
            responseError = error
            if let httpResponse = response as? HTTPURLResponse {
                responseStatusCode = httpResponse.statusCode
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()

        if let responseError {
            throw BroccoliPatchError.network(responseError.localizedDescription)
        }

        guard let responseStatusCode else {
            throw BroccoliPatchError.network("Cloud upload did not return an HTTP response: \(urlString)")
        }

        guard (200...299).contains(responseStatusCode) else {
            throw BroccoliPatchError.network("Cloud upload failed with HTTP \(responseStatusCode): \(urlString)")
        }
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

    private static func optionalUploadURL(for key: String) -> String? {
        guard let value = UserDefaults.standard.string(forKey: key) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionalUploadURL(json: [String: Any], key: String) -> String? {
        guard let value = json[key] as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        LanguageModelManager.loadUserPhrases(
            enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
        LanguageModelManager.loadUserPhraseReplacement()
        LanguageModelManager.loadCandidateOrder()

        fsStreamHelper?.delegate = nil
        fsStreamHelper?.stop()
        fsStreamHelper = FSEventStreamHelper(
            path: LanguageModelManager.dataFolderPath, queue: DispatchQueue(label: "User Phrases"))
        fsStreamHelper?.delegate = self
        _ = fsStreamHelper?.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LanguageModelManager.setupDataModelValueConverter()
        updateUserPhrases()

        // Broccoli SmartInput does not use the upstream McBopomofo update
        // feed. Automatic update checking is disabled so that users are never
        // directed to install the upstream package.
        UserDefaults.standard.set(false, forKey: kCheckUpdateAutomatically)
        UserDefaults.standard.synchronize()

        if UserDefaults.standard.object(forKey: kBeepUponInputErrorKey) == nil {
            UserDefaults.standard.set(true, forKey: kBeepUponInputErrorKey)
            UserDefaults.standard.synchronize()
        }

        NotificationCenter.default.addObserver(
            forName: .userPhraseLocationDidChange, object: nil, queue: OperationQueue.main
        ) { notification in
            self.updateUserPhrases()
        }

        serviceProvider.delegate = (serviceProviderHelper as! any ServiceProviderDelegate)
        NSApp.servicesProvider = serviceProvider

        enableBopomofoFontAnnotationSupportMenuItemIfRelevantFontsInstalled()
    }

    @MainActor
    @objc func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showAndActivate()
    }

    @objc(checkForUpdate)
    func checkForUpdate() {
        checkForUpdate(forced: false)
    }

    // Broccoli SmartInput does not use the upstream McBopomofo update feed,
    // so the check is switched off here rather than repointed. Flipping this
    // to true restores the original behaviour.
    private static let upstreamUpdateCheckEnabled = false

    @objc(checkForUpdateForced:)
    func checkForUpdate(forced: Bool) {
        guard Self.upstreamUpdateCheckEnabled else {
            return
        }
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
                    let content = String(
                        format: NSLocalizedString(
                            "You're currently using McBopomofo %@ (%@), a new version %@ (%@) is now available. Do you want to visit McBopomofo's website to download the version?%@",
                            comment: ""),
                        report.currentShortVersion,
                        report.currentVersion,
                        report.remoteShortVersion,
                        report.remoteVersion,
                        report.versionDescription)
                    NonModalAlertWindowController.shared.show(
                        title: NSLocalizedString("New Version Available", comment: ""),
                        content: content,
                        confirmButtonTitle: NSLocalizedString("Visit Website", comment: ""),
                        cancelButtonTitle: NSLocalizedString("Not Now", comment: ""),
                        cancelAsDefault: false, delegate: self)
                case .noNeedToUpdate:
                    NonModalAlertWindowController.shared.show(
                        title: NSLocalizedString("Check for Update Completed", comment: ""),
                        content: NSLocalizedString("McBopomofo is up to date.", comment: ""),
                        confirmButtonTitle: NSLocalizedString("OK", comment: ""),
                        cancelButtonTitle: nil, cancelAsDefault: false, delegate: self)
                case .ignored:
                    break
                }
            case .failure(let error):
                switch error {
                case VersionUpdateApiError.connectionError(let message):
                    let title = NSLocalizedString("Update Check Failed", comment: "")
                    let content = String(
                        format: NSLocalizedString(
                            "There may be no internet connection or the server failed to respond.\n\nError message: %@",
                            comment: ""), message)
                    let buttonTitle = NSLocalizedString("Dismiss", comment: "")
                    NonModalAlertWindowController.shared.show(
                        title: title, content: content, confirmButtonTitle: buttonTitle,
                        cancelButtonTitle: nil, cancelAsDefault: false, delegate: nil)
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
            LanguageModelManager.loadUserPhrases(
                enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
            LanguageModelManager.loadUserPhraseReplacement()
            LanguageModelManager.loadCandidateOrder()
        }
    }
}

extension AppDelegate {
    private func open(userFileAt path: String) {
        func checkIfUserFilesExist() -> Bool {
            if !LanguageModelManager.checkIfUserLanguageModelFilesExist() {
                let content = String(
                    format: NSLocalizedString(
                        "Please check the permission of the path at \"%@\".", comment: ""),
                    LanguageModelManager.dataFolderPath)
                NonModalAlertWindowController.shared.show(
                    title: NSLocalizedString("Failed to Create the User Phrase File", comment: ""),
                    content: content, confirmButtonTitle: NSLocalizedString("OK", comment: ""),
                    cancelButtonTitle: nil, cancelAsDefault: false, delegate: nil)
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
                    let uploadList = report.uploadedFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
                    var content = "已更新：\(fileList)"
                    if !uploadList.isEmpty {
                        content += "\n已回寫雲端：\(uploadList)"
                    }
                    NonModalAlertWindowController.shared.show(
                        title: "雲端詞庫同步完成",
                        content: content,
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
