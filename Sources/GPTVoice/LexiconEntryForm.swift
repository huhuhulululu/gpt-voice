import DictationCore
import SwiftUI

enum LexiconEntryKind: String, CaseIterable, Identifiable {
    case term
    case correction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .term: return "Word"
        case .correction: return "Correction"
        }
    }
}

/// Adds one word or one `heard => should be` correction. The user always confirms with Add;
/// nothing is learned from other apps.
struct LexiconEntryForm: View {
    @ObservedObject var library: LexiconLibrary
    var onAdded: (() -> Void)?

    @State private var kind: LexiconEntryKind
    @State private var term: String
    @State private var mishear: String
    @State private var correct = ""
    @State private var result: (text: String, ok: Bool)?

    init(library: LexiconLibrary, kind: LexiconEntryKind = .term, seed: String = "",
         onAdded: (() -> Void)? = nil) {
        self.library = library
        self.onAdded = onAdded
        let seed = Self.seedText(seed)
        _kind = State(initialValue: kind)
        _term = State(initialValue: seed)
        _mishear = State(initialValue: seed)
    }

    /// Only short transcripts prefill; longer ones are better copied from in part.
    static func seedText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= Lexicon.maxTermLength && !trimmed.contains(where: \.isNewline) ? trimmed : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSegmented(label: "Entry type", options: LexiconEntryKind.allCases, title: \.title,
                         selection: $kind)
            switch kind {
            case .term:
                AppTextField(label: "Word", text: $term, placeholder: "Goice, 声笔, Kubernetes")
                    .onSubmit(add)
            case .correction:
                HStack(spacing: 8) {
                    AppTextField(label: "Heard as", text: $mishear, placeholder: "Heard as: go ice")
                        .onSubmit(add)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    AppTextField(label: "Should be", text: $correct, placeholder: "Should be: Goice")
                        .onSubmit(add)
                }
            }
            HStack(spacing: 8) {
                Text(result?.text ?? hint)
                    .font(AppType.detail)
                    .foregroundStyle(result.map { $0.ok ? AppPalette.success : AppPalette.problem } ?? .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Add", action: add)
                    .buttonStyle(AppButtonStyle(kind: .secondary, small: true))
                    .disabled(!canAdd)
            }
        }
        .onChange(of: kind) { _ in result = nil }
    }

    private var hint: String {
        kind == .term
            ? "Helps the speech model spell names and jargon."
            : "Fixes this text on this Mac after each transcription."
    }

    private var canAdd: Bool {
        switch kind {
        case .term: return !term.trimmingCharacters(in: .whitespaces).isEmpty
        case .correction:
            return !mishear.trimmingCharacters(in: .whitespaces).isEmpty
                && !correct.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func add() {
        guard canAdd else { return }
        let change: Lexicon.Change
        switch kind {
        case .term: change = library.addTerm(term)
        case .correction: change = library.addReplacement(mishear: mishear, correct: correct)
        }
        switch change {
        case .added, .updated:
            result = (change == .added ? "Added. Used from the next dictation." : "Already saved. Updated.", true)
            term = ""
            mishear = ""
            correct = ""
            onAdded?()
        case .invalid:
            result = (kind == .term
                      ? "Use one line of up to \(Lexicon.maxTermLength) characters."
                      : "Both sides must differ and fit in \(Lexicon.maxTermLength) characters.", false)
        }
    }
}
