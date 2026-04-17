import Foundation

@MainActor
class OllamiSettings: ObservableObject {
  static let shared = OllamiSettings()

  private static let ollamaURLKey = "ollami.ollamaURL"
  private static let activeModelKey = "ollami.activeModel"
  private static let whisperModelKey = "ollami.whisperModel"
  private static let backendURLKey = "ollami.backendURL"
  private static let pluginsKey = "ollami.plugins"

  @Published var ollamaURL: String
  @Published var activeModel: String
  @Published var whisperModel: String
  @Published var backendURL: String
  @Published var plugins: [String]

  static let whisperModels: [(id: String, label: String)] = [
    ("tiny", "Tiny (fastest, ~75 MB)"),
    ("base", "Base (balanced, ~150 MB)"),
    ("small", "Small (accurate, ~500 MB)"),
    ("medium", "Medium (best, ~1.5 GB)"),
  ]

  private init() {
    let ud = UserDefaults.standard
    ollamaURL = ud.string(forKey: Self.ollamaURLKey) ?? "http://localhost:11434"
    activeModel = ud.string(forKey: Self.activeModelKey) ?? ""
    whisperModel = ud.string(forKey: Self.whisperModelKey) ?? "base"
    backendURL = ud.string(forKey: Self.backendURLKey) ?? "http://localhost:8080"
    plugins = ud.stringArray(forKey: Self.pluginsKey) ?? []
  }

  func save() {
    let ud = UserDefaults.standard
    ud.set(ollamaURL, forKey: Self.ollamaURLKey)
    ud.set(activeModel, forKey: Self.activeModelKey)
    ud.set(whisperModel, forKey: Self.whisperModelKey)
    ud.set(backendURL, forKey: Self.backendURLKey)
    ud.set(plugins, forKey: Self.pluginsKey)
  }
}
