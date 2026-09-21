import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private func appFile(_ name: String) -> URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LayoutSwitcher")
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

func wordSet(_ file: URL) -> Set<String> {
    let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    return Set(text.lowercased().split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
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
                Toggle("Автоматически переключать раскладку", isOn: $enabled)
                Toggle("Исправлять короткие слова перед переключённым (я, ну, мы, the…)", isOn: $oneLetterWords)
                Toggle("Конвертировать последнее слово или выделенный текст по Option", isOn: $manualConvert)
                Picker("Нажатие Option", selection: $convertTrigger) {
                    Text("Одиночное").tag("single")
                    Text("Двойное").tag("double")
                }
                .pickerStyle(.segmented)
                .disabled(!manualConvert)
                Toggle("Запоминать слова, сконвертированные вручную", isOn: $learnWords)
                    .disabled(!manualConvert)
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch {
                            NSAlert(error: error).runModal()
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            .padding()
            .tabItem { Text("Основные") }

            VStack(alignment: .leading) {
                Text("Эти слова не переключаются автоматически — по одному в строке.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $words)
                    .font(.body.monospaced())
                    .border(.separator)
                    .onChange(of: words) { try? $0.write(to: exceptionsFile, atomically: true, encoding: .utf8) }
                Text("Выученные слова: их нет в словаре, но вы конвертировали их вручную — теперь они переключаются сами.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $learned)
                    .font(.body.monospaced())
                    .border(.separator)
                    .onChange(of: learned) { try? $0.write(to: learnedFile, atomically: true, encoding: .utf8) }
            }
            .padding()
            .tabItem { Text("Слова") }

            VStack(alignment: .leading) {
                Text("В этих приложениях переключатель не работает.")
                    .foregroundStyle(.secondary)
                List(apps, id: \.self) { id in
                    HStack {
                        Text(appName(id))
                        Spacer()
                        Button("Убрать") { apps.removeAll { $0 == id } }
                    }
                }
                .border(.separator)
                Button("Добавить приложение…", action: addApp)
                Text("На этих сайтах раскладка не переключается сама — по одному в строке: github.com")
                    .foregroundStyle(.secondary)
                TextEditor(text: $sites)
                    .font(.body.monospaced())
                    .border(.separator)
                    .onChange(of: sites) { try? $0.write(to: sitesFile, atomically: true, encoding: .utf8) }
            }
            .padding()
            .onChange(of: apps) { UserDefaults.standard.set($0, forKey: "excludedApps") }
            .tabItem { Text("Приложения и сайты") }
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
