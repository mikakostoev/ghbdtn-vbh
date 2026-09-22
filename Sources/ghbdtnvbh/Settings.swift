import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private func appFile(_ name: String) -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = support.appendingPathComponent("ghbdtn vbh"), old = support.appendingPathComponent("LayoutSwitcher")
    // The app was called LayoutSwitcher up to 1.1: the three files move over once, the first time 2.0 runs.
    // If the move ever fails, the next line silently creates an empty new folder and the exceptions, learned
    // words and excluded sites look like they vanished — they are intact under the old "LayoutSwitcher" folder.
    if !FileManager.default.fileExists(atPath: dir.path), FileManager.default.fileExists(atPath: old.path) {
        try? FileManager.default.moveItem(at: old, to: dir)
    }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
    return file
}

let exceptionsFile = appFile("exceptions.txt")  // never autoswitch these
let learnedFile = appFile("words.txt")          // words the dictionaries don't know, learned from manual converts

let sitesFile = appFile("sites.txt")            // no autoswitching on these sites

/// Lines may be pasted as they come: "https://www.github.com/me" means "github.com".
func excludedSites() -> Set<String> {
    Set(wordSet(sitesFile).compactMap { line in
        let host = URL(string: line.contains("://") ? line : "https://" + line)?.host ?? line
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    })
}

/// Re-read only when the file changed: this is asked on every word from inside the event tap, and words.txt
/// grows for years — 5 000 learned words cost 3 ms to parse against 3 microseconds to stat.
/// Not `URL.resourceValues`: it caches inside the URL and goes on reporting the size and date of a stale read.
// ponytail: no lock, everything here runs on the main thread (the event tap source is on the main run loop).
private var cachedWords: [URL: (mtime: timespec, size: off_t, words: Set<String>)] = [:]

func wordSet(_ file: URL) -> Set<String> {
    var info = stat()
    let missing = stat(file.path, &info) != 0
    let mtime = missing ? timespec() : info.st_mtimespec, size: off_t = missing ? -1 : info.st_size
    if let hit = cachedWords[file], hit.mtime.tv_sec == mtime.tv_sec, hit.mtime.tv_nsec == mtime.tv_nsec,
       hit.size == size { return hit.words }
    let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    let words = Set(text.lowercased().split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
    cachedWords[file] = (mtime, size, words)
    return words
}

struct SettingsView: View {
    @AppStorage("enabled") private var enabled = true
    @AppStorage("manualConvert") private var manualConvert = true
    @AppStorage("oneLetterWords") private var oneLetterWords = true
    @AppStorage("learnWords") private var learnWords = true
    @AppStorage("convertTrigger") private var convertTrigger = "double"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var words = ""
    @State private var learned = ""
    @State private var apps: [String] = []
    @State private var sites = ""

    var body: some View {
        TabView {
            Form {
                Toggle("Switch the layout automatically", isOn: $enabled)
                Toggle("Fix short words before a switched one (я, ну, мы, the…)", isOn: $oneLetterWords)
                Toggle("Convert the last word or the selection with Option", isOn: $manualConvert)
                Picker("Option press", selection: $convertTrigger) {
                    Text("Single").tag("single")
                    Text("Double").tag("double")
                }
                .pickerStyle(.segmented)
                .disabled(!manualConvert)
                Toggle("Remember words converted by hand", isOn: $learnWords)
                    .disabled(!manualConvert)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch {
                            NSAlert(error: error).runModal()
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            .padding()
            .tabItem { Text("General") }

            VStack(alignment: .leading) {
                Text("These words are never switched automatically — one per line.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $words)
                    .font(.body.monospaced())
                    .border(.separator)
                    .onChange(of: words) { try? $0.write(to: exceptionsFile, atomically: true, encoding: .utf8) }
                Text("Learned words: no dictionary knows them, but you converted them by hand, so now they switch by themselves.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $learned)
                    .font(.body.monospaced())
                    .border(.separator)
                    .onChange(of: learned) { try? $0.write(to: learnedFile, atomically: true, encoding: .utf8) }
            }
            .padding()
            .tabItem { Text("Words") }

            VStack(alignment: .leading) {
                Text("The switcher is off in these apps.")
                    .foregroundStyle(.secondary)
                List(apps, id: \.self) { id in
                    HStack {
                        Text(appName(id))
                        Spacer()
                        Button("Remove") { apps.removeAll { $0 == id } }
                    }
                }
                .border(.separator)
                Button("Add app…", action: addApp)
                Text("The layout is never switched by itself on these sites — one per line: github.com")
                    .foregroundStyle(.secondary)
                TextEditor(text: $sites)
                    .font(.body.monospaced())
                    .border(.separator)
                    .onChange(of: sites) { try? $0.write(to: sitesFile, atomically: true, encoding: .utf8) }
            }
            .padding()
            .onChange(of: apps) { UserDefaults.standard.set($0, forKey: "excludedApps") }
            .tabItem { Text("Apps and sites") }
        }
        .padding()
        .frame(width: 480, height: 420)
        .onAppear {
            // Both can change behind our back (menu toggle, learned exceptions), so reload on every open.
            words = (try? String(contentsOf: exceptionsFile, encoding: .utf8)) ?? ""
            learned = (try? String(contentsOf: learnedFile, encoding: .utf8)) ?? ""
            sites = (try? String(contentsOf: sitesFile, encoding: .utf8)) ?? ""
            apps = UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
              !apps.contains(id) else { return }
        apps.append(id)
    }
}
