import OSLog
import SwiftData
import SwiftUI

/// Tasting note editor (PRD F7). Pass nil to create a new note.
struct TastingNoteEditorView: View {
    let bottle: Bottle
    let note: TastingNote?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tastingSuggester) private var suggester

    enum Field: Hashable {
        case nose, palate, finish, conclusion
    }

    @State private var date: Date
    @State private var nose: String
    @State private var palate: String
    @State private var finish: String
    @State private var conclusion: String
    @State private var showingWheel = false
    @FocusState private var focusedField: Field?
    /// Presenting the wheel sheet resigns focus, so the field the person
    /// was typing in is remembered separately; a tapped word goes there.
    @State private var lastField: Field = .nose
    @State private var suggestions: [String] = []
    @State private var isSuggesting = false
    @State private var hasSuggested = false

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
                noteField(Strings.NoteEditor.nose, text: $nose, field: .nose)
                noteField(Strings.NoteEditor.palate, text: $palate, field: .palate)
                noteField(Strings.NoteEditor.finish, text: $finish, field: .finish)
                noteField(Strings.NoteEditor.conclusion, text: $conclusion, field: .conclusion)
                if suggester.isAvailable {
                    suggestionsSection
                }
            }
            .onChange(of: focusedField) { _, field in
                if let field { lastField = field }
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
                TastingWheelSheet(onSelect: { insert($0) })
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

    private func noteField(_ label: String, text: Binding<String>, field: Field) -> some View {
        Section(label) {
            TextField(label, text: text, axis: .vertical)
                .lineLimit(3...8)
                .labelsHidden()
                .focused($focusedField, equals: field)
        }
    }

    // MARK: - Words

    /// Suggestions only: the model proposes wheel words, and nothing is
    /// written until the person taps one.
    private var suggestionsSection: some View {
        Section {
            Button {
                Task { await suggest() }
            } label: {
                if isSuggesting {
                    ProgressView()
                } else {
                    Label(Strings.NoteEditor.suggestWords, systemImage: "text.badge.plus")
                }
            }
            .disabled(isSuggesting || writtenText.isEmpty)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(suggestions, id: \.self) { word in
                            Button(word) { insert(word) }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                        }
                    }
                }
            } else if hasSuggested && !isSuggesting {
                Text(Strings.NoteEditor.suggestNone)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var writtenText: String {
        [nose, palate, finish, conclusion]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func suggest() async {
        isSuggesting = true
        suggestions = await suggester.suggestions(for: writtenText)
        hasSuggested = true
        isSuggesting = false
    }

    /// Adds a tapped word to the field the person was last writing in.
    private func insert(_ word: String) {
        switch lastField {
        case .nose: nose = TastingText.inserting(word, into: nose)
        case .palate: palate = TastingText.inserting(word, into: palate)
        case .finish: finish = TastingText.inserting(word, into: finish)
        case .conclusion: conclusion = TastingText.inserting(word, into: conclusion)
        }
        // A word just used shouldn't be offered again.
        suggestions.removeAll { $0.lowercased() == word.lowercased() }
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
