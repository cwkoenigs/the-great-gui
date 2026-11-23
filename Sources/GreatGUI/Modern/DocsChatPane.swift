import SwiftUI
import TerminalDesign

struct DocsChatPane: View {
    let palette: Palette
    let docs: DocsLibrary

    var body: some View {
        @Bindable var chat = docs.chat
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Provider", selection: $chat.provider) {
                    ForEach(DocsChat.Provider.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(chat.asking)
                if docs.currentSource != nil {
                    Text("Using the page above")
                        .foregroundStyle(palette.muted)
                }
                Spacer()
                Button("New Chat") { chat.reset() }
                    .secondaryButton(palette)
                    .disabled(chat.asking || chat.messages.isEmpty)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if chat.messages.isEmpty {
                            Text("Ask about canon standards or team skills. Your question and relevant excerpts go to the selected provider.")
                                .foregroundStyle(palette.muted)
                        }
                        ForEach(chat.messages) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(message.role == "user" ? "You" : message.provider.title)
                                    .sectionLabel(palette)
                                Text((try? AttributedString(markdown: message.text,
                                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text))
                                    .textSelection(.enabled)
                                    .environment(\.openURL, OpenURLAction { _ in .discarded })
                                ForEach(message.sources) { source in
                                    Button(source.title) { docs.openSource(source.path) }.rowAction(palette)
                                }
                            }
                        }
                        if chat.asking {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Waiting for \(chat.provider.title)…")
                            }
                        }
                        if let note = chat.note { NoteLine(note: note, palette: palette) }
                        Color.clear.frame(height: 1).id("chat-end")
                    }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: chat.messages.count) { scroll.scrollTo("chat-end", anchor: .bottom) }
                .onChange(of: chat.asking) { scroll.scrollTo("chat-end", anchor: .bottom) }
            }
            HStack {
                TextField("Ask about canon…", text: $chat.draft)
                    .textFieldStyle(.plain)
                    .fieldBox(palette)
                    .onSubmit { chat.submit(currentSource: docs.currentSource) }
                Button("Send") { chat.submit(currentSource: docs.currentSource) }
                    .primaryButton(palette)
                    .disabled(chat.asking || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(24)
        }
        .font(.callout)
    }
}
