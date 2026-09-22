import Foundation

/// What has been typed since the last boundary, and the decision to make when a word ends. Kept apart from the
/// event tap so a whole phrase can be replayed in selfTest(): this is the logic live.sh needs a keyboard for.
struct Buffer {
    /// The word being typed. Empty means the caret moved since the last keystroke: there is nothing to convert.
    private(set) var keys: [Key] = []
    /// Short words right before `keys` that were left alone, judged together with it.
    private var prefix: [[Key]] = []
    /// A long word before them stayed as typed: this layout is the intended one.
    private var settled = false
    private(set) var trailingSpaces = 0
    private var wordEnded = false
    /// The last replacement was automatic; a manual convert right after means "wrong guess".
    var autoSwitched = false

    var isEmpty: Bool { keys.isEmpty }

    /// What to put in place of the word just typed. `target` is nil for a corrected number: only the separator
    /// was wrong, so the layout stays.
    struct Fix {
        let stale: Int
        let text: String
        let target: Layout?
    }

    mutating func reset() { self = Buffer() }

    mutating func removeLast() {
        if wordEnded || keys.isEmpty { reset() } else { keys.removeLast() }
    }

    /// A printable key. After a word has ended this starts the next one, carrying over the short words that
    /// might still turn out to be mistyped.
    mutating func letter(_ key: Key, current: Layout?) {
        if wordEnded {
            // "Ye ns lf`im": "Ye" and "ns" pass for words, so they wait here until a longer word shows
            // the layout was wrong. After "press the" it evidently wasn't, unless a sentence just ended.
            var waiting: [[Key]] = [], stays = false
            if trailingSpaces == 1, !autoSwitched {
                let short = keys.count <= 4
                if short, !settled { waiting = Array((prefix + [keys]).suffix(3)) }
                stays = short ? settled : !".?!".contains(current?.translate([keys.last!]) ?? "")
            }
            reset()
            prefix = waiting
            settled = stays
        }
        keys.append(key)
    }

    /// A word ender. `allowed` is asked only once there is something to replace, so the accessibility walk
    /// behind it costs nothing while typing.
    mutating func end(space: Bool, current: Layout?, layouts: [Layout], exceptions: Set<String>,
                      learned: Set<String>, fixShortWords: Bool, allowed: () -> Bool) -> Fix? {
        if wordEnded || keys.isEmpty {
            if space, wordEnded { trailingSpaces += 1 } else { reset() }
            return nil
        }
        let fix = decide(current: current, layouts: layouts, exceptions: exceptions, learned: learned,
                         fixShortWords: fixShortWords, allowed: allowed)
        // A space keeps the word and the short ones before it: the word after them may still change their mind.
        if space {
            wordEnded = true
            trailingSpaces = 1
            if fix?.target != nil { autoSwitched = true }
        } else {
            reset()
        }
        return fix
    }

    private func decide(current: Layout?, layouts: [Layout], exceptions: Set<String>, learned: Set<String>,
                        fixShortWords: Bool, allowed: () -> Bool) -> Fix? {
        guard let current, layouts.contains(where: { $0.id == current.id }) else { return nil }
        let others = layouts.filter { $0.id != current.id }
        if let number = fixedNumber(for: keys, current: current, others: others), allowed() {
            return Fix(stale: current.translate(keys).count, text: number, target: nil)
        }
        guard let target = intendedLayout(for: keys, current: current, others: others,
                                          exceptions: exceptions, learned: learned), allowed() else { return nil }
        var stale = current.translate(keys).count, fixed = target.translate(keys)
        if fixShortWords {
            for short in prefix.reversed() {
                guard isMistypedShort(short, current: current, target: target) else { break }
                stale += current.translate(short).count + 1
                fixed = target.translate(short) + " " + fixed
            }
        }
        return Fix(stale: stale, text: fixed, target: target)
    }
}
