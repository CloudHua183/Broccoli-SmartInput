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
import InputMethodKit
import InputSourceHelper

private func retry<T>(attempts: Int = 10, delay: TimeInterval = 0.25, action: () -> T?) -> T? {
    for attempt in 0..<attempts {
        if let result = action() {
            return result
        }
        if attempt + 1 < attempts {
            Thread.sleep(forTimeInterval: delay)
        }
    }
    return nil
}

private func install() -> Int32 {
    guard let bundleID = Bundle.main.bundleIdentifier else {
        return -1
    }
    let options = Set(CommandLine.arguments.dropFirst(2))
    let shouldEnableAll = options.contains("--all")
    let shouldSelect = options.contains("--select")
    let bopomofoModeID = "\(bundleID).Bopomofo"
    let bundleUrl = Bundle.main.bundleURL
    var maybeInputSource = retry {
        InputSourceHelper.inputSource(for: bundleID)
    }

    if maybeInputSource == nil {
        NSLog("Registering input source \(bundleID) at \(bundleUrl.absoluteString)");
        // then register
        let status = InputSourceHelper.registerInputSource(at: bundleUrl)

        if !status {
            NSLog("Fatal error: Cannot register input source \(bundleID) at \(bundleUrl.absoluteString).")
            return -1
        }

        maybeInputSource = retry {
            InputSourceHelper.inputSource(for: bundleID)
        }
    }

    guard let inputSource = maybeInputSource else {
        NSLog("Fatal error: Cannot find input source \(bundleID) after registration.")
        return -1
    }

    if !InputSourceHelper.inputSourceEnabled(for: inputSource) {
        NSLog("Enabling input source \(bundleID) at \(bundleUrl.absoluteString).")
        let status = InputSourceHelper.enable(inputSource: inputSource)
        if !status {
            NSLog("Fatal error: Cannot enable input source \(bundleID).")
            return -1
        }
        if !InputSourceHelper.inputSourceEnabled(for: inputSource) {
            NSLog("Fatal error: Cannot enable input source \(bundleID).")
            return -1
        }
    }

    if shouldEnableAll {
        let enabled = InputSourceHelper.enableAllInputMode(for: bundleID)
        NSLog(enabled ? "All input sources enabled for \(bundleID)" : "Cannot enable all input sources for \(bundleID), but this is ignored")
    }
    if shouldSelect {
        guard let inputMode = retry(action: {
            InputSourceHelper.inputMode(bopomofoModeID, for: bundleID)
        }) else {
            NSLog("Fatal error: Cannot find input mode \(bopomofoModeID) for \(bundleID).")
            return -1
        }

        if !InputSourceHelper.inputSourceEnabled(for: inputMode) {
            let enabled = InputSourceHelper.enable(inputSource: inputMode)
            if !enabled {
                NSLog("Fatal error: Cannot enable input mode \(bopomofoModeID).")
                return -1
            }
        }

        let selected = retry(action: {
            InputSourceHelper.select(inputSource: inputMode) ? true : nil
        }) ?? false
        if !selected {
            NSLog("Fatal error: Cannot select input mode \(bopomofoModeID).")
            return -1
        }
        NSLog("Selected input mode \(bopomofoModeID) for \(bundleID).")
    }
    return 0
}

private func patch() -> Int32 {
    guard CommandLine.arguments.count > 2 else {
        print("Usage: McBopomofo patch sync|check-release|download-release|open-release|diagnostics|reset-diagnostics")
        return 2
    }

    Preferences.populateDefaults()

    do {
        switch CommandLine.arguments[2] {
        case "sync":
            let report = try BroccoliPatchManager.syncDictionaries()
            print("Synced patch dictionaries:")
            for file in report.updatedFiles {
                print("updated \(file)")
            }
            for file in report.uploadedFiles {
                print("uploaded \(file)")
            }
            for file in report.backupFiles {
                print("backup \(file)")
            }
            return 0
        case "diagnostics":
            print(BroccoliDiagnostics.readLog(), terminator: "")
            return 0
        case "reset-diagnostics":
            BroccoliDiagnostics.reset()
            print("Diagnostics log cleared.")
            return 0
        case "check-release":
            let release = try BroccoliPatchManager.latestRelease()
            print("Latest release: \(release.tagName)")
            print(release.htmlURL.absoluteString)
            if let assetName = release.assetName {
                print("Asset: \(assetName)")
            }
            return 0
        case "download-release":
            let destination = try BroccoliPatchManager.downloadLatestReleaseAsset()
            print("Downloaded latest release asset:")
            print(destination.path)
            NSWorkspace.shared.open(destination)
            return 0
        case "open-release":
            NSWorkspace.shared.open(BroccoliPatchManager.releasePageURL)
            return 0
        default:
            print("Unknown patch command: \(CommandLine.arguments[2])")
            print("Usage: McBopomofo patch sync|check-release|download-release|open-release|diagnostics|reset-diagnostics")
            return 2
        }
    } catch {
        print("Patch failed: \(error.localizedDescription)")
        return 1
    }
}

let kConnectionName = "McBopomofo_1_Connection"

if CommandLine.arguments.count > 1 {
    if CommandLine.arguments[1] == "install" {
        let exitCode = install()
        exit(exitCode)
    }
    if CommandLine.arguments[1] == "patch" {
        let exitCode = patch()
        exit(exitCode)
    }
}

guard let mainNibName = Bundle.main.infoDictionary?["NSMainNibFile"] as? String else {
    NSLog("Fatal error: NSMainNibFile key not defined in Info.plist.");
    exit(-1)
}

let loaded = Bundle.main.loadNibNamed(mainNibName, owner: NSApp, topLevelObjects: nil)
if !loaded {
    NSLog("Fatal error: Cannot load \(mainNibName).")
    exit(-1)
}

guard let bundleID = Bundle.main.bundleIdentifier, let server = IMKServer(name: kConnectionName, bundleIdentifier: bundleID) else {
    NSLog("Fatal error: Cannot initialize input method server with connection \(kConnectionName).")
    exit(-1)
}

Preferences.populateDefaults()
NSApp.run()
