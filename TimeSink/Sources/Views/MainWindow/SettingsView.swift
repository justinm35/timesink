import SwiftUI

/// Application settings view.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var softwareUpdater: SoftwareUpdater

    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var pollInterval: Double = 3
    @State private var idleThreshold: Double = 120
    @State private var categorizationInterval: Int = 30
    @State private var retentionDays: Int = 90
    @State private var showDeleteConfirmation = false
    @State private var apiKeySaveMessage: String?
    @State private var apiKeySaveSucceeded = false

    private let cardSpacing: CGFloat = 18
    private let sectionSpacing: CGFloat = 14
    private let rowSpacing: CGFloat = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: cardSpacing) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // API Key Section
                GroupBox("AI Providers") {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        Text("Choose your default provider for categorization. Keys are stored securely in the macOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(AIProvider.allCases, id: \.self) { provider in
                                SettingsProviderCard(provider: provider, isSelected: provider == appState.selectedAIProvider)
                                    .onTapGesture {
                                        appState.setSelectedAIProvider(provider)
                                        apiKey = KeychainHelper.apiKey(for: provider) ?? ""
                                        apiKeySaveMessage = nil
                                    }
                            }
                        }

                        HStack(alignment: .center, spacing: 10) {
                            if showAPIKey {
                                TextField(appState.selectedAIProvider.placeholder, text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField(appState.selectedAIProvider.placeholder, text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(showAPIKey ? "Hide" : "Show") {
                                showAPIKey.toggle()
                            }
                            .buttonStyle(.bordered)

                            Button("Save") {
                                saveAPIKey()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if let apiKeySaveMessage {
                            Label(apiKeySaveMessage, systemImage: apiKeySaveSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(apiKeySaveSucceeded ? .green : .red)
                        } else if KeychainHelper.exists(key: appState.selectedAIProvider.keychainKey) {
                            Label("\(appState.selectedAIProvider.displayName) key is saved in Keychain", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        Text("Default model: \(appState.selectedAIProvider.model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(SettingsCardGroupBoxStyle())

                // Tracking Section
                GroupBox("Tracking") {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Poll interval:")
                                .frame(width: 110, alignment: .leading)
                            Slider(value: $pollInterval, in: 1...10, step: 1)
                            Text("\(Int(pollInterval))s")
                                .monospacedDigit()
                                .frame(width: 30)
                        }

                        HStack(alignment: .center, spacing: 12) {
                            Text("Idle threshold:")
                                .frame(width: 110, alignment: .leading)
                            Slider(value: $idleThreshold, in: 30...600, step: 30)
                            Text(DateFormatting.formatDuration(seconds: Int(idleThreshold)))
                                .monospacedDigit()
                                .frame(width: 50)
                        }

                        Toggle("Treat meetings as active time", isOn: Binding(
                            get: { appState.treatMeetingsAsActiveTime },
                            set: { appState.treatMeetingsAsActiveTime = $0 }
                        ))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(SettingsCardGroupBoxStyle())

                // Browser Section
                GroupBox("Browser Tracking") {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        Text("Detected browser profiles:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if appState.browserTracker.profilePaths.isEmpty {
                            Text("No browser profiles found")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(appState.browserTracker.profilePaths, id: \.historyPath) { profile in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("\(profile.browserName) - \(profile.profileName)")
                                        .font(.body)
                                    Spacer()
                                    Text(profile.historyPath)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(SettingsCardGroupBoxStyle())

                // Categorization Section
                GroupBox("AI Categorization") {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Auto-categorize every:")
                                .frame(width: 135, alignment: .leading)
                            Picker("", selection: $categorizationInterval) {
                                Text("15 min").tag(15)
                                Text("30 min").tag(30)
                                Text("1 hour").tag(60)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Button("Categorize Now") {
                                Task {
                                    await appState.categorizeNow()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.isCategorizing)

                            if appState.isCategorizing {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            if let status = appState.categorizationStatusMessage {
                                Label(
                                    status,
                                    systemImage: appState.categorizationStatusSucceeded ? "checkmark.circle.fill" : (appState.isCategorizing ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
                                )
                                .font(.caption)
                                .foregroundStyle(appState.isCategorizing ? Color.secondary : (appState.categorizationStatusSucceeded ? Color.green : Color.red))
                            } else {
                                Text("Engine ready")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(SettingsCardGroupBoxStyle())

                // Data Section
                GroupBox("Data Management") {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Keep data for:")
                                .frame(width: 110, alignment: .leading)
                            Picker("", selection: $retentionDays) {
                                Text("30 days").tag(30)
                                Text("90 days").tag(90)
                                Text("1 year").tag(365)
                                Text("Forever").tag(0)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 400)
                        }

                        HStack(alignment: .center, spacing: 10) {
                            Button("Export CSV") {
                                exportData(format: .csv)
                            }
                            .buttonStyle(.bordered)

                            Button("Export JSON") {
                                exportData(format: .json)
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Delete All Data") {
                                showDeleteConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(SettingsCardGroupBoxStyle())

                // Updates Section
                GroupBox("Software Updates") {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        Toggle("Automatically check for updates", isOn: $softwareUpdater.automaticallyChecksForUpdates)

                        HStack(alignment: .center, spacing: 10) {
                            Button("Check for Updates...") {
                                softwareUpdater.checkForUpdates()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!softwareUpdater.canCheckForUpdates)

                            if let lastCheck = softwareUpdater.lastUpdateCheckDate {
                                Text("Last checked: \(lastCheck, format: .relative(presentation: .named))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(SettingsCardGroupBoxStyle())

                // Permissions Section
                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: appState.isAccessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(appState.isAccessibilityGranted ? .green : .red)
                            Text("Accessibility Access")
                            Spacer()
                            if !appState.isAccessibilityGranted {
                                Button("Open Settings") {
                                    AccessibilityHelper.openAccessibilitySettings()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(SettingsCardGroupBoxStyle())
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear {
            apiKey = KeychainHelper.apiKey(for: appState.selectedAIProvider) ?? ""
        }
        .alert("Reset TimeSink?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will delete all tracked activity, remove saved API keys, and reset the app to its initial setup. This cannot be undone.")
        }
    }

    // MARK: - Export

    private enum ExportFormat { case csv, json }

    private func exportData(format: ExportFormat) {
        let (start, _) = DateFormatting.dayRange(for: Date.distantPast)
        let (_, end) = DateFormatting.dayRange(for: Date())

        guard let records = try? appState.database.fetchRecords(from: start, to: end) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .csv ? [.commaSeparatedText] : [.json]
        panel.nameFieldStringValue = format == .csv ? "timesink_export.csv" : "timesink_export.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data: Data
            switch format {
            case .csv:
                data = exportAsCSV(records)
            case .json:
                data = try exportAsJSON(records)
            }
            try data.write(to: url)
        } catch {
            print("Export failed: \(error)")
        }
    }

    private func exportAsCSV(_ records: [ActivityRecord]) -> Data {
        var csv = "id,app_name,window_title,detail,detail_type,started_at,ended_at,duration_seconds,is_idle,category_id\n"
        let df = ISO8601DateFormatter()

        for record in records {
            let fields = [
                "\(record.id ?? 0)",
                "\"\(record.appName)\"",
                "\"\(record.windowTitle.replacingOccurrences(of: "\"", with: "\"\""))\"",
                "\"\(record.detail ?? "")\"",
                record.detailType.rawValue,
                df.string(from: record.startedAt),
                record.endedAt.map { df.string(from: $0) } ?? "",
                "\(record.durationSeconds ?? 0)",
                "\(record.isIdle)",
                "\(record.categoryId ?? 0)",
            ]
            csv += fields.joined(separator: ",") + "\n"
        }

        return csv.data(using: .utf8) ?? Data()
    }

    private func exportAsJSON(_ records: [ActivityRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    private func deleteAllData() {
        appState.resetAllData()
    }

    private func saveAPIKey() {
        do {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                KeychainHelper.delete(key: appState.selectedAIProvider.keychainKey)
                apiKeySaveSucceeded = true
                apiKeySaveMessage = "API key removed"
                return
            }

            try KeychainHelper.save(
                key: appState.selectedAIProvider.keychainKey,
                value: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            let savedValue = try KeychainHelper.loadRequired(key: appState.selectedAIProvider.keychainKey)
            let expectedValue = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            guard savedValue == expectedValue else {
                apiKeySaveSucceeded = false
                apiKeySaveMessage = "Key saved, but read-back mismatched the saved value"
                return
            }

            apiKeySaveSucceeded = true
            apiKeySaveMessage = "\(appState.selectedAIProvider.displayName) key saved successfully"
        } catch {
            apiKeySaveSucceeded = false
            apiKeySaveMessage = error.localizedDescription
        }
    }
}

private struct SettingsProviderCard: View {
    let provider: AIProvider
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: provider.iconName)
                .foregroundStyle(Color(hex: provider.providerAccentHex))
            Text(provider.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(provider.shortName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(isSelected ? 0.07 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color(hex: provider.providerAccentHex) : Color.primary.opacity(0.07), lineWidth: isSelected ? 2 : 1)
        }
    }
}

private struct SettingsCardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            configuration.content
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.045),
                    Color.primary.opacity(0.028),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }
}
