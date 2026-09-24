import SwiftUI
import AppKit

/// Ask Nino, live: answers come from OpenClaw (`openclaw agent --local`) through
/// the Nino Voice engine, which owns the Right-Command key and voice-into-the-box.
/// "Respond" modes (Assistant, Answers Live) show their answers here too.
/// The id stays `nino.search` (ids never change after ship); this was the AI Search stub.
struct AskNinoModule: NinoModule {
    let id = "nino.search"
    let displayName = "Ask Nino"
    let summary = "Ask anything. Nino answers with hands on this Mac (OpenClaw)."
    let systemImage = "sparkle.magnifyingglass"
    let isStub = false

    var panel: AnyView { AnyView(AskNinoPanel()) }
}

struct AskNinoPanel: View {
    @ObservedObject private var link = NinoVoiceLink.shared
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var ask: NinoVoiceState.Ask? { link.state?.ask }

    var body: some View {
        NinoCard {
            stageRow
            if !allMessages.isEmpty {
                messageList(allMessages)
            } else if link.stage == .none && link.state?.recording != "recording" {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(NinoTheme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let status = ask?.status, status != "Thinking", status != "Sending", !(status == "Done" && ask?.messages.isEmpty == false) {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(ask?.failed != nil ? NinoTheme.gold : NinoTheme.sub)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                TextField("", text: $draft, prompt: Text(placeholder).foregroundStyle(NinoTheme.dim))
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(NinoTheme.text)
                    .focused($fieldFocused)
                    .onSubmit(send)
                    .onExitCommand { link.closeAsk() }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(NinoTheme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(link.state == nil || ask?.busy == true)

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(canSend ? NinoTheme.bg : NinoTheme.dim)
                        .frame(width: 24, height: 24)
                        .background(canSend ? NinoTheme.gold : NinoTheme.bg)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)

                if ask?.visible == true {
                    Button { link.closeAsk() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NinoTheme.sub)
                            .frame(width: 24, height: 24)
                            .background(NinoTheme.bg)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close (Esc)")
                }
            }
        }
        .onAppear {
            // Typing needs the notch window to take the keyboard; only this tab allows it.
            BoringNotchSkyLightWindow.ninoAllowsKeyFocus = true
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onDisappear {
            if !NinoVoiceLink.holdsNotchOpen { link.releaseKeyFocus() }
        }
        .onChange(of: ask?.draft ?? "") { _, spoken in
            // Spoken words go out on their own (Screen Control or Ask Nino); only show
            // them in the field while nothing has been sent yet.
            if link.stage == .none || link.stage == .listening { draft = spoken }
        }
        .onChange(of: link.stage) { _, stage in
            // Once spoken words are on their way, the box is not a place to send them again.
            if stage == .thinking { draft = "" }
            if case .done = stage { draft = "" }
        }
        .onChange(of: ask?.visible ?? false) { _, visible in
            if visible { DispatchQueue.main.async { fieldFocused = true } }
        }
    }

    /// Answers made in Nino Notch first, then the full agent's conversation.
    private var allMessages: [NinoVoiceState.Message] {
        link.localMessages + (ask?.messages ?? [])
    }

    @ViewBuilder
    private var stageRow: some View {
        if link.stage == .listening || link.state?.recording == "recording" {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(NinoTheme.gold).frame(width: 8, height: 8).padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listening…").font(.subheadline.weight(.semibold)).foregroundStyle(NinoTheme.gold)
                    Text((link.state?.partial ?? "").isEmpty ? "Say it, then press Right ⌘." : (link.state?.partial ?? ""))
                        .font(.callout).foregroundStyle(NinoTheme.text).lineLimit(2).truncationMode(.head)
                }
                Spacer(minLength: 0)
                NinoVoiceMeter(level: link.level, bars: 10, height: 14)
            }
        } else if link.stage == .thinking || ask?.busy == true {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(NinoTheme.gold)
                Text("Thinking…").font(.subheadline.weight(.semibold)).foregroundStyle(NinoTheme.sub)
            }
        } else if case .done(let line) = link.stage {
            HStack(spacing: 8) {
                Image(systemName: line.hasPrefix("Couldn't") ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(NinoTheme.gold)
                Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(NinoTheme.text).lineLimit(2)
            }
        }
    }

    private var hint: String {
        guard let state = link.state else { return "Starting the Nino Voice engine…" }
        var parts = ["Ask Nino anything."]
        if !state.askKey.isEmpty { parts.append("\(state.askKey) opens this from any app.") }
        if !state.recordKey.isEmpty { parts.append("Hold \(state.recordKey) to say it.") }
        return parts.joined(separator: " ")
    }

    private var placeholder: String {
        if link.state?.recording == "recording" {
            let partial = link.state?.partial ?? ""
            return partial.isEmpty ? "Listening… press Right ⌘ to send" : partial
        }
        return "Ask Nino…"
    }

    private var canSend: Bool {
        link.state != nil && ask?.busy != true && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        draft = ""
        link.routeAsk(text)
    }

    private func messageList(_ messages: [NinoVoiceState.Message]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(messages) { message in
                        AskNinoBubble(message: message).id(message.id)
                    }
                }
            }
            .onAppear { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
        }
    }
}

private struct AskNinoBubble: View {
    let message: NinoVoiceState.Message
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            if !isUser {
                HStack(spacing: 6) {
                    Text("NINO")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .kerning(0.6)
                        .foregroundStyle(NinoTheme.gold)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NinoTheme.dim)
                    .help("Copy")
                }
            }
            // ponytail: inline markdown only (bold, code, links); block lists render as plain lines.
            Text(Self.markdown(message.text))
                .font(.caption)
                .foregroundStyle(isUser ? NinoTheme.text : NinoTheme.sub)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isUser ? NinoTheme.bg : NinoTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isUser ? Color.clear : NinoTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
