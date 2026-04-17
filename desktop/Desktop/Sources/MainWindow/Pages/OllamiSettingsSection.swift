import SwiftUI

struct OllamiSettingsSection: View {
  @ObservedObject private var settings = OllamiSettings.shared
  @Binding var highlightedSettingId: String?

  @State private var ollamaURLDraft = ""
  @State private var backendURLDraft = ""
  @State private var availableModels: [String] = []
  @State private var isFetchingModels = false
  @State private var fetchError: String?
  @State private var newPluginURL = ""
  @State private var showAddPlugin = false

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
      Task { await fetchModels() }
    }
  }

  // MARK: - Ollama Card

  private var ollamaCard: some View {
    settingsCard(settingId: "ollami.ollama") {
      VStack(alignment: .leading, spacing: 16) {
        cardHeader(
          icon: "server.rack",
          title: "Ollama",
          subtitle: "Local LLM inference server"
        )

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
                  .overlay(
                    RoundedRectangle(cornerRadius: 8)
                      .stroke(OmiColors.backgroundQuaternary, lineWidth: 1)
                  )
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
                ProgressView()
                  .scaleEffect(0.6)
                  .frame(width: 16, height: 16)
              } else {
                Image(systemName: "arrow.clockwise")
                  .scaledFont(size: 12)
                  .foregroundColor(OmiColors.textTertiary)
              }
            }
            .buttonStyle(.plain)
            .disabled(isFetchingModels)
          }

          if let err = fetchError {
            Text(err)
              .scaledFont(size: 12)
              .foregroundColor(OmiColors.error ?? .red)
          } else if availableModels.isEmpty && !isFetchingModels {
            Text("No models found — is Ollama running?")
              .scaledFont(size: 12)
              .foregroundColor(OmiColors.textTertiary)
          } else {
            Picker("", selection: $settings.activeModel) {
              Text("— select a model —").tag("")
              ForEach(availableModels, id: \.self) { model in
                Text(model).tag(model)
              }
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
        cardHeader(
          icon: "waveform",
          title: "Whisper",
          subtitle: "Local speech-to-text model size"
        )

        Picker("", selection: $settings.whisperModel) {
          ForEach(OllamiSettings.whisperModels, id: \.id) { m in
            Text(m.label).tag(m.id)
          }
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
          icon: "network",
          title: "Local Backend",
          subtitle: "FastAPI server that bridges the app to Ollama and Whisper"
        )

        HStack(spacing: 8) {
          TextField("http://localhost:8080", text: $backendURLDraft)
            .textFieldStyle(.plain)
            .scaledFont(size: 13)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .fill(OmiColors.backgroundQuaternary.opacity(0.6))
                .overlay(
                  RoundedRectangle(cornerRadius: 8)
                    .stroke(OmiColors.backgroundQuaternary, lineWidth: 1)
                )
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
            icon: "puzzlepiece.extension",
            title: "Webhook Plugins",
            subtitle: "URLs called after conversations end"
          )
          Spacer()
          Button {
            showAddPlugin.toggle()
          } label: {
            Image(systemName: showAddPlugin ? "minus.circle" : "plus.circle")
              .scaledFont(size: 16)
              .foregroundColor(OmiColors.purplePrimary ?? .accentColor)
          }
          .buttonStyle(.plain)
        }

        if showAddPlugin {
          HStack(spacing: 8) {
            TextField("https://example.com/webhook", text: $newPluginURL)
              .textFieldStyle(.plain)
              .scaledFont(size: 13)
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .fill(OmiColors.backgroundQuaternary.opacity(0.6))
                  .overlay(
                    RoundedRectangle(cornerRadius: 8)
                      .stroke(OmiColors.backgroundQuaternary, lineWidth: 1)
                  )
              )
              .onSubmit { addPlugin() }

            Button("Add") { addPlugin() }
              .buttonStyle(SmallPrimaryButtonStyle())
              .disabled(newPluginURL.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }

        if settings.plugins.isEmpty {
          Text("No plugins configured")
            .scaledFont(size: 13)
            .foregroundColor(OmiColors.textTertiary)
        } else {
          VStack(spacing: 6) {
            ForEach(settings.plugins, id: \.self) { url in
              HStack(spacing: 8) {
                Image(systemName: "link")
                  .scaledFont(size: 12)
                  .foregroundColor(OmiColors.textTertiary)

                Text(url)
                  .scaledFont(size: 13)
                  .foregroundColor(OmiColors.textSecondary)
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                  removePlugin(url)
                } label: {
                  Image(systemName: "trash")
                    .scaledFont(size: 12)
                    .foregroundColor(OmiColors.textTertiary)
                }
                .buttonStyle(.plain)
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .fill(OmiColors.backgroundQuaternary.opacity(0.4))
              )
            }
          }
        }
      }
    }
  }

  // MARK: - Helpers

  private func cardHeader(icon: String, title: String, subtitle: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .scaledFont(size: 18)
        .foregroundColor(OmiColors.purplePrimary ?? .accentColor)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .scaledFont(size: 15, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Text(subtitle)
          .scaledFont(size: 12)
          .foregroundColor(OmiColors.textTertiary)
      }
    }
  }

  private func settingsCard<Content: View>(
    settingId: String? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(OmiColors.backgroundTertiary.opacity(0.5))
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(OmiColors.backgroundQuaternary.opacity(0.3), lineWidth: 1)
          )
      )
  }

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
  }

  private func addPlugin() {
    let url = newPluginURL.trimmingCharacters(in: .whitespaces)
    guard !url.isEmpty, !settings.plugins.contains(url) else { return }
    settings.plugins.append(url)
    settings.save()
    newPluginURL = ""
    showAddPlugin = false
  }

  private func removePlugin(_ url: String) {
    settings.plugins.removeAll { $0 == url }
    settings.save()
  }

  private func fetchModels() async {
    isFetchingModels = true
    fetchError = nil
    defer { isFetchingModels = false }

    let base = settings.ollamaURL.hasSuffix("/") ? settings.ollamaURL : settings.ollamaURL + "/"
    guard let url = URL(string: "\(base)api/tags") else {
      fetchError = "Invalid Ollama URL"
      return
    }

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
