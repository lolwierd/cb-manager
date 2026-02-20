import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsModel: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("CBManager")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Settings")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider().overlay(.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aiTitleSection
                    historySection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .frame(width: 500, height: 520)
        .background(.ultraThickMaterial)
    }

    // MARK: - AI Image Titles

    private var aiTitleSection: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Section header — toggle lives inline with the label
            // so enable/disable is a single glance + click.
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.07))
                    )

                Text("AI Image Titles")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Spacer()

                Toggle("", isOn: $settingsModel.imageTitlesEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }

            Text("When you copy an image, CBManager sends it to an AI model via the pi CLI to generate a short descriptive title. Titles appear in the clipboard list and the preview information panel.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(settingsModel.imageTitlesEnabled ? 1 : 0.5)

            // Model configuration
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Model")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !settingsModel.imageTitleModel.isEmpty {
                        Button {
                            settingsModel.imageTitleModel = ""
                        } label: {
                            Text("Reset to default")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }

                TextField(ImageTitleGenerator.defaultModel, text: $settingsModel.imageTitleModel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(settingsModel.imageTitlesEnabled ? 0.06 : 0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                    )
                    .disabled(!settingsModel.imageTitlesEnabled)

                // Resolved model indicator — shows what's actually being used
                HStack(spacing: 5) {
                    Circle()
                        .fill(settingsModel.imageTitlesEnabled ? .green.opacity(0.7) : .white.opacity(0.2))
                        .frame(width: 5, height: 5)

                    if settingsModel.imageTitleModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Using default: \(ImageTitleGenerator.defaultModel)")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Using: \(settingsModel.imageTitleModel)")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("Any pi model with image support works. Run `pi --list-models` to see options.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.quaternary)
            }
            .opacity(settingsModel.imageTitlesEnabled ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.15), value: settingsModel.imageTitlesEnabled)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - History / Auto-Prune

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.07))
                    )

                Text("History")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Spacer()

                Toggle("", isOn: $settingsModel.autoPruneEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }

            Text("Automatically delete clipboard entries older than a set number of days. Pruning runs once each time CBManager launches.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(settingsModel.autoPruneEnabled ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Delete entries older than")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    TextField("90", text: $settingsModel.autoPruneDaysText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .frame(width: 52)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(settingsModel.autoPruneEnabled ? 0.06 : 0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                        )
                        .disabled(!settingsModel.autoPruneEnabled)

                    Text("days")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(settingsModel.autoPruneEnabled ? .orange.opacity(0.7) : .white.opacity(0.2))
                        .frame(width: 5, height: 5)

                    if settingsModel.autoPruneEnabled {
                        Text("Entries older than \(settingsModel.resolvedDays) days will be removed on next launch")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Auto-pruning is off — entries are kept until the 300-entry limit")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .opacity(settingsModel.autoPruneEnabled ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.15), value: settingsModel.autoPruneEnabled)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Settings Model

/// View model that reads/writes settings and notifies the store on changes.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var imageTitlesEnabled: Bool {
        didSet { save() }
    }
    @Published var imageTitleModel: String {
        didSet { save() }
    }
    @Published var autoPruneEnabled: Bool {
        didSet { save() }
    }
    /// Raw text binding for the days field so the user can type freely.
    @Published var autoPruneDaysText: String {
        didSet { save() }
    }

    /// The resolved integer value of the days field, clamped to ≥ 1.
    var resolvedDays: Int {
        max(Int(autoPruneDaysText) ?? 90, 1)
    }

    private let settingsURL: URL
    private let onChanged: (SettingsSnapshot) -> Void

    struct SettingsSnapshot {
        let imageTitlesEnabled: Bool
        let imageTitleModel: String
        let autoPruneEnabled: Bool
        let autoPruneDays: Int
    }

    init(settingsURL: URL, onChanged: @escaping (SettingsSnapshot) -> Void) {
        self.settingsURL = settingsURL
        self.onChanged = onChanged

        let settings = AppModel.loadSettings(at: settingsURL)
        self.imageTitlesEnabled = settings?.resolvedImageTitlesEnabled ?? true
        self.imageTitleModel = settings?.imageTitleModel ?? ""
        self.autoPruneEnabled = settings?.resolvedAutoPruneEnabled ?? false
        self.autoPruneDaysText = "\(settings?.resolvedAutoPruneDays ?? 90)"
    }

    private func save() {
        let days = resolvedDays
        var settings = AppModel.loadSettings(at: settingsURL) ?? AppSettings(shortcut: nil)
        settings = AppSettings(
            shortcut: settings.shortcut,
            imageTitleModel: imageTitleModel.isEmpty ? nil : imageTitleModel,
            imageTitlesEnabled: imageTitlesEnabled,
            autoPruneEnabled: autoPruneEnabled,
            autoPruneDays: days
        )
        AppModel.saveSettings(settings, at: settingsURL)

        onChanged(SettingsSnapshot(
            imageTitlesEnabled: imageTitlesEnabled,
            imageTitleModel: settings.resolvedImageTitleModel,
            autoPruneEnabled: autoPruneEnabled,
            autoPruneDays: days
        ))
    }
}
