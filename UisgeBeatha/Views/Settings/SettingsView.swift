import OSLog
import SwiftData
import SwiftUI

/// Settings tab (PRD F8): export via ShareLink, About, debug lookup source.
struct SettingsView: View {
    @Query private var bottles: [Bottle]
    @Environment(\.syncMonitor) private var syncMonitor

    @State private var jsonFileURL: URL?
    @State private var csvFileURL: URL?

    @AppStorage(CascadeBarcodeLookupService.debugSourceDefaultsKey)
    private var lastLookupSource = "—"

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "Settings")

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let jsonFileURL {
                        ShareLink(item: jsonFileURL) {
                            Label(Strings.Settings.exportJSON, systemImage: "square.and.arrow.up")
                        }
                    }
                    if let csvFileURL {
                        ShareLink(item: csvFileURL) {
                            Label(Strings.Settings.exportCSV, systemImage: "tablecells")
                        }
                    }
                } header: {
                    Text(Strings.Settings.exportSection)
                } footer: {
                    Text(Strings.Settings.exportPhotosNote)
                }

                if let syncMonitor {
                    Section {
                        LabeledContent(
                            Strings.Settings.syncStatus,
                            value: Strings.Settings.syncTitle(syncMonitor.status)
                        )
                        Text(Strings.Settings.syncExplanation(syncMonitor.status))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(Strings.Settings.syncSection)
                    }
                }

                Section(Strings.Settings.privacySection) {
                    Text(Strings.Settings.privacyNetwork)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(Strings.Settings.privacyICloud)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(Strings.Settings.aboutSection) {
                    LabeledContent(Strings.Settings.version, value: appVersion)
                    Text(Strings.Settings.dataNotice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                // Developer diagnostics only; never shipped in a release
                // build.
                Section(Strings.Settings.debugSection) {
                    LabeledContent(Strings.Settings.lastLookupSource, value: lastLookupSource)
                }
                #endif
            }
            .navigationTitle(Strings.Settings.title)
            .onAppear(perform: regenerateExports)
        }
    }

    /// Cheap for a personal collection; regenerated on every visit so the
    /// share sheets always carry current data.
    private func regenerateExports() {
        let sorted = CollectionSortKey.name.sorted(Array(bottles))
        let directory = FileManager.default.temporaryDirectory
        do {
            let jsonURL = directory.appendingPathComponent("UisgeBeatha-Collection.json")
            try ExportService.jsonData(from: sorted).write(to: jsonURL, options: .atomic)
            jsonFileURL = jsonURL

            let csvURL = directory.appendingPathComponent("UisgeBeatha-Collection.csv")
            try Data(ExportService.csv(from: sorted).utf8).write(to: csvURL, options: .atomic)
            csvFileURL = csvURL
        } catch {
            Self.logger.error("Export generation failed: \(error)")
            jsonFileURL = nil
            csvFileURL = nil
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: Bottle.self, inMemory: true)
}
