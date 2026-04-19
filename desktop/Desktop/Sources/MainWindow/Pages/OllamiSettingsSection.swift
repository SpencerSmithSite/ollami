import SwiftUI

// MARK: - Plugin model

private struct PluginItem: Identifiable, Codable {
  let id: String
  var name: String
  var trigger: String
  var webhookURL: String
  var enabled: Bool

  enum CodingKeys: String, CodingKey {
    case id, name, trigger, enabled
    case webhookURL = "webhook_url"
  }
}

private enum PluginTrigger: String, CaseIterable {
  case conversationEnd = "on_conversation_end"
  case memoryCreated = "on_memory_created"
  case chatMessage = "on_chat_message"

  var label: String {
    switch self {
    case .conversationEnd: return "Conversation ends"
    case .memoryCreated: return "Memory created"
    case .chatMessage: return "Chat message"
    }
  }
}

// MARK: - Main view

struct OllamiSettingsSection: View {
  @ObservedObject private var settings = OllamiSettings.shared
  @Binding var highlightedSettingId: String?

  // Ollama card state
  @State private var ollamaURLDraft = ""
  @State private var availableModels: [String] = []
  @State private var isFetchingModels = false
  @State private var fetchError: String?

  // Backend card state
  @State private var backendURLDraft = ""

  // Plugin card state
  @State private var plugins: [PluginItem] = []
  @State private var isLoadingPlugins = false
  @State private var pluginError: String?
  @State private var showAddPlugin = false
  @State private var newPluginName = ""
  @State private var newPluginURL = ""
  @State private var newPluginTrigger: PluginTrigger = .conversationEnd

  init(highlightedSettingId: Binding<String?> = .constant(nil)) {
    self._highlightedSettingId = highlightedSettingId
  }

  var body: some View {
    VStack(spacing: 20) {
      ollamaCard
      whisperCard
      backendCard
      pluginsCard
    }
    .onAppear {
      ollamaURLDraft = settings.ollamaURL
      backendURLDraft = settings.backendURL
      Task {
        await fetchModels()
        await fetchPlugins()
      }
    }
  }

  // MARK: - Ollama Card

  private var ollamaCard: some View {
    settingsCard(settingId: "ollami.ollama") {
      VStack(alignment: .leading, spacing: 16) {
        cardHeader(icon: "server.rack", title: "Ollama", subtitle: "Local LLM inference server")

        VStack(alignment: .leading, spacing: 8) {
          Text("Base URL")
            .scaledFont(size: 13, weight: .medium)
            .foregroundColor(OmiColors.textSecondary)

          HStack(spacing: 8) {
            TextField("http://localhost:11434", text: $ollamaURLDraft)
              .textFieldStyle(.plain)
              .scaledFont(size: 13)
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .fill(OmiColors.backgroundQuaternary.opacity(0.6))
                  .overlay(RoundedRectangle(cornerRadius: 8).stroke(OmiColors.backgroundQuaternary, lineWidth: 1))
              )
              .onSubmit { commitOllamaURL() }

            Button("Save") { commitOllamaURL() }
              .buttonStyle(SmallPrimaryButtonStyle())
          }
        }

        Divider().background(OmiColors.backgroundQuaternary.opacity(0.5))

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Active Model")
              .scaledFont(size: 13, weight: .medium)
              .foregroundColor(OmiColors.textSecondary)
            Spacer()
            Button {
              Task { await fetchModels() }
            } label: {
              if isFetchingModels {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
              } else {
                Image(systemName: "arrow.clockwise").scaledFont(size: 12).foregroundColor(OmiColors.textTertiary)
              }
            }
            .buttonStyle(.plain)
            .disabled(isFetchingModels)
          }

          if let err = fetchError {
            Text(err).scaledFont(size: 12).foregroundColor(OmiColors.error ?? .red)
          } else if availableModels.isEmpty && !isFetchingModels {
            Text("No models found — is Ollama running?").scaledFont(size: 12).foregroundColor(OmiColors.textTertiary)
          } else {
            Picker("", selection: $settings.activeModel) {
              Text("— select a model —").tag("")
              ForEach(availableModels, id: \.self) { model in Text(model).tag(model) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: settings.activeModel) { _, _ in settings.save() }
          }
        }
      }
    }
  }

  // MARK: - Whisper Card

  private var whisperCard: some View {
    settingsCard(settingId: "ollami.whisper") {
      VStack(alignment: .leading, spacing: 12) {
        cardHeader(icon: "waveform", title: "Whisper", subtitle: "Local speech-to-text model size")
        Picker("", selection: $settings.whisperModel) {
          ForEach(OllamiSettings.whisperModels, id: \.id) { m in Text(m.label).tag(m.id) }
        }
        .pickerStyle(.segmented)
        .onChange(of: settings.whisperModel) { _, _ in settings.save() }
      }
    }
  }

  // MARK: - Backend Card

  private var backendCard: some View {
    settingsCard(settingId: "ollami.backend") {
      VStack(alignment: .leading, spacing: 12) {
        cardHeader(
          icon: "network", title: "Local Backend",
          subtitle: "FastAPI server that bridges the app to Ollama and Whisper")

        HStack(spacing: 8) {
          TextField("http://localhost:8080", text: $backendURLDraft)
            .textFieldStyle(.plain)
            .scaledFont(size: 13)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .fill(OmiColors.backgroundQuaternary.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(OmiColors.backgroundQuaternary, lineWidth: 1))
            )
            .onSubmit { commitBackendURL() }

          Button("Save") { commitBackendURL() }
            .buttonStyle(SmallPrimaryButtonStyle())
        }
      }
    }
  }

  // MARK: - Plugins Card

  private var pluginsCard: some View {
    settingsCard(settingId: "ollami.plugins") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          cardHeader(
            icon: "puzzlepiece.extension", title: "Webhook Plugins",
            subtitle: "HTTP callbacks fired after conversation, memory, and chat events")
          Spacer()
          if isLoadingPlugins {
            ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
          } else {
            Button {
              showAddPlugin.toggle()
              if showAddPlugin { newPluginName = ""; newPluginURL = ""; newPluginTrigger = .conversationEnd }
            } label: {
              Image(systemName: showAddPlugin ? "minus.circle" : "plus.circle")
                .scaledFont(size: 16)
                .foregroundColor(OmiColors.purplePrimary ?? .accentColor)
            }
            .buttonStyle(.plain)
          }
        }

        if let err = pluginError {
          Text(err).scaledFont(size: 12).foregroundColor(OmiColors.error ?? .red)
        }

        if showAddPlugin {
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              TextField("Plugin name", text: $newPluginName)
                .textFieldStyle(.plain)
                .scaledFont(size: 13)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                  RoundedRectangle(cornerRadius: 8)
                    .fill(OmiColors.backgroundQuaternary.opacity(0.6))
                    .overlay(
                      RoundedRectangle(cornerRadius: 8).stroke(OmiColors.backgroundQuaternary, lineWidth: 1))
                )
                .frame(maxWidth: 160)

              TextField("https://example.com/webhook", text: $newPluginURL)
                .textFieldStyle(.plain)
                .scaledFont(size: 13)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                  RoundedRectangle(cornerRadius: 8)
                    .fill(OmiColors.backgroundQuaternary.opacity(0.6))
                    .overlay(
                      RoundedRectangle(cornerRadius: 8).stroke(OmiColors.backgroundQuaternary, lineWidth: 1))
                )
            }

            HStack(spacing: 8) {
              Picker("", selection: $newPluginTrigger) {
                ForEach(PluginTrigger.allCases, id: \.self) { t in Text(t.label).tag(t) }
              }
              .labelsHidden()
              .frame(maxWidth: .infinity, alignment: .leading)

              Button("Add") { Task { await addPlugin() } }
                .buttonStyle(SmallPrimaryButtonStyle())
                .disabled(newPluginName.trimmingCharacters(in: .whitespaces).isEmpty
                  || newPluginURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
          }
          .padding(12)
          .background(
            RoundedRectangle(cornerRadius: 8).fill(OmiColors.backgroundQuaternary.opacity(0.3))
          )
        }

        if plugins.isEmpty && !isLoadingPlugins {
          Text("No plugins configured")
            .scaledFont(size: 13)
            .foregroundColor(OmiColors.textTertiary)
        } else {
          VStack(spacing: 6) {
            ForEach(plugins) { plugin in
              pluginRow(plugin)
            }
          }
        }
      }
    }
  }

  private func pluginRow(_ plugin: PluginItem) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "link")
        .scaledFont(size: 12)
        .foregroundColor(OmiColors.textTertiary)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(plugin.name)
            .scaledFont(size: 13, weight: .medium)
            .foregroundColor(OmiColors.textPrimary)

          Text(triggerLabel(plugin.trigger))
            .scaledFont(size: 11, weight: .medium)
            .foregroundColor(OmiColors.purplePrimary ?? .accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill((OmiColors.purplePrimary ?? .accentColor).opacity(0.12))
            )
        }

        Text(plugin.webhookURL)
          .scaledFont(size: 11)
          .foregroundColor(OmiColors.textTertiary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Toggle("", isOn: Binding(
        get: { plugin.enabled },
        set: { newVal in Task { await togglePlugin(plugin, enabled: newVal) } }
      ))
      .labelsHidden()
      .toggleStyle(.switch)
      .scaleEffect(0.8)

      Button {
        Task { await deletePlugin(plugin) }
      } label: {
        Image(systemName: "trash")
          .scaledFont(size: 12)
          .foregroundColor(OmiColors.textTertiary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(OmiColors.backgroundQuaternary.opacity(0.4))
    )
  }

  private func triggerLabel(_ trigger: String) -> String {
    PluginTrigger(rawValue: trigger)?.label ?? trigger
  }

  // MARK: - Helpers

  private func cardHeader(icon: String, title: String, subtitle: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .scaledFont(size: 18)
        .foregroundColor(OmiColors.purplePrimary ?? .accentColor)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(title).scaledFont(size: 15, weight: .semibold).foregroundColor(OmiColors.textPrimary)
        Text(subtitle).scaledFont(size: 12).foregroundColor(OmiColors.textTertiary)
      }
    }
  }

  private func settingsCard<Content: View>(settingId: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(OmiColors.backgroundTertiary.opacity(0.5))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(OmiColors.backgroundQuaternary.opacity(0.3), lineWidth: 1))
      )
  }

  // MARK: - Ollama actions

  private func commitOllamaURL() {
    let trimmed = ollamaURLDraft.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    settings.ollamaURL = trimmed
    settings.save()
    Task { await fetchModels() }
  }

  private func commitBackendURL() {
    let trimmed = backendURLDraft.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    settings.backendURL = trimmed
    settings.save()
    Task { await fetchPlugins() }
  }

  private func fetchModels() async {
    isFetchingModels = true
    fetchError = nil
    defer { isFetchingModels = false }

    let base = settings.ollamaURL.hasSuffix("/") ? settings.ollamaURL : settings.ollamaURL + "/"
    guard let url = URL(string: "\(base)api/tags") else { fetchError = "Invalid Ollama URL"; return }

    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      struct TagsResponse: Decodable {
        struct ModelEntry: Decodable { let name: String }
        let models: [ModelEntry]
      }
      let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
      availableModels = decoded.models.map(\.name)
      if !availableModels.isEmpty && settings.activeModel.isEmpty {
        settings.activeModel = availableModels[0]
        settings.save()
      }
    } catch {
      fetchError = "Could not reach Ollama: \(error.localizedDescription)"
    }
  }

  // MARK: - Plugin network actions

  private func authToken() -> String? {
    let path =
      ProcessInfo.processInfo.environment["TOKEN_PATH"]
      ?? (NSHomeDirectory() + "/.ollami/token")
    return try? String(contentsOfFile: path, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func pluginRequest(path: String, method: String = "GET", body: Data? = nil) -> URLRequest? {
    let base = settings.backendURL.hasSuffix("/")
      ? String(settings.backendURL.dropLast()) : settings.backendURL
    guard let url = URL(string: "\(base)\(path)") else { return nil }
    var req = URLRequest(url: url)
    req.httpMethod = method
    if let token = authToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    return req
  }

  private func fetchPlugins() async {
    isLoadingPlugins = true
    pluginError = nil
    defer { isLoadingPlugins = false }

    guard let req = pluginRequest(path: "/v1/plugins") else { pluginError = "Invalid backend URL"; return }
    do {
      let (data, _) = try await URLSession.shared.data(for: req)
      let decoder = JSONDecoder()
      plugins = try decoder.decode([PluginItem].self, from: data)
    } catch {
      pluginError = "Could not load plugins: \(error.localizedDescription)"
    }
  }

  private func addPlugin() async {
    let name = newPluginName.trimmingCharacters(in: .whitespaces)
    let urlStr = newPluginURL.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty, !urlStr.isEmpty else { return }

    struct PluginCreate: Encodable {
      let name: String; let trigger: String; let webhook_url: String
    }
    guard let body = try? JSONEncoder().encode(PluginCreate(name: name, trigger: newPluginTrigger.rawValue, webhook_url: urlStr)),
      let req = pluginRequest(path: "/v1/plugins", method: "POST", body: body)
    else { return }

    do {
      let (data, _) = try await URLSession.shared.data(for: req)
      let newPlugin = try JSONDecoder().decode(PluginItem.self, from: data)
      plugins.append(newPlugin)
      newPluginName = ""; newPluginURL = ""; showAddPlugin = false
    } catch {
      pluginError = "Could not add plugin: \(error.localizedDescription)"
    }
  }

  private func deletePlugin(_ plugin: PluginItem) async {
    guard let req = pluginRequest(path: "/v1/plugins/\(plugin.id)", method: "DELETE") else { return }
    do {
      _ = try await URLSession.shared.data(for: req)
      plugins.removeAll { $0.id == plugin.id }
    } catch {
      pluginError = "Could not delete plugin: \(error.localizedDescription)"
    }
  }

  private func togglePlugin(_ plugin: PluginItem, enabled: Bool) async {
    struct Patch: Encodable { let enabled: Bool }
    guard let body = try? JSONEncoder().encode(Patch(enabled: enabled)),
      let req = pluginRequest(path: "/v1/plugins/\(plugin.id)", method: "PATCH", body: body)
    else { return }
    do {
      let (data, _) = try await URLSession.shared.data(for: req)
      let updated = try JSONDecoder().decode(PluginItem.self, from: data)
      if let idx = plugins.firstIndex(where: { $0.id == plugin.id }) {
        plugins[idx] = updated
      }
    } catch {
      pluginError = "Could not update plugin: \(error.localizedDescription)"
    }
  }
}

// MARK: - Button style

private struct SmallPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaledFont(size: 13, weight: .medium)
      .foregroundColor(.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill((OmiColors.purplePrimary ?? .accentColor).opacity(configuration.isPressed ? 0.7 : 1))
      )
  }
}
