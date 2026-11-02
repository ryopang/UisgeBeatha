import SwiftUI

/// Shown instead of the app when the SwiftData store can't be opened.
/// Order of the offered actions is deliberate: retry (harmless), save a
/// copy of the data (harmless), then reset (destructive, confirmed).
struct ContainerRecoveryView: View {
    let errorDescription: String
    let onRetry: () -> Void
    let onReset: () -> Void

    @State private var confirmingReset = false

    private var storeFileURL: URL? {
        let url = AppContainer.storeURL
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Strings.Recovery.heading)
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(Strings.Recovery.explanation)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        Button(action: onRetry) {
                            Text(Strings.Recovery.retry)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)

                        if let storeFileURL {
                            ShareLink(item: storeFileURL) {
                                Label(Strings.Recovery.saveCopy, systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(role: .destructive) {
                            confirmingReset = true
                        } label: {
                            Text(Strings.Recovery.reset)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(errorDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle(Strings.App.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog(
            Strings.Recovery.resetConfirmTitle,
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button(Strings.Recovery.resetConfirmAction, role: .destructive, action: onReset)
            Button(Strings.Collection.cancel, role: .cancel) {}
        } message: {
            Text(Strings.Recovery.resetConfirmMessage)
        }
    }
}

#Preview {
    ContainerRecoveryView(errorDescription: "Example error", onRetry: {}, onReset: {})
}
