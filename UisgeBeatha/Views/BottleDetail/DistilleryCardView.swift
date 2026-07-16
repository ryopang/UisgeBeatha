import SwiftUI

/// Distillery info card (PRD F6): Wikipedia summary plus founded/owner
/// from seed data. Offline or unknown distillery degrades to seed facts
/// only — never an error banner. Hidden entirely when nothing is known.
struct DistilleryCardView: View {
    let distilleryName: String

    @Environment(\.distilleryStore) private var distilleryStore
    @Environment(\.wikipedia) private var wikipedia

    @State private var summary: WikipediaSummary?
    @State private var showingSafari = false

    private var seed: Distillery? {
        distilleryStore.exactMatch(distilleryName) ?? distilleryStore.bestMatch(for: distilleryName)
    }

    private var wikipediaURL: URL? {
        summary?.pageURL.flatMap(URL.init(string:))
    }

    var body: some View {
        if seed != nil || summary != nil {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.Distillery.cardTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(seed?.name ?? distilleryName)
                        .font(.headline)
                }

                if let seed {
                    HStack(spacing: 20) {
                        seedFact(Strings.Distillery.founded, String(seed.founded))
                        seedFact(Strings.Distillery.owner, seed.owner)
                    }
                }

                if let summary {
                    HStack(alignment: .top, spacing: 12) {
                        if let thumbnail = summary.thumbnailURL, let url = URL(string: thumbnail) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.clear
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inline))
                            .accessibilityHidden(true)
                        }
                        Text(summary.extract)
                            .font(.callout)
                            .lineLimit(8)
                    }
                    if wikipediaURL != nil {
                        Button(Strings.Distillery.readMore, systemImage: "safari") {
                            showingSafari = true
                        }
                        .font(.subheadline)
                    }
                }
            }
            .cardBackground()
            .task(id: distilleryName) {
                summary = await wikipedia.summary(forTitles: titleCandidates)
            }
            .sheet(isPresented: $showingSafari) {
                if let url = wikipediaURL {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
        }
    }

    /// Seed title first; unknown distilleries try the common patterns (PRD F6).
    private var titleCandidates: [String] {
        if let seed {
            return [seed.wikipediaTitle]
        }
        let base = distilleryName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        guard !base.isEmpty else { return [] }
        return ["\(base)_distillery", base]
    }

    private func seedFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
        }
        .accessibilityElement(children: .combine)
    }
}
