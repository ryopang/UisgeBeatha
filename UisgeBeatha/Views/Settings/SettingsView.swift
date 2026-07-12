import SwiftUI

/// Settings tab. v1 grows export here in Phase 6; for now, About only.
struct SettingsView: View {
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "1.0"
    }

    @AppStorage(CascadeBarcodeLookupService.debugSourceDefaultsKey)
    private var lastLookupSource = "—"

    var body: some View {
        NavigationStack {
            Form {
                Section(Strings.Settings.aboutSection) {
                    LabeledContent(Strings.Settings.version, value: appVersion)
                    Text(Strings.Settings.dataNotice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section(Strings.Settings.debugSection) {
                    LabeledContent(Strings.Settings.lastLookupSource, value: lastLookupSource)
                }
            }
            .navigationTitle(Strings.Settings.title)
        }
    }
}

#Preview {
    SettingsView()
}
