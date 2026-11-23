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

#import "LanguageModelManager.h"
#import "LanguageModelManager+Privates.h"
#import "McBopomofo-Swift.h"

#include "UTF8Helper.h"
#include "AssociatedPhrasesV2.h"
#include "SmartMixed.h"
#include "TextAssist.h"

#include <memory>
#include <mutex>

@import OpenCCBridge;

static const int kUserOverrideModelCapacity = 500;
static const double kObservedOverrideHalflife = 5400.0; // 1.5 hr.

static McBopomofo::McBopomofoLM gLanguageModelMcBopomofo;
static McBopomofo::McBopomofoLM gLanguageModelPlainBopomofo;
static McBopomofo::UserOverrideModel gUserOverrideModel(kUserOverrideModelCapacity, kObservedOverrideHalflife);

// Broccoli SmartInput (T07): a second, slow-decaying model so a correction made
// today is still remembered next week. The short-term model above keeps the
// upstream behaviour; both are saved to disk so a restart loses neither.
static const int kLongTermUserOverrideModelCapacity = 2000;
static const double kLongTermObservedOverrideHalflife = 7.0 * 24.0 * 3600.0; // 1 week.
static McBopomofo::UserOverrideModel gLongTermUserOverrideModel(kLongTermUserOverrideModelCapacity, kLongTermObservedOverrideHalflife);
static BOOL gUserOverrideModelsLoaded = NO;

// Broccoli SmartInput (A1): smart mixed word lists live in memory. The known
// words (whitelists + user ASCII phrases) are rebuilt only when their files
// change; the English dictionary loads once, off the main thread.
static std::mutex gSmartMixedDictionaryMutex;
static std::shared_ptr<const McBopomofo::SmartMixed::Lexicon> gSmartMixedDictionary;
static std::shared_ptr<const McBopomofo::SmartMixed::Lexicon> gSmartMixedKnownWords;
static BOOL gSmartMixedKnownWordsDirty = YES;
static CFAbsoluteTime gSmartMixedKnownWordsLastCheck = 0;
static NSTimeInterval gSmartMixedLocalWordsModified = 0;
static NSTimeInterval gSmartMixedUserPhrasesModified = 0;
static McBopomofo::SmartMixed::LearnedChoices gSmartMixedLearnedChoices;
static BOOL gSmartMixedLearnedChoicesLoaded = NO;
static McBopomofo::TextAssist::TypingGuard gTypingGuard;
static McBopomofo::VariantAnnotator gVariantAnnotator;

static NSString *const kUserDataTemplateName = @"template-data";
static NSString *const kUserDataPlainBopomofoTemplateName = @"template-data-plain-bpmf";
static NSString *const kExcludedPhrasesMcBopomofoTemplateName = @"template-exclude-phrases";
static NSString *const kExcludedPhrasesPlainBopomofoTemplateName = @"template-exclude-phrases-plain-bpmf";
static NSString *const kPhraseReplacementTemplateName = @"template-phrases-replacement";
static NSString *const kSmartMixedASCIIWordsTemplateName = @"smart-mixed-ascii-words";
static NSString *const kTemplateExtension = @".txt";

static NSCharacterSet *SmartMixedASCIILettersAndDigits()
{
    static NSCharacterSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"];
    });
    return set;
}

static NSTimeInterval SmartMixedModificationTime(NSString *path)
{
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *date = attributes[NSFileModificationDate];
    return date != nil ? date.timeIntervalSince1970 : 0;
}

static NSString *SmartMixedReadFile(NSString *path)
{
    if (path == nil) {
        return nil;
    }
    return [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

static BOOL SmartMixedWriteFile(NSString *content, NSString *path)
{
    NSError *error = nil;
    BOOL written = [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!written) {
        NSLog(@"Failed to write %@: %@", path, error);
    }
    return written;
}

// Unit tests run inside the real input method's container; they must not
// overwrite what the user has learned.
static BOOL BroccoliIsRunningUnitTests()
{
    return NSClassFromString(@"XCTestCase") != nil;
}

static dispatch_queue_t BroccoliPersistenceQueue()
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.broccoli.smartinput.persistence", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@implementation LanguageModelManager

static void LTLoadLanguageModelFile(NSString *filenameWithoutExtension, McBopomofo::McBopomofoLM& lm)
{
    Class cls = NSClassFromString(@"McBopomofoInputMethodController");
    NSString *dataPath = [[NSBundle bundleForClass:cls] pathForResource:filenameWithoutExtension ofType:@"txt"];
    lm.loadLanguageModel(dataPath.UTF8String);
}

static void LTLoadAssociatedPhrases(McBopomofo::McBopomofoLM& lm)
{
    Class cls = NSClassFromString(@"McBopomofoInputMethodController");
    NSString *dataPath = [[NSBundle bundleForClass:cls] pathForResource:@"associated-phrases-v2" ofType:@"txt"];
    lm.loadAssociatedPhrasesV2(dataPath.UTF8String);
}

static void LTLoadVariantAnnotatorData()
{
    Class cls = NSClassFromString(@"McBopomofoInputMethodController");
    NSString *puaDataPath = [[NSBundle bundleForClass:cls] pathForResource:@"bpmfvs-pua" ofType:@"txt"];
    if (puaDataPath == nil) {
        NSLog(@"Error: No PUA data found in bundle");
        return;
    }

    NSString *variantsDataPath = [[NSBundle bundleForClass:cls] pathForResource:@"bpmfvs-variants" ofType:@"txt"];
    if (variantsDataPath == nil) {
        NSLog(@"Error: No variants data found in bundle");
        return;
    }

    BOOL puaLoaded = gVariantAnnotator.loadPUAFile(puaDataPath.UTF8String);
    BOOL variantsLoaded = gVariantAnnotator.loadVariantsFile(variantsDataPath.UTF8String);
    if (!gVariantAnnotator.loaded()) {
        NSLog(@"Error: VariantAnnotator not ready, puaLoaded: %d, variantsLoaded: %d", puaLoaded, variantsLoaded);
    }
}

+ (void)loadDataModels
{
    [self preloadSmartMixedDictionary];
    if (!gLanguageModelMcBopomofo.isDataModelLoaded()) {
        LTLoadLanguageModelFile(@"data", gLanguageModelMcBopomofo);
    }
    if (!gLanguageModelMcBopomofo.isAssociatedPhrasesV2Loaded()) {
        LTLoadAssociatedPhrases(gLanguageModelMcBopomofo);
    }

    if (!gLanguageModelPlainBopomofo.isDataModelLoaded()) {
        LTLoadLanguageModelFile(@"data-plain-bpmf", gLanguageModelPlainBopomofo);
    }
    if (!gLanguageModelPlainBopomofo.isAssociatedPhrasesV2Loaded()) {
        LTLoadAssociatedPhrases(gLanguageModelPlainBopomofo);
    }
    if (!gVariantAnnotator.loaded()) {
        LTLoadVariantAnnotatorData();
    }
}

+ (void)loadDataModel:(InputMode)mode
{
    [self preloadSmartMixedDictionary];
    if ([mode isEqualToString:InputModeBopomofo]) {
        if (!gLanguageModelMcBopomofo.isDataModelLoaded()) {
            LTLoadLanguageModelFile(@"data", gLanguageModelMcBopomofo);
        }
        if (!gLanguageModelMcBopomofo.isAssociatedPhrasesV2Loaded()) {
            LTLoadAssociatedPhrases(gLanguageModelMcBopomofo);
        }
        if (!gVariantAnnotator.loaded()) {
            LTLoadVariantAnnotatorData();
        }
    }

    if ([mode isEqualToString:InputModePlainBopomofo]) {
        if (!gLanguageModelPlainBopomofo.isDataModelLoaded()) {
            LTLoadLanguageModelFile(@"data-plain-bpmf", gLanguageModelPlainBopomofo);
        }
        if (!gLanguageModelPlainBopomofo.isAssociatedPhrasesV2Loaded()) {
            LTLoadAssociatedPhrases(gLanguageModelPlainBopomofo);
        }
        if (!gVariantAnnotator.loaded()) {
            LTLoadVariantAnnotatorData();
        }
    }
}

+ (void)loadUserPhrasesWithPlainBopomofoEnabled:(BOOL)userPhraseForPlainBopomofo
{
    gSmartMixedKnownWordsDirty = YES;
    gLanguageModelMcBopomofo.loadUserPhrases([self userPhrasesDataPathMcBopomofo].UTF8String, [self excludedPhrasesDataPathMcBopomofo].UTF8String);
    gLanguageModelPlainBopomofo.loadUserPhrases(userPhraseForPlainBopomofo ? [self userPhrasesDataPathPlainBopomofo].UTF8String : NULL,
        [self excludedPhrasesDataPathPlainBopomofo].UTF8String);
}

+ (void)loadCandidateOrder
{
    gLanguageModelMcBopomofo.loadCandidateOrder([self candidateOrderDataPath].UTF8String);
    gLanguageModelPlainBopomofo.loadCandidateOrder([self candidateOrderDataPath].UTF8String);
}

// Rewrites the ordering for one reading. The file is small and rewritten whole
// so that a line is replaced rather than accumulating stale duplicates.
+ (BOOL)writeCandidateOrderForReading:(NSString *)reading values:(NSArray<NSString *> *)values
{
    if (reading.length == 0 || values.count == 0) {
        return NO;
    }
    if (![self checkIfUserDataFolderExists]) {
        return NO;
    }

    NSString *path = [self candidateOrderDataPath];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    NSString *existing = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (existing.length > 0) {
        for (NSString *line in [existing componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length == 0) {
                continue;
            }
            if ([trimmed hasPrefix:@"#"]) {
                [lines addObject:trimmed];
                continue;
            }
            NSArray<NSString *> *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (parts.count > 0 && [parts.firstObject isEqualToString:reading]) {
                continue;
            }
            [lines addObject:trimmed];
        }
    } else {
        [lines addObject:@"# Preferred candidate order."];
        [lines addObject:@"# One reading per line, followed by the values that should come first."];
    }

    [lines addObject:[NSString stringWithFormat:@"%@ %@", reading, [values componentsJoinedByString:@" "]]];

    NSString *output = [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    NSError *error = nil;
    BOOL result = [output writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!result) {
        NSLog(@"Failed to write candidate order: %@", error);
    }
    return result;
}

+ (void)loadUserPhraseReplacement
{
    gLanguageModelMcBopomofo.loadPhraseReplacementMap([self phraseReplacementDataPathMcBopomofo].UTF8String);
}

+ (void)setupDataModelValueConverter
{
    auto macroConverter = [](const std::string& input) {
        NSString *inputText = @(input.c_str());
        NSString *handled = [[InputMacroController shared] handle:inputText];
        return std::string(handled.UTF8String);
    };

    auto converter = [](const std::string& input) {
        if (!Preferences.chineseConversionEnabled) {
            return input;
        }

        if (Preferences.chineseConversionStyle == 0) {
            return input;
        }

        NSString *text = [[OpenCCBridge sharedInstance] convertToSimplified:@(input.c_str())];
        return std::string(text.UTF8String);
    };

    gLanguageModelMcBopomofo.setMacroConverter(macroConverter);
    gLanguageModelMcBopomofo.setExternalConverter(converter);
    gLanguageModelPlainBopomofo.setExternalConverter(converter);
}

+ (BOOL)checkIfUserDataFolderExists
{
    NSString *folderPath = [self dataFolderPath];
    BOOL isFolder = NO;
    BOOL folderExist = [[NSFileManager defaultManager] fileExistsAtPath:folderPath isDirectory:&isFolder];
    if (folderExist && !isFolder) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:folderPath error:&error];
        if (error) {
            NSLog(@"Failed to remove folder %@", error);
            return NO;
        }
        folderExist = NO;
    }
    if (!folderExist) {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:folderPath withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"Failed to create folder %@", error);
            return NO;
        }
    }
    return YES;
}

+ (BOOL)ensureFileExists:(NSString *)filePath populateWithTemplate:(NSString *)templateBasename extension:(NSString *)ext
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {

        NSURL *templateURL = [[NSBundle mainBundle] URLForResource:templateBasename withExtension:ext];
        NSData *templateData;
        if (templateURL) {
            templateData = [NSData dataWithContentsOfURL:templateURL];
        } else {
            templateData = [@"" dataUsingEncoding:NSUTF8StringEncoding];
        }

        BOOL result = [templateData writeToFile:filePath atomically:YES];
        if (!result) {
            NSLog(@"Failed to write file");
            return NO;
        }
    }
    return YES;
}

+ (BOOL)checkIfUserLanguageModelFilesExist
{
    if (![self checkIfUserDataFolderExists]) {
        return NO;
    }
    if (![self ensureFileExists:[self userPhrasesDataPathMcBopomofo] populateWithTemplate:kUserDataTemplateName extension:kTemplateExtension]) {
        return NO;
    }
    if (![self ensureFileExists:[self userPhrasesDataPathPlainBopomofo] populateWithTemplate:kUserDataPlainBopomofoTemplateName extension:kTemplateExtension]) {
        return NO;
    }
    if (![self ensureFileExists:[self excludedPhrasesDataPathMcBopomofo] populateWithTemplate:kExcludedPhrasesMcBopomofoTemplateName extension:kTemplateExtension]) {
        return NO;
    }
    if (![self ensureFileExists:[self excludedPhrasesDataPathPlainBopomofo] populateWithTemplate:kExcludedPhrasesPlainBopomofoTemplateName extension:kTemplateExtension]) {
        return NO;
    }
    if (![self ensureFileExists:[self phraseReplacementDataPathMcBopomofo] populateWithTemplate:kPhraseReplacementTemplateName extension:kTemplateExtension]) {
        return NO;
    }
    if (![self ensureFileExists:[self smartMixedASCIIWordsDataPath] populateWithTemplate:kSmartMixedASCIIWordsTemplateName extension:kTemplateExtension]) {
        return NO;
    }
    return YES;
}

+ (BOOL)checkIfUserPhraseExist:(NSString *)userPhrase key:(NSString *)key NS_SWIFT_NAME(checkIfExist(userPhrase:key:))
{
    std::string unigramKey(key.UTF8String);
    auto unigrams = gLanguageModelMcBopomofo.getUnigrams(unigramKey);
    std::string userPhraseString(userPhrase.UTF8String);
    for (const auto& unigram : unigrams) {
        if (unigram.value() == userPhraseString) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)_checkIfPhrase:(NSString *)phrase existAtPath:(NSString *)path
{
    NSString *exactPhrase = nil;
    NSString *key = nil;
    NSArray *components = [phrase componentsSeparatedByString:@" "];
    if (components.count != 2) {
        return NO;
    }
    exactPhrase = components[0];
    key = components[1];

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }
    NSError *error = nil;
    NSString *content = [[NSString alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        return NO;
    }
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray *lineComponents = [trimmed componentsSeparatedByString:@" "];
        if (lineComponents.count != 2) {
            continue;
        }
        if ([lineComponents[0] isEqualToString:exactPhrase] &&
            [lineComponents[1] isEqualToString:key]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)_writePhrase:(NSString *)phrase atEndOfPath:(NSString *)path
{
    BOOL addLineBreakAtFront = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSError *error = nil;
        NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
        unsigned long long fileSize = [attr fileSize];
        if (!error && fileSize) {
            NSFileHandle *readFile = [NSFileHandle fileHandleForReadingAtPath:path];
            if (readFile) {
                [readFile seekToFileOffset:fileSize - 1];
                NSData *data = [readFile readDataToEndOfFile];
                const void *bytes = data.bytes;
                if (*(char *)bytes != '\n') {
                    addLineBreakAtFront = YES;
                }
                [readFile closeFile];
            }
        }
    }
    NSMutableString *currentMarkedPhrase = [NSMutableString string];
    if (addLineBreakAtFront) {
        [currentMarkedPhrase appendString:@"\n"];
    }
    [currentMarkedPhrase appendString:phrase];
    [currentMarkedPhrase appendString:@"\n"];

    NSFileHandle *writeFile = [NSFileHandle fileHandleForUpdatingAtPath:path];
    if (!writeFile) {
        return NO;
    }

    [writeFile seekToEndOfFile];
    NSData *data = [currentMarkedPhrase dataUsingEncoding:NSUTF8StringEncoding];
    [writeFile writeData:data];
    [writeFile closeFile];
    return YES;
}

+ (BOOL)_removePhrase:(NSString *)phrase atPath:(NSString *)path
{
    NSString *exactPhrase = nil;
    NSString *key = nil;
    NSArray *components = [phrase componentsSeparatedByString:@" "];
    if (components.count != 2) {
        return NO;
    }
    exactPhrase = components[0];
    key = components[1];

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }
    NSError *error = nil;
    NSString *content = [[NSString alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        return NO;
    }
    NSArray *lines = [content componentsSeparatedByString:@"\n"];

    BOOL result = NO;
    NSMutableString *mutableString = [NSMutableString string];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray *lineComponents = [trimmed componentsSeparatedByString:@" "];
        if (lineComponents.count != 2) {
            [mutableString appendString:line];
            [mutableString appendString:@"\n"];
            continue;
        }
        if ([lineComponents[0] isEqualToString:exactPhrase] &&
            [lineComponents[1] isEqualToString:key]) {
            result = YES;
            continue;
        }
        [mutableString appendString:line];
        [mutableString appendString:@"\n"];
    }
    if (result) {
        NSError *writeError;
        [mutableString writeToURL:[NSURL fileURLWithPath:path] atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
        if (writeError != nil) {
            return NO;
        }
        return YES;
    }

    return NO;
}

+ (BOOL)userASCIIPhraseHasPrefix:(NSString *)prefix
{
    if (prefix.length == 0) {
        return NO;
    }

    NSString *lowercasePrefix = prefix.lowercaseString;
    NSString *includePath = [self userPhrasesDataPathMcBopomofo];
    if (![[NSFileManager defaultManager] fileExistsAtPath:includePath]) {
        return NO;
    }

    NSError *error = nil;
    NSString *content = [[NSString alloc] initWithContentsOfURL:[NSURL fileURLWithPath:includePath] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        return NO;
    }

    NSCharacterSet *asciiLettersAndDigits = SmartMixedASCIILettersAndDigits();
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) {
            continue;
        }

        NSArray *lineComponents = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (lineComponents.count < 2) {
            continue;
        }

        NSString *phrase = lineComponents[0];
        if (phrase.length == 0 || [phrase rangeOfCharacterFromSet:asciiLettersAndDigits.invertedSet].location != NSNotFound) {
            continue;
        }

        if ([phrase.lowercaseString hasPrefix:lowercasePrefix]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)userASCIIPhraseMatches:(NSString *)phrase
{
    if (phrase.length == 0) {
        return NO;
    }

    NSString *lowercasePhrase = phrase.lowercaseString;
    NSString *includePath = [self userPhrasesDataPathMcBopomofo];
    if (![[NSFileManager defaultManager] fileExistsAtPath:includePath]) {
        return NO;
    }

    NSError *error = nil;
    NSString *content = [[NSString alloc] initWithContentsOfURL:[NSURL fileURLWithPath:includePath] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        return NO;
    }

    NSCharacterSet *asciiLettersAndDigits = SmartMixedASCIILettersAndDigits();
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) {
            continue;
        }

        NSArray *lineComponents = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (lineComponents.count < 2) {
            continue;
        }

        NSString *userPhrase = lineComponents[0];
        if (userPhrase.length == 0 || [userPhrase rangeOfCharacterFromSet:asciiLettersAndDigits.invertedSet].location != NSNotFound) {
            continue;
        }

        if ([userPhrase.lowercaseString isEqualToString:lowercasePhrase]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)bundledSmartMixedASCIIWordHasPrefix:(NSString *)prefix
{
    if (prefix.length == 0) {
        return NO;
    }

    Class cls = NSClassFromString(@"McBopomofoInputMethodController");
    NSString *path = [[NSBundle bundleForClass:cls] pathForResource:@"smart-mixed-ascii-words" ofType:@"txt"];
    if (path == nil || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }

    NSError *error = nil;
    NSString *content = [[NSString alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        return NO;
    }

    NSString *lowercasePrefix = prefix.lowercaseString;
    NSCharacterSet *asciiLettersAndDigits = SmartMixedASCIILettersAndDigits();
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *word = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (word.length == 0 || [word hasPrefix:@"#"]) {
            continue;
        }
        if ([word rangeOfCharacterFromSet:asciiLettersAndDigits.invertedSet].location != NSNotFound) {
            continue;
        }
        if ([word.lowercaseString hasPrefix:lowercasePrefix]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)bundledSmartMixedASCIIWordMatches:(NSString *)phrase
{
    if (phrase.length == 0) {
        return NO;
    }

    Class cls = NSClassFromString(@"McBopomofoInputMethodController");
    NSString *path = [[NSBundle bundleForClass:cls] pathForResource:@"smart-mixed-ascii-words" ofType:@"txt"];
    if (path == nil || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }

    NSError *error = nil;
    NSString *content = [[NSString alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        return NO;
    }

    NSString *lowercasePhrase = phrase.lowercaseString;
    NSCharacterSet *asciiLettersAndDigits = SmartMixedASCIILettersAndDigits();
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *word = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (word.length == 0 || [word hasPrefix:@"#"]) {
            continue;
        }
        if ([word rangeOfCharacterFromSet:asciiLettersAndDigits.invertedSet].location != NSNotFound) {
            continue;
        }
        if ([word.lowercaseString isEqualToString:lowercasePhrase]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)localSmartMixedASCIIWordHasPrefix:(NSString *)prefix
{
    if (prefix.length == 0) {
        return NO;
    }

    NSString *path = [self smartMixedASCIIWordsDataPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }

    NSError *error = nil;
    NSString *content = [[NSString alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        return NO;
    }

    NSString *lowercasePrefix = prefix.lowercaseString;
    NSCharacterSet *asciiLettersAndDigits = SmartMixedASCIILettersAndDigits();
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *word = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (word.length == 0 || [word hasPrefix:@"#"]) {
            continue;
        }
        if ([word rangeOfCharacterFromSet:asciiLettersAndDigits.invertedSet].location != NSNotFound) {
            continue;
        }
        if ([word.lowercaseString hasPrefix:lowercasePrefix]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)localSmartMixedASCIIWordMatches:(NSString *)phrase
{
    if (phrase.length == 0) {
        return NO;
    }

    NSString *path = [self smartMixedASCIIWordsDataPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }

    NSError *error = nil;
    NSString *content = [[NSString alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        return NO;
    }

    NSString *lowercasePhrase = phrase.lowercaseString;
    NSCharacterSet *asciiLettersAndDigits = SmartMixedASCIILettersAndDigits();
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *word = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (word.length == 0 || [word hasPrefix:@"#"]) {
            continue;
        }
        if ([word rangeOfCharacterFromSet:asciiLettersAndDigits.invertedSet].location != NSNotFound) {
            continue;
        }
        if ([word.lowercaseString isEqualToString:lowercasePhrase]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)smartMixedASCIIPhraseHasPrefix:(NSString *)prefix
{
    auto known = [self smartMixedKnownWords];
    return prefix.length > 0 && known != nullptr && known->hasPrefix(prefix.UTF8String);
}

+ (BOOL)smartMixedASCIIPhraseMatches:(NSString *)phrase
{
    auto known = [self smartMixedKnownWords];
    return phrase.length > 0 && known != nullptr && known->contains(phrase.UTF8String);
}

+ (BOOL)smartMixedSystemDictionaryASCIIWordHasPrefix:(NSString *)prefix
{
    // Now backed by the bundled English lexicon instead of /usr/share/dict/words.
    if (prefix.length < 2) {
        return NO;
    }
    auto dictionary = [self smartMixedDictionary];
    return dictionary != nullptr && dictionary->hasProperPrefix(prefix.UTF8String);
}

+ (BOOL)smartMixedSystemDictionaryASCIIWordMatches:(NSString *)phrase
{
    if (phrase.length < 3) {
        return NO;
    }
    auto dictionary = [self smartMixedDictionary];
    return dictionary != nullptr && dictionary->contains(phrase.UTF8String);
}

+ (BOOL)writeUserPhrase:(NSString *)userPhrase
{
    if (![self checkIfUserLanguageModelFilesExist]) {
        return NO;
    }

    NSString *excludePath = [self excludedPhrasesDataPathMcBopomofo];
    [self _removePhrase:userPhrase atPath:excludePath];

    NSString *includePath = [self userPhrasesDataPathMcBopomofo];
    if ([self _checkIfPhrase:userPhrase existAtPath:includePath]) {
        return NO;
    }
    BOOL result = [self _writePhrase:userPhrase atEndOfPath:includePath];

    //  We use FSEventStream to monitor the change of the user phrase folder,
    //  so we don't have to load data here.
    //  [self loadUserPhrases];
    return result;
}

+ (BOOL)deleteUserPhrase:(NSString *)userPhrase
{
    if (![self checkIfUserLanguageModelFilesExist]) {
        return NO;
    }

    NSString *includePath = [self userPhrasesDataPathMcBopomofo];
    return [self _removePhrase:userPhrase atPath:includePath];
}

+ (BOOL)removeUserPhrase:(NSString *)userPhrase
{
    if (![self checkIfUserLanguageModelFilesExist]) {
        return NO;
    }

    NSString *includePath = [self userPhrasesDataPathMcBopomofo];
    [self _removePhrase:userPhrase atPath:includePath];

    NSString *excludePath = [self excludedPhrasesDataPathMcBopomofo];
    if ([self _checkIfPhrase:userPhrase existAtPath:excludePath]) {
        return NO;
    }
    BOOL result = [self _writePhrase:userPhrase atEndOfPath:excludePath];

    //  We use FSEventStream to monitor the change of the user phrase folder,
    //  so we don't have to load data here.
    //  [self loadUserPhrases];
    return result;
}

+ (NSString *)dataFolderPath
{
    BOOL useCustomLocation = Preferences.useCustomUserPhraseLocation;
    if (!useCustomLocation) {
        return [UserPhraseLocationHelper defaultUserPhraseLocation];
    }
    return Preferences.customUserPhraseLocation;
}

+ (NSString *)userPhrasesDataPathMcBopomofo
{
    return [[self dataFolderPath] stringByAppendingPathComponent:@"data.txt"];
}

+ (NSString *)userPhrasesDataPathPlainBopomofo
{
    return [[self dataFolderPath] stringByAppendingPathComponent:@"data-plain-bpmf.txt"];
}

+ (NSString *)excludedPhrasesDataPathMcBopomofo
{
    return [[self dataFolderPath] stringByAppendingPathComponent:@"exclude-phrases.txt"];
}

+ (NSString *)excludedPhrasesDataPathPlainBopomofo
{
    return [[self dataFolderPath] stringByAppendingPathComponent:@"exclude-phrases-plain-bpmf.txt"];
}

+ (NSString *)phraseReplacementDataPathMcBopomofo
{
    return [[self dataFolderPath] stringByAppendingPathComponent:@"phrases-replacement.txt"];
}

+ (NSString *)candidateOrderDataPath
{
    return [[self dataFolderPath] stringByAppendingPathComponent:@"candidate-order.txt"];
}

+ (NSString *)smartMixedASCIIWordsDataPath
{
    return [[self dataFolderPath] stringByAppendingPathComponent:@"smart-mixed-ascii-words.txt"];
}

+ (McBopomofo::McBopomofoLM *)languageModelMcBopomofo
{
    return &gLanguageModelMcBopomofo;
}

+ (McBopomofo::McBopomofoLM *)languageModelPlainBopomofo
{
    return &gLanguageModelPlainBopomofo;
}

+ (McBopomofo::UserOverrideModel *)userOverrideModel
{
    [self loadUserOverrideModels];
    return &gUserOverrideModel;
}

+ (McBopomofo::VariantAnnotator *)variantAnnotator
{
    return &gVariantAnnotator;
}

+ (BOOL)phraseReplacementEnabled
{
    return gLanguageModelMcBopomofo.phraseReplacementEnabled();
}

+ (void)setPhraseReplacementEnabled:(BOOL)phraseReplacementEnabled
{
    gLanguageModelMcBopomofo.setPhraseReplacementEnabled(phraseReplacementEnabled);
}

+ (nullable NSString *)readingFor:(NSString *)phrase
{
    if (!gLanguageModelMcBopomofo.isDataModelLoaded()) {
        [self loadDataModel:InputModeBopomofo];
    }

    std::string reading = gLanguageModelMcBopomofo.getReading(phrase.UTF8String);
    return !reading.empty() ? @(reading.c_str()) : nil;
}

+ (NSString *)annotateVariantForCharacters:(NSString *)inCharacters readings:(NSString *)inReadings
{
    McBopomofo::VariantAnnotator *annotator = LanguageModelManager.variantAnnotator;
    if (!annotator || !annotator->loaded()) {
        return inCharacters;
    }

    std::string value(inCharacters.UTF8String);
    std::string readingString(inReadings.UTF8String);
    std::vector<std::string> characters = McBopomofo::Split(value);
    std::vector<std::string> readings = McBopomofo::AssociatedPhrasesV2::SplitReadings(readingString);

    McBopomofo::VariantAnnotator::CombinedResult result = LanguageModelManager.variantAnnotator->annotate(characters,
                                                                                                          readings);
    return [[NSString alloc] initWithUTF8String:result.annotatedString.c_str()];
}



#pragma mark - Broccoli SmartInput: smart mixed word lists (A1, A2)

+ (void)invalidateSmartMixedKnownWords
{
    gSmartMixedKnownWordsDirty = YES;
}

+ (std::shared_ptr<const McBopomofo::SmartMixed::Lexicon>)smartMixedKnownWords
{
    // Called on every smart mixed keystroke: a cheap time check, then at most
    // two stat() calls every couple of seconds. Files are read only when they
    // actually changed.
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!gSmartMixedKnownWordsDirty && gSmartMixedKnownWords != nullptr && now - gSmartMixedKnownWordsLastCheck < 2.0) {
        return gSmartMixedKnownWords;
    }
    gSmartMixedKnownWordsLastCheck = now;

    NSString *localPath = [self smartMixedASCIIWordsDataPath];
    NSString *userPath = [self userPhrasesDataPathMcBopomofo];
    NSTimeInterval localModified = SmartMixedModificationTime(localPath);
    NSTimeInterval userModified = SmartMixedModificationTime(userPath);
    if (!gSmartMixedKnownWordsDirty && gSmartMixedKnownWords != nullptr &&
        localModified == gSmartMixedLocalWordsModified && userModified == gSmartMixedUserPhrasesModified) {
        return gSmartMixedKnownWords;
    }

    auto lexicon = std::make_shared<McBopomofo::SmartMixed::Lexicon>();
    Class cls = NSClassFromString(@"McBopomofoInputMethodController");
    NSString *bundledPath = [[NSBundle bundleForClass:cls] pathForResource:@"smart-mixed-ascii-words" ofType:@"txt"];
    for (NSString *path in @[ (bundledPath != nil ? bundledPath : @""), localPath ]) {
        NSString *content = SmartMixedReadFile(path.length ? path : nil);
        if (content != nil) {
            lexicon->addLines(content.UTF8String, McBopomofo::SmartMixed::kWhitelistTier);
        }
    }
    NSString *userPhrases = SmartMixedReadFile(userPath);
    for (NSString *line in [userPhrases componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) {
            continue;
        }
        NSArray<NSString *> *components = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (components.count >= 2) {
            // add() ignores anything that is not ASCII letters and digits.
            lexicon->add(components[0].UTF8String, McBopomofo::SmartMixed::kWhitelistTier);
        }
    }
    lexicon->finalize();

    gSmartMixedKnownWords = lexicon;
    gSmartMixedLocalWordsModified = localModified;
    gSmartMixedUserPhrasesModified = userModified;
    gSmartMixedKnownWordsDirty = NO;
    return gSmartMixedKnownWords;
}

+ (void)preloadSmartMixedDictionary
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"McBopomofoInputMethodController");
        NSString *path = [[NSBundle bundleForClass:cls] pathForResource:@"smart-mixed-english-lexicon" ofType:@"txt"];
        if (path == nil) {
            NSLog(@"Smart mixed English lexicon is missing from the bundle");
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString *content = SmartMixedReadFile(path);
            auto lexicon = std::make_shared<McBopomofo::SmartMixed::Lexicon>();
            if (content != nil) {
                lexicon->addLines(content.UTF8String, McBopomofo::SmartMixed::kDefaultTier);
            }
            lexicon->finalize();
            std::lock_guard<std::mutex> lock(gSmartMixedDictionaryMutex);
            gSmartMixedDictionary = lexicon;
        });
    });
}

+ (std::shared_ptr<const McBopomofo::SmartMixed::Lexicon>)smartMixedDictionary
{
    [self preloadSmartMixedDictionary];
    std::lock_guard<std::mutex> lock(gSmartMixedDictionaryMutex);
    // nullptr until the background load finishes; callers treat that as "no
    // dictionary evidence" rather than waiting.
    return gSmartMixedDictionary;
}

#pragma mark - Broccoli SmartInput: learned smart mixed choices (A6)

+ (NSString *)smartMixedLearnedChoicesDataPath
{
    return [[self dataFolderPath] stringByAppendingPathComponent:@"smart-mixed-learned.txt"];
}

+ (const McBopomofo::SmartMixed::LearnedChoices *)smartMixedLearnedChoices
{
    if (!gSmartMixedLearnedChoicesLoaded) {
        gSmartMixedLearnedChoicesLoaded = YES;
        if (BroccoliIsRunningUnitTests()) {
            return &gSmartMixedLearnedChoices;
        }
        NSString *content = SmartMixedReadFile([self smartMixedLearnedChoicesDataPath]);
        if (content != nil) {
            gSmartMixedLearnedChoices.load(content.UTF8String);
        }
    }
    return &gSmartMixedLearnedChoices;
}

+ (void)saveSmartMixedLearnedChoices
{
    if (BroccoliIsRunningUnitTests() || ![self checkIfUserDataFolderExists]) {
        return;
    }
    NSString *content = [NSString stringWithUTF8String:gSmartMixedLearnedChoices.serialize().c_str()];
    NSString *path = [self smartMixedLearnedChoicesDataPath];
    dispatch_async(BroccoliPersistenceQueue(), ^{
        SmartMixedWriteFile(content, path);
    });
}

+ (void)recordSmartMixedASCIIChoice:(NSString *)word
{
    [self smartMixedLearnedChoices];
    if (gSmartMixedLearnedChoices.prefersASCII(word.UTF8String)) {
        return;
    }
    gSmartMixedLearnedChoices.recordASCII(word.UTF8String);
    [self saveSmartMixedLearnedChoices];
}

+ (void)recordSmartMixedBopomofoChoice:(NSString *)run
{
    [self smartMixedLearnedChoices];
    if (gSmartMixedLearnedChoices.prefersBopomofo(run.UTF8String)) {
        return;
    }
    gSmartMixedLearnedChoices.recordBopomofo(run.UTF8String);
    [self saveSmartMixedLearnedChoices];
}

+ (void)clearSmartMixedLearnedChoices
{
    gSmartMixedLearnedChoicesLoaded = YES;
    gSmartMixedLearnedChoices.clear();
    [self saveSmartMixedLearnedChoices];
}

#pragma mark - Broccoli SmartInput: persisted user override models (T07)

+ (NSString *)userOverrideModelDataPath
{
    return [[self dataFolderPath] stringByAppendingPathComponent:@"user-override-model.txt"];
}

+ (NSString *)longTermUserOverrideModelDataPath
{
    return [[self dataFolderPath] stringByAppendingPathComponent:@"user-override-model-long-term.txt"];
}

+ (McBopomofo::UserOverrideModel *)longTermUserOverrideModel
{
    [self loadUserOverrideModels];
    return &gLongTermUserOverrideModel;
}

+ (void)loadUserOverrideModels
{
    if (gUserOverrideModelsLoaded) {
        return;
    }
    gUserOverrideModelsLoaded = YES;
    if (BroccoliIsRunningUnitTests()) {
        // Keep tests independent of what this Mac has learned.
        return;
    }
    NSString *shortTerm = SmartMixedReadFile([self userOverrideModelDataPath]);
    if (shortTerm != nil) {
        gUserOverrideModel.deserialize(shortTerm.UTF8String);
    }
    NSString *longTerm = SmartMixedReadFile([self longTermUserOverrideModelDataPath]);
    if (longTerm != nil) {
        gLongTermUserOverrideModel.deserialize(longTerm.UTF8String);
    }
}

+ (void)saveUserOverrideModels
{
    if (!gUserOverrideModelsLoaded || BroccoliIsRunningUnitTests() || ![self checkIfUserDataFolderExists]) {
        return;
    }
    // Serialize on the calling (main) thread, which owns the models; write
    // elsewhere so deactivating the input method never waits on the disk.
    NSString *shortTerm = [NSString stringWithUTF8String:gUserOverrideModel.serialize().c_str()];
    NSString *longTerm = [NSString stringWithUTF8String:gLongTermUserOverrideModel.serialize().c_str()];
    NSString *shortTermPath = [self userOverrideModelDataPath];
    NSString *longTermPath = [self longTermUserOverrideModelDataPath];
    dispatch_async(BroccoliPersistenceQueue(), ^{
        SmartMixedWriteFile(shortTerm != nil ? shortTerm : @"", shortTermPath);
        SmartMixedWriteFile(longTerm != nil ? longTerm : @"", longTermPath);
    });
}

+ (void)clearUserOverrideModels
{
    gUserOverrideModelsLoaded = YES;
    gUserOverrideModel.clear();
    gLongTermUserOverrideModel.clear();
    [self saveUserOverrideModels];
}

#pragma mark - Broccoli SmartInput: text helpers (T03, T09)

+ (NSString *)applyAutoSpacing:(NSString *)text
{
    if (text.length == 0) {
        return text;
    }
    std::string spaced = McBopomofo::TextAssist::ApplyAutoSpacing(text.UTF8String);
    NSString *spacedText = [NSString stringWithUTF8String:spaced.c_str()];
    return spacedText != nil ? spacedText : text;
}

+ (NSInteger)feedTypingGuardWithTimestamp:(NSTimeInterval)timestamp keyCode:(NSInteger)keyCode isRepeat:(BOOL)isRepeat
{
    switch (gTypingGuard.feed(timestamp, (int)keyCode, isRepeat)) {
    case McBopomofo::TextAssist::TypingGuard::Result::kAllow:
        return 0;
    case McBopomofo::TextAssist::TypingGuard::Result::kBlock:
        return 1;
    case McBopomofo::TextAssist::TypingGuard::Result::kStartedBlocking:
        return 2;
    }
    return 0;
}

+ (void)resetTypingGuard
{
    gTypingGuard.reset();
}

@end
