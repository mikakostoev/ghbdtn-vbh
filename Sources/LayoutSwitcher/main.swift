import AppKit
import Carbon
import ServiceManagement
import SwiftUI

private let synthetic: Int64 = 0x4C53_5752  // marks events we post ourselves
private let space: UInt16 = 49, backspace: UInt16 = 51
private let wordEnders: Set<UInt16> = [space, 36, 48, 76]  // space, return, tab, enter
private let optionKeys: Set<UInt16> = [58, 61]

final class Switcher: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private var tap: CFMachPort?

    private var settingsWindow: NSWindow?

    private var word: [Key] = []
    private var prefix: [[Key]] = []   // short words right before `word` that we left alone, judged together with it
    private var settled = false        // a long word before them stayed as typed: this layout is the intended one
    private var trailingSpaces = 0
    private var wordEnded = false
    private var autoSwitched = false   // last replacement was automatic; a manual convert right after means "wrong guess"
    private var optionAlone = false
    private var copying = false        // a clipboard round-trip for the selection is in flight
    private var lastOptionTap: TimeInterval?   // double-Option mode: when the first lone tap happened

    private var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    private var excludedApps: Set<String> { Set(defaults.stringArray(forKey: "excludedApps") ?? []) }
    private var frontApp: NSRunningApplication? { NSWorkspace.shared.frontmostApplication }

    private var exceptions: Set<String> { wordSet(exceptionsFile) }

    // MARK: App

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An image, not the "⌨︎" glyph: only an image can be dimmed to show the switcher is doing nothing.
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "LayoutSwitcher")
        statusItem.button?.image?.isTemplate = true
        showState()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reset), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // We ask other apps about focus from inside the event tap: a hung app must not stall typing for the default 6 s.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            if self?.startTap() == true { timer.invalidate(); self?.showState() }
        }.fire()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector, on: Bool = false) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.state = on ? .on : .off
        }
        if tap == nil { add("Нет доступа: Универсальный доступ…", #selector(openAccessibility)) }
        add("Автопереключение", #selector(toggleEnabled), on: enabled)
        menu.addItem(.separator())
        add("Настройки…", #selector(openSettings))
        add("Выйти", #selector(NSApplication.terminate))
        menu.items.last?.target = NSApp
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        showState()
    }

    /// Dimmed whenever nothing will be switched — turned off, or no Accessibility grant — so that the two
    /// cases the user has to act on don't look exactly like the working one.
    private func showState() {
        statusItem.button?.appearsDisabled = !enabled || tap == nil
        statusItem.button?.toolTip = tap == nil ? "LayoutSwitcher: нет доступа к Универсальному доступу"
            : enabled ? "LayoutSwitcher" : "LayoutSwitcher: автопереключение выключено"
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "LayoutSwitcher"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        } else {
            // Re-host so onAppear reloads exceptions learned since the last open.
            settingsWindow?.contentViewController = NSHostingController(rootView: SettingsView())
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: Event tap

    private func startTap() -> Bool {
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, _ in
            switcher.handle(type, event) ? Unmanaged.passUnretained(event) : nil
        }, userInfo: nil) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        self.tap = tap
        return true
    }

    /// Returns false to swallow the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        if event.getIntegerValueField(.eventSourceUserData) == synthetic { return true }

        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let shortcut: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]

        // Never touch password fields (secure input) or apps the user opted out of.
        guard enabled, !IsSecureEventInputEnabled(), !excludedApps.contains(frontApp?.bundleIdentifier ?? "") else {
            reset()
            return true
        }

        switch type {
        case .flagsChanged:
            // Option pressed and released with nothing in between = convert the last word manually.
            if optionKeys.contains(code), flags.intersection(shortcut.union(.maskShift)) == .maskAlternate {
                optionAlone = true
            } else if optionAlone, flags.intersection(shortcut).isEmpty {
                optionAlone = false
                if defaults.object(forKey: "manualConvert") as? Bool ?? true, optionTapCompletes() {
                    // Clicking, arrows and shortcuts empty the buffer, so an empty buffer means "not right after typing".
                    if word.isEmpty { convertSelection() } else { convertManually() }
                }
            } else {
                optionAlone = false
            }
        case .keyDown:
            optionAlone = false
            lastOptionTap = nil
            if !flags.intersection(shortcut).isEmpty {
                reset()
            } else if code == backspace {
                if wordEnded || word.isEmpty { reset() } else { word.removeLast() }
            } else if wordEnders.contains(code) {
                return endWord(with: code, flags: flags)
            } else if let char = currentLayout()?.translate([Key(code: code, shift: false, caps: false)]).unicodeScalars.first,
                      char.value > 0x20, char.value != 0x7F, !(0xF700...0xF8FF).contains(char.value) {
                if wordEnded {
                    // "Ye ns lf`im": "Ye" and "ns" pass for words, so they wait here until a longer word shows
                    // the layout was wrong. After "press the" it evidently wasn't, unless a sentence just ended.
                    var waiting: [[Key]] = [], stays = false
                    if trailingSpaces == 1, !autoSwitched {
                        let short = word.count <= 4
                        if short, !settled { waiting = Array((prefix + [word]).suffix(3)) }
                        stays = short ? settled : !".?!".contains(currentLayout()?.translate([word.last!]) ?? "")
                    }
                    reset()
                    prefix = waiting
                    settled = stays
                }
                word.append(Key(code: code, shift: flags.contains(.maskShift), caps: flags.contains(.maskAlphaShift)))
            } else {
                reset()  // arrows, escape, function keys: the caret moved, the buffer is stale
            }
        default:
            optionAlone = false
            reset()
        }
        return true
    }

    private func endWord(with code: UInt16, flags: CGEventFlags) -> Bool {
        if wordEnded || word.isEmpty {
            if code == space, wordEnded { trailingSpaces += 1 } else { reset() }
            return true
        }
        let layouts = keyboardLayouts()
        if let current = currentLayout(), layouts.contains(where: { $0.id == current.id }),
           let number = fixedNumber(for: word, current: current, others: layouts.filter { $0.id != current.id }),
           !siteExcluded() {
            replace(current.translate(word).count, with: number)
            post(code, flags: flags.intersection(.maskShift))
            if code == space { wordEnded = true; trailingSpaces = 1 } else { reset() }
            return false
        }
        guard let current = currentLayout(), layouts.contains(where: { $0.id == current.id }),
              let target = intendedLayout(for: word, current: current, others: layouts.filter { $0.id != current.id },
                                          exceptions: exceptions, learned: wordSet(learnedFile)),
              !siteExcluded() else {
            if code == space { wordEnded = true; trailingSpaces = 1 } else { reset() }
            return true
        }
        var stale = current.translate(word).count, fixed = target.translate(word)
        if defaults.object(forKey: "oneLetterWords") as? Bool ?? true {
            for keys in prefix.reversed() {
                guard isMistypedShort(keys, current: current, target: target) else { break }
                stale += current.translate(keys).count + 1
                fixed = target.translate(keys) + " " + fixed
            }
        }
        replace(stale, with: fixed)
        post(code, flags: flags.intersection(.maskShift))
        target.select()
        if code == space { wordEnded = true; trailingSpaces = 1; autoSwitched = true } else { reset() }
        return false
    }

    /// Single mode: every lone Option converts. Double mode (default): the first tap only arms the second,
    /// so an Option that belongs to something else (push-to-talk, a stray press) doesn't convert or teach anything.
    private func optionTapCompletes() -> Bool {
        guard (defaults.string(forKey: "convertTrigger") ?? "double") == "double" else { return true }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastOptionTap, now - last < NSEvent.doubleClickInterval {
            lastOptionTap = nil
            return true
        }
        lastOptionTap = now
        return false
    }

    private func convertManually() {
        let layouts = keyboardLayouts()
        guard !word.isEmpty, layouts.count > 1, let current = currentLayout(),
              let index = layouts.firstIndex(where: { $0.id == current.id }) else { return }
        let target = layouts[(index + 1) % layouts.count]
        let typed = current.translate(word), restored = target.translate(word)
        replace(typed.count + trailingSpaces, with: restored + String(repeating: " ", count: trailingSpaces))
        target.select()
        if autoSwitched {
            // The user undid our autoswitch: remember the word so it never happens again.
            append(bare(restored), to: exceptionsFile)
        } else if defaults.object(forKey: "learnWords") as? Bool ?? true {
            learn(restored, insteadOf: typed)
        }
        autoSwitched = false
    }

    // MARK: Selection

    private func convertSelection() {
        if let text = selectedText(), !text.isEmpty { return retype(text) }
        // A second Option while the copy is in flight would re-read the stale selection and type twice.
        guard !copying else { return }
        copying = true
        // The app doesn't expose its selection (Electron, some browsers): copy it and put the clipboard back.
        let pasteboard = NSPasteboard.general, before = pasteboard.changeCount
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        post(8, flags: .maskCommand)  // Cmd+C
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            copying = false
            guard pasteboard.changeCount != before else { return }  // nothing was selected
            let text = pasteboard.string(forType: .string)
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                types.forEach { item.setData($1, forType: $0) }
                return item
            })
            if let text { retype(text) }
        }
    }

    private func selectedText() -> String? {
        guard let focused = axValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) else { return nil }
        return axValue(focused as! AXUIElement, kAXSelectedTextAttribute) as? String
    }

    private func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    // MARK: Sites

    /// Asked only when we are about to autoswitch, so the walk up the accessibility tree costs nothing while typing.
    /// Manual convert still works on an excluded site: that is the user's own explicit request.
    private func siteExcluded() -> Bool {
        let sites = excludedSites()
        guard !sites.isEmpty, let host = currentSite() else { return false }
        return sites.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Host of the page being typed into. Browsers and Electron apps expose it as the URL of the web area;
    /// the outermost one wins, so an embedded frame counts as the site it sits on.
    private func currentSite() -> String? {
        // A hung app takes the full messaging timeout per call and the walk makes three of them per level,
        // so the depth alone is no bound: without a budget one space could hold the keyboard for a minute.
        // Out of time we answer with the outermost web area reached so far, exactly as a shallow tree would.
        let deadline = ProcessInfo.processInfo.systemUptime + 0.05
        var element = axValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute), host: String?
        for _ in 0..<100 {
            guard let current = element, CFGetTypeID(current) == AXUIElementGetTypeID(),
                  ProcessInfo.processInfo.systemUptime < deadline else { break }
            if axValue(current as! AXUIElement, kAXRoleAttribute) as? String == "AXWebArea",
               let url = axValue(current as! AXUIElement, kAXURLAttribute) as? URL { host = url.host ?? host }
            element = axValue(current as! AXUIElement, kAXParentAttribute)
        }
        return host?.lowercased()
    }

    /// Typing over a selection replaces it, so the converted text is simply typed.
    // ponytail: single line only. A typed newline sends the message in chat apps, and editors that copy the
    // whole line when nothing is selected (VS Code) hand us text ending in one. Paste instead if multi-line matters.
    private func retype(_ text: String) {
        guard text.count <= 2000, !text.contains(where: \.isNewline),
              let (converted, target) = convert(text, layouts: keyboardLayouts()) else { return }
        replace(0, with: converted)
        target.select()
        reset()
    }

    /// We left the word alone and the user converted it by hand: next time switch it ourselves.
    /// Converting straight back means the first press was a mistake, so that forgets the word again.
    private func learn(_ restored: String, insteadOf typed: String) {
        var learned = wordSet(learnedFile)
        if learned.remove(typed.lowercased()) != nil {
            try? learned.sorted().map { $0 + "\n" }.joined().write(to: learnedFile, atomically: true, encoding: .utf8)
        } else if (2...30).contains(restored.count), restored.allSatisfy(\.isLetter), !learned.contains(restored.lowercased()) {
            append(restored, to: learnedFile)
        }
    }

    private func append(_ word: String, to file: URL) {
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        handle.seekToEndOfFile()
        handle.write((word.lowercased() + "\n").data(using: .utf8)!)
        try? handle.close()
    }

    @objc private func reset() {
        word.removeAll()
        prefix.removeAll()
        settled = false
        trailingSpaces = 0
        wordEnded = false
        autoSwitched = false
    }

    // MARK: Typing

    private func replace(_ count: Int, with text: String) {
        for _ in 0..<count { post(backspace) }
        // Unicode payload instead of keycodes: independent of when the app notices the layout change.
        for char in text {
            let utf16 = Array(String(char).utf16)
            post(0, unicode: utf16)
        }
    }

    private func post(_ code: UInt16, flags: CGEventFlags = [], unicode: [UniChar]? = nil) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags
            if let unicode { event.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode) }
            event.setIntegerValueField(.eventSourceUserData, value: synthetic)
            event.post(tap: .cgSessionEventTap)
        }
    }
}

if CommandLine.arguments.contains("--selftest") {
    selfTest()
    exit(0)
}
if let flag = CommandLine.arguments.firstIndex(of: "--eval") {
    exit(evaluate(Array(CommandLine.arguments[(flag + 1)...])) ? 0 : 1)
}

let switcher = Switcher()
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.delegate = switcher
application.run()
