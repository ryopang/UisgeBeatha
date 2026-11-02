import Observation
import SwiftUI

/// Editors that can be opened from inside a bottle's detail.
///
/// Detail is rebuilt when the iPhone Duo folds or unfolds (the layout
/// changes), and a sheet owned by a rebuilt view is dismissed with it,
/// taking a half-typed note or form with it. Presenting editors from a
/// router held *above* the size-class switch keeps them, and their drafts,
/// alive across the change.
enum EditorRoute: Identifiable {
    case newBottle
    case editBottle(Bottle)
    case newNote(Bottle)
    case editNote(Bottle, TastingNote)

    var id: String {
        switch self {
        case .newBottle: "new-bottle"
        case .editBottle(let bottle): "edit-bottle-\(bottle.id)"
        case .newNote(let bottle): "new-note-\(bottle.id)"
        case .editNote(_, let note): "edit-note-\(note.id)"
        }
    }
}

@MainActor @Observable
final class EditorRouter {
    var route: EditorRoute?

    func present(_ route: EditorRoute) {
        self.route = route
    }
}

extension EnvironmentValues {
    @Entry var editorRouter: EditorRouter?
}

/// Installs a router in the environment and presents its editors as sheets.
/// Apply once per presentation boundary: the collection root, and any sheet
/// that shows a bottle detail (a sheet can't present over the sheet that
/// contains it).
private struct EditorRouting: ViewModifier {
    @State private var router = EditorRouter()

    func body(content: Content) -> some View {
        content
            .environment(\.editorRouter, router)
            .sheet(item: Bindable(router).route) { route in
                switch route {
                case .newBottle:
                    BottleFormView(bottle: nil)
                case .editBottle(let bottle):
                    BottleFormView(bottle: bottle)
                case .newNote(let bottle):
                    TastingNoteEditorView(bottle: bottle, note: nil)
                case .editNote(let bottle, let note):
                    TastingNoteEditorView(bottle: bottle, note: note)
                }
            }
    }
}

extension View {
    func editorRouting() -> some View {
        modifier(EditorRouting())
    }
}
