import SwiftUI

/// Small pill showing a bottle's sealed/open/finished status.
struct StatusPillView: View {
    let status: BottleStatus

    var body: some View {
        Text(Strings.Status.label(for: status))
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(.secondary)
            .background(.quaternary, in: Capsule())
    }
}

#Preview {
    HStack {
        ForEach(BottleStatus.allCases, id: \.self) { status in
            StatusPillView(status: status)
        }
    }
    .padding()
}
