import DictationCore
import SwiftUI

/// Settings → Transcription word list: add, review, and delete words and corrections.
struct LexiconSection: View {
    @ObservedObject var library: LexiconLibrary

    var body: some View {
        let now = Date()
        let active = library.promptTerms(now: now)
        SettingsGroup(footnote: "Saved only on this Mac (lexicon.json beside history). Up to \(Lexicon.maxPromptTerms) recently heard words go into the speech prompt; words you stop saying rest until you say them again. Corrections run locally after transcription. Add from any History item, too.") {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Word list").font(AppType.rowTitle)
                    Text("Names and terms to prefer, and fixes for words the model keeps mishearing.")
                        .font(AppType.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
                .padding(.bottom, 10)
                LexiconEntryForm(library: library)
                    .padding(.bottom, 12)
                if let error = library.errorMessage {
                    Text(error)
                        .font(AppType.detail)
                        .foregroundStyle(AppPalette.problem)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)
                }
            }

            if !library.terms.isEmpty {
                RowDivider()
                subheading("Words", count: library.terms.count)
                ForEach(sortedTerms(now: now)) { term in
                    entryRow(title: term.text,
                             caption: termCaption(term, inPrompt: active.contains(term.text)),
                             removeLabel: "Delete \(term.text)") { library.removeTerm(id: term.id) }
                }
            }
            if !library.replacements.isEmpty {
                RowDivider()
                subheading("Corrections", count: library.replacements.count)
                ForEach(Array(library.replacements.reversed())) { rule in
                    entryRow(title: "\(rule.mishear)  →  \(rule.correct)",
                             caption: hitsCaption(rule.hits, lastUsed: rule.lastUsed, fallback: "Not applied yet"),
                             removeLabel: "Delete correction for \(rule.mishear)") {
                        library.removeReplacement(id: rule.id)
                    }
                }
            }
        }
    }

    private func sortedTerms(now: Date) -> [LexiconTerm] {
        library.terms.sorted { Lexicon.score($0, now: now) > Lexicon.score($1, now: now) }
    }

    private func subheading(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count)")
            .font(AppType.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func entryRow(title: String, caption: String, removeLabel: String,
                          remove: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppType.body).textSelection(.enabled)
                Text(caption).font(AppType.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            QuietIconButton(symbol: "trash", label: removeLabel, action: remove)
        }
        .padding(.vertical, 6)
    }

    private func termCaption(_ term: LexiconTerm, inPrompt: Bool) -> String {
        let state = inPrompt ? "In prompt" : "Resting · not heard lately"
        return term.hits > 0 ? "\(state) · heard \(term.hits)×" : state
    }

    private func hitsCaption(_ hits: Int, lastUsed: Date?, fallback: String) -> String {
        guard hits > 0 else { return fallback }
        let when = lastUsed.map { " · last \($0.formatted(.relative(presentation: .named)))" } ?? ""
        return "Applied \(hits)×\(when)"
    }
}
