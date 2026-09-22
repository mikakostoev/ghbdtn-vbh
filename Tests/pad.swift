import AppKit
import Carbon
// Tiny pad for Tests/live.sh: a text view with every substitution off; types the cases given as arguments into itself
// by key code, so the running ghbdtn vbh sees them as real typing, and prints what ended up in the view.
let codes: [Character: UInt16] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46," ":49,"`":50,",":43,".":47]
func layout(_ id: String) -> TISInputSource? {
    (TISCreateInputSourceList([kTISPropertyInputSourceID: id] as CFDictionary, false).takeRetainedValue() as? [TISInputSource])?.first
}
let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
let view = NSTextView(frame: window.contentView!.bounds)
view.isAutomaticSpellingCorrectionEnabled = false; view.isAutomaticTextReplacementEnabled = false
view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
view.isContinuousSpellCheckingEnabled = false; view.isAutomaticTextCompletionEnabled = false
window.contentView!.addSubview(view); window.title = "ghbdtn vbh test pad"
// FRAMES=dir: bigger type, and a PNG of the view every 40 ms — Tools/demo.sh turns them into the README gif.
if let dir = ProcessInfo.processInfo.environment["FRAMES"] {
    view.font = .systemFont(ofSize: 30); view.textContainerInset = NSSize(width: 20, height: 40)
    var n = 0
    Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep); n += 1
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%04d.png", n)))
    }
}
window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view); app.activate(ignoringOtherApps: true)
let source = CGEventSource(stateID: .hidSystemState)
func press(_ code: UInt16, flags: CGEventFlags = []) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
        e.flags = flags; e.post(tap: .cghidEventTap); usleep(12_000)
    }
}
let cases = Array(CommandLine.arguments.dropFirst())
DispatchQueue.global().async {
    sleep(1)
    for line in cases {
        guard DispatchQueue.main.sync(execute: { NSApp.isActive }) else { print("pad lost focus, stopping"); break }
        DispatchQueue.main.sync { view.string = ""; _ = layout("com.apple.keylayout.ABC").map { TISSelectInputSource($0) } }
        press(53); usleep(200_000)  // escape: clears the switcher's buffer
        for char in line { press(codes[char]!); if char == " " { usleep(450_000) } }
        usleep(300_000)
        print("\(line)| => \(DispatchQueue.main.sync { view.string })|")
    }
    DispatchQueue.main.sync { TISSelectInputSource(original); exit(0) }
}
app.run()
