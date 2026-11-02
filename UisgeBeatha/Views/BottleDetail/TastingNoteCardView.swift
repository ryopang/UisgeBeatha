import SwiftUI

/// One tasting note as a card, newest-first in the detail view.
struct TastingNoteCardView: View {
    let note: TastingNote
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var fields: [(label: String, text: String)] {
        [
            (Strings.NoteEditor.nose, note.nose),
            (Strings.NoteEditor.palate, note.palate),
            (Strings.NoteEditor.finish, note.finish),
            (Strings.NoteEditor.conclusion, note.conclusion),
        ].filter { !$0.text.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(note.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button(Strings.Detail.edit, systemImage: "pencil", action: onEdit)
                    Button(Strings.Detail.delete, systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // 44pt: the HIG / PRD minimum touch target. The
                        // glyph stays small; only the hit area grows.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Strings.Detail.noteActions)
            }
            ForEach(fields, id: \.label) { field in
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(field.text)
                        .font(.callout)
                }
            }
        }
        .cardBackground()
    }
}
