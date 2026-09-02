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

import Testing

@testable import McBopomofo

@Suite("Broccoli Patch Sync Tests")
final class BroccoliPatchSyncTests {
    @Test("Initial sync keeps both local and remote additions")
    func testInitialSyncUnionKeepsBothSides() {
        let local = "alpha a\nlocal c\n"
        let remote = "beta b\nremote d\n"
        let merged = BroccoliPatchDictionaryMerger.merge(
            kind: .userPhrases,
            base: nil,
            local: local,
            remote: remote
        )

        #expect(merged == "beta b\nremote d\nalpha a\nlocal c\n")
    }

    @Test("Three-way merge keeps concurrent additions and local deletions")
    func testThreeWayMergeKeepsConcurrentAdditionsAndLocalDeletes() {
        let base = "alpha a\nbeta b\n"
        let local = "alpha a\nlocal c\n"
        let remote = "alpha a\nbeta b\nremote d\n"
        let merged = BroccoliPatchDictionaryMerger.merge(
            kind: .userPhrases,
            base: base,
            local: local,
            remote: remote
        )

        #expect(merged == "alpha a\nremote d\nlocal c\n")
        #expect(!merged.contains("beta b"))
    }

    @Test("Smart mixed words merge is case-insensitive and additive")
    func testSmartMixedWordsMergeAddsUniqueWords() {
        let base = "API\nmacOS\n"
        let local = "API\nSwift\n"
        let remote = "api\nChrome\n"
        let merged = BroccoliPatchDictionaryMerger.merge(
            kind: .smartMixedASCIIWords,
            base: base,
            local: local,
            remote: remote
        )

        #expect(merged == "api\nChrome\nSwift\n")
    }
}
