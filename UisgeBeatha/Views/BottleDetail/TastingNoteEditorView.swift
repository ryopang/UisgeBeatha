import OSLog
import SwiftData
import SwiftUI

/// Tasting note editor (PRD F7). Pass nil to create a new note.
struct TastingNoteEditorView: View {
    let bottle: Bottle
    let note: TastingNote?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var nose: String
    @State private var palate: String
    @State private var finish: String
    @State private var conclusion: String
    @State private var showingWheel = false

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "TastingNote")

    init(bottle: Bottle, note: TastingNote?) {
        self.bottle = bottle
        self.note = note
        _date = State(initialValue: note?.date ?? .now)
        _nose = State(initialValue: note?.nose ?? "")
        _palate = State(initialValue: note?.palate ?? "")
        _finish = State(initialValue: note?.finish ?? "")
        _conclusion = State(initialValue: note?.conclusion ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(Strings.NoteEditor.date, selection: $date)
                noteField(Strings.NoteEditor.nose, text: $nose)
                noteField(Strings.NoteEditor.palate, text: $palate)
                noteField(Strings.NoteEditor.finish, text: $finish)
                noteField(Strings.NoteEditor.conclusion, text: $conclusion)
            }
            .navigationTitle(Strings.NoteEditor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Form.cancel, role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingWheel = true
                    } label: {
                        Label(Strings.NoteEditor.wheelButton, systemImage: "circle.grid.3x3.circle")
                            .labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Form.save) { save() }
                        .disabled(isEmpty)
                }
            }
            .sheet(isPresented: $showingWheel) {
                TastingWheelSheet()
            }
        }
    }

    /// A note with nothing written in any field is just an empty card on
    /// the detail screen.
    private var isEmpty: Bool {
        [nose, palate, finish, conclusion].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func noteField(_ label: String, text: Binding<String>) -> some View {
        Section(label) {
            TextField(label, text: text, axis: .vertical)
                .lineLimit(3...8)
                .labelsHidden()
        }
    }

    private func save() {
        if let note {
            note.date = date
            note.nose = nose
            note.palate = palate
            note.finish = finish
            note.conclusion = conclusion
        } else {
            let newNote = TastingNote(
                date: date, nose: nose, palate: palate,
                finish: finish, conclusion: conclusion
            )
            modelContext.insert(newNote)
            newNote.bottle = bottle
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            Self.logger.error("Failed to save tasting note: \(error)")
        }
    }
}
