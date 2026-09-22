import AppKit
import Carbon

struct Key {
    let code: UInt16
    let shift: Bool
    let caps: Bool
}

struct Layout {
    let source: TISInputSource
    let id: String
    let lang: String

    init?(_ source: TISInputSource) {
        guard let id: CFString = prop(source, kTISPropertyInputSourceID),
              let langs: CFArray = prop(source, kTISPropertyInputSourceLanguages),
              let lang = (langs as? [String])?.first else { return nil }
        self.source = source
        self.id = id as String
        self.lang = lang
    }

    /// What these keystrokes produce in this layout.
    func translate(_ keys: [Key]) -> String {
        guard let data: CFData = prop(source, kTISPropertyUnicodeKeyLayoutData) else { return "" }
        let keyboard = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        var result = ""
        for key in keys {
            var dead: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let mods = UInt32(((key.shift ? shiftKey : 0) | (key.caps ? alphaLock : 0)) >> 8)
            UCKeyTranslate(keyboard, key.code, UInt16(kUCKeyActionDown), mods, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
            result += String(utf16CodeUnits: chars, count: length)
        }
        return result
    }

    func select() { TISSelectInputSource(source) }
}

private func prop<T>(_ source: TISInputSource, _ key: CFString) -> T? {
    guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? T
}

/// Plain keyboard layouts (no input methods). `installed: false` = only the ones enabled in System Settings.
func keyboardLayouts(installed: Bool = false) -> [Layout] {
    let filter = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
    let list = TISCreateInputSourceList(filter, installed).takeRetainedValue() as? [TISInputSource] ?? []
    return list.compactMap(Layout.init)
}

func currentLayout() -> Layout? {
    Layout(TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue())
}

/// `asTyped`: the text as it stands on screen. Protect-only words count for it alone, never as a reason to switch.
private func isWord(_ text: String, lang: String, learned: Set<String> = [], asTyped: Bool = false) -> Bool? {
    // The speller waves through anything in capitals ("GHBDTN", "ЫВАПР"), so capitals are judged in lower case.
    let text = text.count > 1 && text == text.uppercased() ? text.lowercased() : text
    let forms = [bare(text)] + squashed(bare(text))
    func listed(_ form: String) -> Bool {
        let lower = form.lowercased()
        return extraWords[lang]?.contains(lower) == true || learned.contains(lower)
            || (asTyped && protectedWords[lang]?.contains(lower) == true)
    }
    if forms.contains(where: listed) { return true }
    let checker = NSSpellChecker.shared
    guard checker.availableLanguages.contains(where: { $0 == lang || $0.hasPrefix(lang + "_") }) else { return nil }
    return ([text] + forms.dropFirst()).contains {
        checker.checkSpelling(of: $0, startingAt: 0, language: lang, wrap: false,
                              inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }
}

/// "kubectl," "(docker" "utf8" -> the word itself: the lists hold plain words, and the speller doesn't know them.
func bare(_ text: String) -> String { text.trimmingCharacters(in: CharacterSet.letters.inverted) }

/// "привееет" -> "привет", "привеет": every stretched run (3+ of one letter) cut down to one or two.
/// A single run ("ыыы", "sss") and anything shorter than three letters is not worth trusting.
private func squashed(_ text: String) -> [String] {
    var runs: [[Character]] = []
    for char in text {
        if runs.last?.last?.lowercased() == char.lowercased() { runs[runs.count - 1].append(char) } else { runs.append([char]) }
    }
    // ponytail: 2^n forms, so at most four stretched runs ("слоооовааа" has two).
    guard runs.count >= 2, (1...4).contains(runs.filter { $0.count >= 3 }.count), text.allSatisfy(\.isLetter) else { return [] }
    return runs.reduce([""]) { forms, run in
        (run.count >= 3 ? [1, 2] : [run.count]).flatMap { n in forms.map { $0 + String(run.prefix(n)) } }
    }.filter { $0.count >= 3 }
}

/// The layout the word was evidently meant for, or nil to leave it alone.
/// Switches when the system dictionary rejects the word as typed and either accepts it in another layout or,
/// where the dictionary knows neither, the letters only make sense in the other one.
func intendedLayout(for keys: [Key], current: Layout, others: [Layout], exceptions: Set<String>,
                    learned: Set<String> = []) -> Layout? {
    let typed = current.translate(keys)
    guard typed.count >= 2, !exceptions.contains(bare(typed).lowercased()) else { return nil }
    // Exceptions are written by hand as well as by us, and by hand the natural thing to write is the word as it
    // ends up on screen ("девопсов"), not the keys that were pressed ("ltdjgcjd") — which is what the guard above
    // compares. So a reading listed there drops out of the running. Only that one: with a third layout installed
    // the others still get their say, which giving up here altogether would take from them.
    let readings = others.map { ($0, $0.translate(keys)) }.filter {
        $0.1.filter(\.isLetter).count >= 2 && (exceptions.isEmpty || !exceptions.contains(bare($0.1).lowercased()))
    }
    // Plain words first: the speller reads "f[r" as the words "f" and "r", which must not beat the German "für".
    let candidates = readings.filter { $0.1.allSatisfy(\.isLetter) } + readings.filter { !$0.1.allSatisfy(\.isLetter) }
    // The speller skips punctuation, so ",fu" passes as the word "fu" — but , ; [ ' are letters in other
    // layouts ("баг"). Punctuation before the end of a word is suspicious enough that a plain known word
    // in another layout wins. Trailing punctuation proves nothing: "he," must not become "руб" — except
    // brackets and the backtick, which nobody leaves at the end of a plain word: "dc`" is "всё", "b[" is "их".
    // The reading may end in punctuation of its own: "fdnjhbpfwb.?" is "авторизацию,".
    let strayTail = "[]{}`~".contains(typed.last!) && typed.dropLast().allSatisfy(\.isLetter)
    if hasInnerPunctuation(typed) || strayTail, let plain = candidates.first(where: {
        bare($0.1).allSatisfy(\.isLetter) && isWord($0.1, lang: $0.0.lang, learned: learned) == true
    }) { return plain.0 }
    // Without a speller for the language (Croatian, Slovak, Farsi...) the table stands in: a word with ordinary
    // letter triplets is taken for a real one. With neither, the word is left alone.
    // ponytail: 100 is the top of the range measured on ru/en; the speller-less languages are checked on word
    // lists only (no chat texts), and the speller's leniency with punctuation means "kuća" typed as "ku'a" stays.
    let letters = strangeness(of: typed.filter(\.isLetter), lang: current.lang)
    let spelled = isWord(typed, lang: current.lang, learned: learned, asTyped: true)
    guard (spelled ?? letters.map { $0 <= 100 }) == false else { return nil }
    // A reading cut up by punctuation passes the speller piece by piece: "бауэр" reads ",fe'h", that is "fe" and "h".
    // Hyphens, apostrophes, dots and underscores do sit inside words ("из-за", "I've", "user_name"); anything else,
    // or punctuation in front, is believed only if what was typed looks like nothing: names cost 90-100, gibberish 130+.
    func natural(_ reading: String) -> Bool {
        reading.first!.isLetter && bare(reading).allSatisfy { $0.isLetter || "-'’._".contains($0) }
    }
    // With only the table vouching against the typed word, the speller's find must look ordinary by its own
    // table too: it waves through "lMssDk" and "f_h" piece by piece.
    if let exact = candidates.first(where: {
        isWord($0.1, lang: $0.0.lang, learned: learned) == true && (natural($0.1) || (letters ?? .infinity) > 115)
            && (spelled != nil || (strangeness(of: bare($0.1), lang: $0.0.lang) ?? 0) <= 100)
    }) { return exact.0 }
    // In no dictionary (slang, names, inflected jargon): letter statistics decide, from memory and in microseconds.
    // "ltdjgcjd" can't be English and "девопсов" is ordinary Russian. Measured on 5 700 rare words and names from
    // outside the tables: a gap of 40 adds no false switch; the speller's guesses used to catch a third more of
    // them (foreign names mostly) but held the key for 15-100 ms, against the rule of never waiting on another
    // process while a key is down.
    // With three layouts the most ordinary reading wins, not the first one past the gap: "ghbdsn" is nearly
    // Russian ("привыт") and plainly Ukrainian ("привіт").
    guard bare(typed).count >= 4, let odd = strangeness(of: bare(typed), lang: current.lang) else { return nil }
    return candidates.filter { bare($0.1).allSatisfy(\.isLetter) }
        .map { ($0.0, strangeness(of: bare($0.1), lang: $0.0.lang) ?? .infinity) }
        .filter { odd - $0.1 > 40 }.min { $0.1 < $1.1 }?.0
}

/// Parsed on first use, one language at a time: there are 35 tables and a Mac has two or three layouts.
private var trigrams: [String: (unseen: Double, triplets: [Substring: Double])] = [:]
private func trigramTable(_ lang: String) -> (unseen: Double, triplets: [Substring: Double])? {
    if let parsed = trigrams[lang] { return parsed }
    guard let table = trigramTables[lang] else { return nil }
    let parsed = (table.unseen, Dictionary(uniqueKeysWithValues: table.triplets.split(whereSeparator: \.isWhitespace).map {
        ($0.prefix(3), Double($0.dropFirst(3))!)
    }))
    trigrams[lang] = parsed
    return parsed
}

/// Mean cost of the word's letter triplets: 60-100 for a real word, 130+ for one typed in the wrong layout.
/// Nil for a language without a table (Tools/trigrams.py says which have one).
private func strangeness(of word: String, lang: String) -> Double? {
    guard let table = trigramTable(lang) else { return nil }
    let padded = Substring("^^" + word.lowercased() + "$")
    let costs = padded.indices.dropLast(2).map { table.triplets[padded[$0...].prefix(3)] ?? table.unseen }
    return costs.reduce(0, +) / Double(costs.count)
}

private func hasInnerPunctuation(_ text: String) -> Bool {
    text.reversed().drop { !$0.isLetter }.contains { !$0.isLetter }
}

/// Re-reads text that is already on screen in the next layout: "ghbdtn vbh" <-> "привет мир".
/// The source is the layout that can type most of its letters; characters it can't type stay as they are.
func convert(_ text: String, layouts: [Layout]) -> (text: String, target: Layout)? {
    func table(_ layout: Layout) -> [Character: Key] {
        var keys: [Character: Key] = [:]
        for shift in [true, false] {  // unshifted last, so it wins when both produce the character
            for code in UInt16(0)...50 {
                let key = Key(code: code, shift: shift, caps: false), typed = layout.translate([key])
                if typed.count == 1, typed != " " { keys[typed.first!] = key }
            }
        }
        return keys
    }
    let tables = layouts.map(table)
    let scores = tables.map { keys in text.filter { $0.isLetter && keys[$0] != nil }.count }
    guard layouts.count > 1, let best = scores.max(), best > 0, let source = scores.firstIndex(of: best) else { return nil }
    let target = layouts[(source + 1) % layouts.count]
    let converted = text.map { char in
        guard char.isLetter, let key = tables[source][char] else { return String(char) }
        return target.translate([key])
    }.joined()
    return (converted, target)
}

/// "10ю5" -> "10.5", "12Ж30" -> "12:30": a separator between two digits pressed the way another layout has it.
/// Returns the corrected text, or nil to leave the token alone. The layout stays: only the separator was wrong,
/// and if the layout was wrong too, the next word gets switched as usual.
/// Separators that already mean something ("10/5", "2^10", "1+1") and anything with other letters are not touched.
func fixedNumber(for keys: [Key], current: Layout, others: [Layout]) -> String? {
    let typed = keys.map { current.translate([$0]) }
    guard typed.count >= 3, typed.allSatisfy({ $0.count == 1 }) else { return nil }
    let digits = Set("0123456789"), meaningful = Set(".,:/-^*+=")
    func isDigit(_ s: String) -> Bool { digits.contains(s.first!) }
    for other in others {
        var result = typed, changed = false
        for (i, char) in typed.enumerated() where !isDigit(char) {
            let sandwiched = i > 0 && i < typed.count - 1 && isDigit(typed[i - 1]) && isDigit(typed[i + 1])
            let meant = other.translate([keys[i]])
            if sandwiched, !meaningful.contains(char.first!), [".", ",", ":"].contains(meant) {
                result[i] = meant
                changed = true
            } else if char.first!.isLetter || (sandwiched && !meaningful.contains(char.first!)) {
                changed = false  // a real letter, or a separator no layout explains: not a number we understand
                break
            }
        }
        if changed { return result.joined() }
    }
    return nil
}

/// A lone letter proves nothing ("b" vs "и"), so it is only fixed together with the next word,
/// once that word has shown which layout was meant.
func isMistypedLetter(_ keys: [Key], current: Layout, target: Layout) -> Bool {
    guard keys.count == 1, let typed = current.translate(keys).lowercased().first,
          let meant = target.translate(keys).lowercased().first else { return false }
    return oneLetterWords[current.lang]?.contains(typed) != true && oneLetterWords[target.lang]?.contains(meant) == true
}

/// A short word proves little either: "Ye" passes for English and "Ну" for Russian. It is fixed together with
/// the next word too, if it reads as a word in the layout that one turned out to be meant for.
func isMistypedShort(_ keys: [Key], current: Layout, target: Layout) -> Bool {
    if keys.count == 1 { return isMistypedLetter(keys, current: current, target: target) }
    let meant = target.translate(keys)
    return bare(meant).count >= 2 && bare(meant).allSatisfy(\.isLetter) && isWord(meant, lang: target.lang) == true
}

func selfTest() {
    // The word files are read once and cached until they change; a change the cache misses means an
    // exception stops applying or a just-learned word never switches.
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("layoutswitcher-selftest.txt")
    try! "one\n".write(to: file, atomically: true, encoding: .utf8)
    precondition(wordSet(file) == ["one"])
    try! "one\ntwo\n".write(to: file, atomically: true, encoding: .utf8)
    precondition(wordSet(file) == ["one", "two"])
    let handle = try! FileHandle(forWritingTo: file)  // how learned words are actually added
    handle.seekToEndOfFile()
    handle.write("three\n".data(using: .utf8)!)
    try! handle.close()
    precondition(wordSet(file) == ["one", "two", "three"])
    try! FileManager.default.removeItem(at: file)
    precondition(wordSet(file).isEmpty)

    // Which languages the speller knows differs between Macs; a CI log needs to say what it was judging with.
    print("spellers:", NSSpellChecker.shared.availableLanguages.sorted().joined(separator: " "))
    let all = keyboardLayouts(installed: true)
    guard let us = all.first(where: { $0.id == "com.apple.keylayout.US" }),
          let ru = all.first(where: { $0.id == "com.apple.keylayout.Russian" }) else { fatalError("US/Russian layouts not installed") }
    func keys(_ codes: [UInt16]) -> [Key] { codes.map { Key(code: $0, shift: false, caps: false) } }
    let ghbdtn = keys([5, 4, 11, 2, 17, 45]), hello = keys([4, 14, 37, 37, 31])

    precondition(us.translate(ghbdtn) == "ghbdtn" && ru.translate(ghbdtn) == "привет")
    precondition(intendedLayout(for: ghbdtn, current: us, others: [ru], exceptions: [])?.id == ru.id)
    precondition(intendedLayout(for: ghbdtn, current: us, others: [ru], exceptions: ["ghbdtn"]) == nil)
    // The same exception written the way it looks on screen, which is how a hand-edited list gets written.
    precondition(intendedLayout(for: ghbdtn, current: us, others: [ru], exceptions: ["привет"]) == nil)
    precondition(intendedLayout(for: ghbdtn, current: us, others: [ru], exceptions: ["мир"])?.id == ru.id)
    precondition(intendedLayout(for: ghbdtn, current: ru, others: [us], exceptions: []) == nil)
    precondition(intendedLayout(for: hello, current: us, others: [ru], exceptions: []) == nil)
    precondition(intendedLayout(for: hello, current: ru, others: [us], exceptions: [])?.id == us.id)
    let baranchik = keys([43, 3, 4, 3, 45, 16, 7, 11, 15]), kubectl = keys([40, 32, 11, 14, 8, 17, 37])
    precondition(intendedLayout(for: baranchik, current: us, others: [ru], exceptions: [])?.id == ru.id)
    precondition(intendedLayout(for: kubectl, current: us, others: [ru], exceptions: []) == nil)
    precondition(intendedLayout(for: kubectl, current: ru, others: [us], exceptions: [])?.id == us.id)  // лгиусед
    precondition(intendedLayout(for: keys([9, 40]), current: us, others: [ru], exceptions: []) == nil)  // vk, not "мл"
    let frontend = keys([0, 4, 38, 16, 45, 17, 16, 37])  // ahjyntyl
    precondition(ru.translate(frontend) == "фронтенд")
    precondition(intendedLayout(for: frontend, current: us, others: [ru], exceptions: [])?.id == ru.id)
    precondition(intendedLayout(for: keys([43, 3, 32]), current: us, others: [ru], exceptions: [])?.id == ru.id)  // ,fu -> баг
    precondition(intendedLayout(for: keys([4, 14, 43]), current: us, others: [ru], exceptions: []) == nil)        // "he," not "руб"
    precondition(intendedLayout(for: keys([2, 31, 45, 39, 17]), current: us, others: [ru], exceptions: []) == nil) // don't
    let zsh = keys([6, 1, 4])  // "zsh" is built in; "яыр" learned as a word must win over it being gibberish
    precondition(intendedLayout(for: zsh, current: ru, others: [us], exceptions: [], learned: ["яыр"]) == nil)
    let octokit = keys([31, 8, 17, 31, 40, 34, 17])  // in no dictionary and no list: letter statistics switch it
    precondition(us.translate(octokit) == "octokit")
    precondition(intendedLayout(for: octokit, current: ru, others: [us], exceptions: [])?.id == us.id)
    precondition(intendedLayout(for: octokit, current: ru, others: [us], exceptions: ["щсещлше"]) == nil)
    precondition(intendedLayout(for: octokit, current: ru, others: [us], exceptions: [], learned: ["octokit"])?.id == us.id)
    precondition(intendedLayout(for: octokit, current: us, others: [ru], exceptions: [], learned: ["octokit"]) == nil)
    precondition(isMistypedLetter(keys([6]), current: us, target: ru))    // z -> я
    precondition(!isMistypedLetter(keys([0]), current: us, target: ru))   // "a" is a word already
    precondition(isMistypedLetter(keys([0]), current: ru, target: us))    // ф -> a
    precondition(!isMistypedLetter(keys([2]), current: ru, target: us))   // в is a word already
    // Capitals: the speller accepts any of them, so they are judged in lower case.
    func caps(_ codes: [UInt16]) -> [Key] { codes.map { Key(code: $0, shift: true, caps: false) } }
    precondition(intendedLayout(for: caps([5, 4, 11, 2, 17, 45]), current: us, others: [ru], exceptions: [])?.id == ru.id)  // GHBDTN
    precondition(intendedLayout(for: caps([4, 14, 37, 37, 31]), current: us, others: [ru], exceptions: []) == nil)         // HELLO
    precondition(intendedLayout(for: caps([1, 12, 37]), current: ru, others: [us], exceptions: [])?.id == us.id)           // ЫЙД -> SQL
    precondition(intendedLayout(for: keys([4, 3]), current: ru, others: [us], exceptions: []) == nil)                       // рф, not "ha"
    // Abbreviations in lower case: listed ones switch, protect-only ones just stay as typed.
    precondition(intendedLayout(for: keys([8, 34, 3]), current: us, others: [ru], exceptions: [])?.id == ru.id)   // cif -> сша
    precondition(intendedLayout(for: keys([2, 45, 1]), current: ru, others: [us], exceptions: [])?.id == us.id)   // вты -> dns
    precondition(intendedLayout(for: keys([9, 2, 37]), current: ru, others: [us], exceptions: []) == nil)         // мвд, not "vdl"
    precondition(intendedLayout(for: keys([15, 2, 16]), current: us, others: [ru], exceptions: []) == nil)        // rdy, not "квн"
    // Stretched letters: "ghbdtttn" -> "привееет", and "нееет" typed on purpose stays.
    precondition(intendedLayout(for: keys([5, 4, 11, 2, 17, 17, 17, 45]), current: us, others: [ru], exceptions: [])?.id == ru.id)
    precondition(intendedLayout(for: keys([45, 17, 17, 17, 17]), current: ru, others: [us], exceptions: []) == nil)
    precondition(intendedLayout(for: keys([1, 1, 1]), current: ru, others: [us], exceptions: []) == nil)                    // ыыы, not "sss"
    // Punctuation and digits around a listed word: "лгиуседб" -> "kubectl,", "геа8" -> "utf8".
    precondition(intendedLayout(for: kubectl + keys([43]), current: ru, others: [us], exceptions: [])?.id == us.id)
    precondition(intendedLayout(for: keys([32, 17, 3, 28]), current: ru, others: [us], exceptions: [])?.id == us.id)
    precondition(intendedLayout(for: kubectl + keys([43]), current: us, others: [ru], exceptions: []) == nil)
    // Identifiers: the speller splits camelCase and snake_case itself.
    let getUserName = [5, 14, 17].map { Key(code: $0, shift: false, caps: false) } + caps([32]) + keys([1, 14, 15]) + caps([45]) + keys([0, 46, 14])
    precondition(us.translate(getUserName) == "getUserName")
    precondition(intendedLayout(for: getUserName, current: ru, others: [us], exceptions: [])?.id == us.id)
    precondition(intendedLayout(for: getUserName, current: us, others: [ru], exceptions: []) == nil)
    let userName = keys([32, 1, 14, 15]) + caps([27]) + keys([45, 0, 46, 14])  // user_name
    precondition(us.translate(userName) == "user_name")
    precondition(intendedLayout(for: userName, current: ru, others: [us], exceptions: [])?.id == us.id)
    precondition(intendedLayout(for: userName, current: us, others: [ru], exceptions: []) == nil)
    // Umlauts: nothing here is tied to ru/en, a German layout works the same way.
    if let de = all.first(where: { $0.id == "com.apple.keylayout.German" }) {
        let fur = keys([3, 33, 15]), uber = keys([33, 11, 14, 15])
        precondition(de.translate(fur) == "für" && de.translate(uber) == "über")
        precondition(intendedLayout(for: fur, current: ru, others: [us, de], exceptions: [])?.id == de.id)
        precondition(intendedLayout(for: uber, current: us, others: [ru, de], exceptions: [])?.id == de.id)
        precondition(intendedLayout(for: uber, current: de, others: [us, ru], exceptions: []) == nil)
        precondition(intendedLayout(for: uber, current: us, others: [ru, de], exceptions: ["über"]) == nil)
        precondition(convert("für", layouts: [de, ru])?.text == ru.translate(fur))
    }
    // Ukrainian: a third layout next to the two. "ghsdbn" is a word only there; "лгіусед" still goes to English.
    if let uk = all.first(where: { $0.id == "com.apple.keylayout.Ukrainian" }) {
        let pryvit = keys([5, 4, 1, 2, 11, 45])
        precondition(uk.translate(pryvit) == "привіт" && ru.translate(pryvit) == "прывит")
        precondition(intendedLayout(for: pryvit, current: us, others: [ru, uk], exceptions: [])?.id == uk.id)
        precondition(intendedLayout(for: pryvit, current: uk, others: [us, ru], exceptions: []) == nil)
        precondition(intendedLayout(for: ghbdtn, current: us, others: [uk, ru], exceptions: [])?.id == ru.id)
        precondition(intendedLayout(for: kubectl, current: uk, others: [us, ru], exceptions: [])?.id == us.id)
        // In no dictionary: "загуглити" against "pfueuksns" and "загуглыты" is decided by the tables.
        let zahuhlyty = keys([35, 3, 32, 14, 32, 40, 1, 45, 1])
        precondition(uk.translate(zahuhlyty) == "загуглити")
        precondition(intendedLayout(for: zahuhlyty, current: us, others: [ru, uk], exceptions: [])?.id == uk.id)
        precondition(intendedLayout(for: zahuhlyty, current: uk, others: [us, ru], exceptions: []) == nil)
    }
    precondition(intendedLayout(for: keys([3, 33, 3, 33, 3]), current: ru, others: [us], exceptions: []) == nil)  // ахаха, not "f[f[f"
    precondition(isMistypedShort(keys([16, 14]), current: us, target: ru))     // Ye -> ну
    precondition(isMistypedShort(keys([17, 4, 14]), current: ru, target: us))  // еру -> the
    precondition(!isMistypedShort(keys([17, 31]), current: us, target: ru))    // "to" stays: "ещ" is nothing
    precondition(!isMistypedShort(keys([18, 47, 23]), current: ru, target: us)) // "1ю5" is not a word
    // In no dictionary: letter statistics decide.
    let devopsov = keys([37, 17, 2, 38, 5, 8, 38, 2])
    precondition(ru.translate(devopsov) == "девопсов")
    precondition(intendedLayout(for: devopsov, current: us, others: [ru], exceptions: [])?.id == ru.id)
    precondition(intendedLayout(for: devopsov, current: ru, others: [us], exceptions: []) == nil)
    precondition(intendedLayout(for: octokit, current: us, others: [ru], exceptions: []) == nil)
    // Converting a selection: source layout is detected from the text itself.
    precondition(convert("ghbdtn vbh", layouts: [us, ru])?.text == "привет мир")
    precondition(convert("ghbdtn vbh, rfr ltkf?", layouts: [us, ru])?.text == "привет мир, как дела?")  // punctuation kept
    precondition(convert("Привет мир", layouts: [us, ru])?.text == "Ghbdtn vbh")
    precondition(convert("Привет мир", layouts: [us, ru])?.target.id == us.id)
    precondition(convert("ghbdtn 123 ✓", layouts: [us, ru])?.text == "привет 123 ✓")
    precondition(convert("12345", layouts: [us, ru]) == nil)
    precondition(convert("ghbdtn", layouts: [us]) == nil)
    // Numbers: only a separator squeezed between digits is fixed, and only if it means nothing as typed.
    func k(_ code: UInt16, shift: Bool = false) -> Key { Key(code: code, shift: shift, caps: false) }
    let one = k(18), two = k(19), three = k(20), five = k(23), zero = k(29)
    precondition(fixedNumber(for: [one, zero, k(47), five], current: ru, others: [us]) == "10.5")                      // 10ю5
    precondition(fixedNumber(for: [one, two, k(41, shift: true), three, zero], current: ru, others: [us]) == "12:30")  // 12Ж30
    precondition(fixedNumber(for: [one, zero, k(43), five], current: ru, others: [us]) == "10,5")                      // 10б5
    precondition(fixedNumber(for: [two, one, k(47), zero, five, k(47), two, zero], current: ru, others: [us]) == "21.05.20")
    precondition(fixedNumber(for: [one, zero, k(47), five], current: us, others: [ru]) == nil)                         // 10.5 is fine
    precondition(fixedNumber(for: [two, k(22, shift: true), one, zero], current: us, others: [ru]) == nil)             // 2^10
    precondition(fixedNumber(for: [one, zero, k(44), five], current: us, others: [ru]) == nil)                         // 10/5
    precondition(fixedNumber(for: [one, zero, k(47)], current: ru, others: [us]) == nil)                               // "10ю": not between digits
    precondition(fixedNumber(for: [k(9), one, zero, k(47), five], current: ru, others: [us]) == nil)                   // "м10ю5": other letters
    if let pc = all.first(where: { $0.id == "com.apple.keylayout.RussianWin" }) {
        precondition(fixedNumber(for: [one, zero, k(44, shift: true), five], current: us, others: [pc]) == "10,5")    // 10?5, Russian-PC comma
    }
    // Built-in words must not shadow a real word in the other layout.
    func keys(for text: String, in layout: Layout) -> [Key]? {
        let table = Dictionary((0...50).map { (layout.translate(keys([$0])), $0) }, uniquingKeysWith: { a, _ in a })
        let codes = text.map { table[String($0)] }
        return codes.contains(nil) ? nil : keys(codes.compactMap { $0 })
    }
    for (lang, list) in extraWords {
        let (own, other) = lang == "en" ? (us, ru) : (ru, us)
        for word in list where !deliberateCollisions.contains(word) {
            guard let typed = keys(for: word, in: own) else { fatalError("can't type built-in word \(word)") }
            let reading = other.translate(typed)
            precondition(hasInnerPunctuation(reading) || isWord(reading, lang: other.lang) != true, "built-in \(word) shadows \(reading)")
        }
    }
    // No speller for Croatian (Apple's layout is QWERTY, only č ć š ž đ differ): the table alone keeps "dobro"
    // and "kuća" Croatian and sends "quickly" to English. Macedonian, a different script: "pi[uva" is "пишува".
    if let hr = all.first(where: { $0.id == "com.apple.keylayout.Croatian" }) {
        let quickly = keys(for: "quickly", in: us)!
        precondition(hr.translate(quickly) == "quickly")
        precondition(intendedLayout(for: keys(for: "dobro", in: hr)!, current: hr, others: [us], exceptions: []) == nil)
        precondition(intendedLayout(for: keys(for: "kuća", in: hr)!, current: hr, others: [us], exceptions: []) == nil)
        precondition(intendedLayout(for: quickly, current: hr, others: [us], exceptions: [])?.id == us.id)
        precondition(intendedLayout(for: quickly, current: us, others: [hr], exceptions: []) == nil)
    }
    if let mk = all.first(where: { $0.id == "com.apple.keylayout.Macedonian" }) {
        let pishuva = keys(for: "пишува", in: mk)!, quickly = keys(for: "quickly", in: us)!
        precondition(us.translate(pishuva) == "pi[uva" && mk.translate(quickly) == "љуицклѕ")
        precondition(intendedLayout(for: pishuva, current: us, others: [mk], exceptions: [])?.id == mk.id)
        precondition(intendedLayout(for: pishuva, current: mk, others: [us], exceptions: []) == nil)
        precondition(intendedLayout(for: quickly, current: mk, others: [us], exceptions: [])?.id == us.id)
        precondition(intendedLayout(for: quickly, current: us, others: [mk], exceptions: []) == nil)
    }
    // Whole phrases through the same buffer the event tap drives: live.sh without a keyboard. The keys are the
    // ones a US layout types; `shown` is the text left on screen, with each fix applied the way the app applies
    // it. This is the only check of the short words fixed after the fact, and of a switch outliving its word.
    func screen(_ phrase: String) -> String {
        var buffer = Buffer(), shown = "", current = us
        for char in phrase {
            if char == " " {
                let fix = buffer.end(space: true, current: current, layouts: [us, ru], exceptions: [],
                                     learned: [], fixShortWords: true, allowed: { true })
                if let fix { shown = String(shown.dropLast(fix.stale)) + fix.text }
                shown += " "
                if let target = fix?.target { current = target }
                continue
            }
            guard let key = keys(for: String(char), in: us)?.first else { fatalError("can't type \(char)") }
            buffer.letter(key, current: current)
            shown += current.translate([key])
        }
        return shown
    }
    func check(_ phrase: String, _ expected: String) {
        let shown = screen(phrase)
        precondition(shown == expected, "typed \"\(phrase)\" -> \"\(shown)\", expected \"\(expected)\"")
    }
    check("ltdjgcjd ", "девопсов ")
    check("kubectl nginx ", "kubectl nginx ")
    check("ye ns ghbdtn ", "ну ты привет ")          // short words fixed behind the word that gave them away
    check("z ye ghbdtn ", "я ну привет ")
    // A word left holding a bracket: "b[" is "их". (live.sh types "dc`" for "всё", which needs Russian-PC —
    // Apple's own Russian layout has "]" where the backtick key is.)
    check("b[ ghbdtn ", "их привет ")
    check("to ghbdtn ", "to привет ")                // "to" is a word in its own right, so it stays
    check("press the ghbdtn ", "press the привет ")
    check("hello. ye ns ghbdtn ", "hello. ну ты привет ")  // a sentence ended: "ye ns" is up for grabs again
    check("ltdjgcjd ghbdtn ", "девопсов привет ")          // the switch stays on for the next word

    print("selftest ok")
}
