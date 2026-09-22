import AppKit
import SwiftUI

/// Shown while there is no Accessibility grant: at launch, and from the menu item. `afterUpdate` picks the text
/// for a Mac that had the grant before — the build's signature changed with the update and macOS forgot it.
/// Polls the grant itself while open; the tap is raised by Switcher's own timer, independently.
struct OnboardingView: View {
    let afterUpdate: Bool
    let openAccessibility: () -> Void
    let close: () -> Void
    @State private var granted = AXIsProcessTrusted()
    @State private var sample = ""
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("ghbdtn vbh").font(.title.bold())
            if granted {
                Label("Access granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Try it: type ghbdtn vbh and press space").foregroundStyle(.secondary)
                TextField("", text: $sample).textFieldStyle(.roundedBorder).frame(width: 260)
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            } else {
                Text(NSLocalizedString(afterUpdate
                    ? "The update changed the app's signature and macOS forgot the permission. Untick ghbdtn vbh in the list and tick it again."
                    : "To fix the layout, the app has to see what you type. Allow it under Accessibility.", comment: ""))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Accessibility settings", action: openAccessibility).keyboardShortcut(.defaultAction)
                Label("Waiting for permission…", systemImage: "hourglass").foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 420)
        .onReceive(tick) { _ in granted = AXIsProcessTrusted() }
    }
}
