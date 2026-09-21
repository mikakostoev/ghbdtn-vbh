import Foundation

/// `--eval file…`: types every word of each text twice with the layouts enabled on this Mac — in its own layout
/// (it must stay) and in the other one (it must switch) — and prints what went wrong and how long the slowest
/// decisions took. Returns false if anything was switched that shouldn't have been.
/// Short words that read as words both ways ("Ye"/"Ну") show up as missed here: they are fixed at run time
/// together with the word after them, which a word-by-word check can't see.
func evaluate(_ files: [String]) -> Bool {
    let layouts = keyboardLayouts()
    let tables = layouts.map { layout in
        var table: [Character: Key] = [:]
        for shift in [true, false] {  // unshifted last, so it wins when both produce the character
            for code in UInt16(0)...50 {
                let key = Key(code: code, shift: shift, caps: false), typed = layout.translate([key])
                if typed.count == 1, typed != " " { table[typed.first!] = key }
            }
        }
        return table
    }
    var clean = true, times: [(seconds: Double, word: String)] = []
    for file in files {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { fatalError("can't read \(file)") }
        let words = Set(text.split(whereSeparator: \.isWhitespace).map(String.init)).sorted()
        // The text's own layout is the one that can type the most of it.
        let scores = tables.map { table in words.filter { $0.allSatisfy { table[$0] != nil } }.count }
        guard layouts.count > 1, let own = scores.firstIndex(of: scores.max()!) else { fatalError("need two layouts enabled") }
        let others = layouts.indices.filter { $0 != own }.map { layouts[$0] }
        var switched: [String] = [], missed: [String] = [], count = 0
        for word in words where word.count >= 2 {
            let keys = word.compactMap { tables[own][$0] }
            guard keys.count == word.count else { continue }
            count += 1
            var start = Date()
            if let wrong = intendedLayout(for: keys, current: layouts[own], others: others, exceptions: []) {
                switched.append("\(word) -> \(wrong.translate(keys))")
            }
            times.append((Date().timeIntervalSince(start), word))
            for other in others {
                start = Date()
                let rest = layouts.filter { $0.id != other.id }
                if intendedLayout(for: keys, current: other, others: rest, exceptions: [])?.id != layouts[own].id {
                    missed.append("\(other.translate(keys)) ≠ \(word)")
                }
                times.append((Date().timeIntervalSince(start), other.translate(keys)))
            }
        }
        print("== \(file): \(count) words, own layout \(layouts[own].id)")
        print("FALSE SWITCH \(switched.count): \(switched.joined(separator: ", "))")
        print("MISSED \(missed.count): \(missed.prefix(40).joined(separator: ", "))\(missed.count > 40 ? ", …" : "")")
        clean = clean && switched.isEmpty
    }
    times.sort { $0.seconds > $1.seconds }
    let slowest = times.prefix(5).map { String(format: "%.0f ms %@", $0.seconds * 1000, $0.word) }.joined(separator: ", ")
    print("== \(times.count) decisions, \(times.filter { $0.seconds > 0.01 }.count) over 10 ms; slowest: \(slowest)")
    return clean
}
