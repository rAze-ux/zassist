import SwiftUI

/// Чат внутри проекта: история из Supabase + ответы модели GLM (Z.AI).
struct ChatView: View {
    let project: Project

    @EnvironmentObject private var state: AppState
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var streamingText: String?
    @State private var sending = false
    @State private var errorText: String?
    @State private var loading = true
    @State private var showClear = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if let errorText {
                errorBanner(errorText)
            }
            inputBar
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showClear = true
                    } label: {
                        Label("Очистить историю", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Удалить все сообщения этого проекта?", isPresented: $showClear, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await clearHistory() } }
            Button("Отмена", role: .cancel) {}
        }
        .task { await loadHistory() }
    }

    // MARK: - Список сообщений

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if loading {
                        ProgressView()
                            .padding(.top, 40)
                    }
                    ForEach(messages) { message in
                        Bubble(text: message.content, mine: message.role == "user")
                            .id(message.id)
                    }
                    if let streaming = streamingText {
                        Bubble(text: streaming.isEmpty ? "…" : streaming, mine: false)
                            .id("streaming")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _ in scrollToBottom(proxy) }
            .onChange(of: streamingText) { _ in scrollToBottom(proxy) }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Сообщение…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit { Task { await send() } }
                .focused($focused)
                .disabled(sending)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.footnote)
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.08))
    }

    // MARK: - Действия

    @MainActor
    private func loadHistory() async {
        if messages.isEmpty { loading = true }
        do {
            let session = try await state.ensureValidSession()
            messages = try await state.supabase.fetchMessages(token: session.accessToken, projectId: project.id)
        } catch {
            errorText = AppState.describe(error)
        }
        loading = false
    }

    @MainActor
    private func clearHistory() async {
        do {
            let session = try await state.ensureValidSession()
            try await state.supabase.deleteMessages(token: session.accessToken, projectId: project.id)
            messages = []
        } catch {
            errorText = AppState.describe(error)
        }
    }

    @MainActor
    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        input = ""
        errorText = nil
        sending = true
        defer { sending = false }

        // Показываем сообщение пользователя сразу
        let localId = UUID()
        messages.append(ChatMessage(id: localId, projectId: project.id, role: "user", content: text, createdAt: Date()))

        do {
            // Сохраняем его в Supabase
            let session = try await state.ensureValidSession()
            if let saved = try? await state.supabase.insertMessage(
                token: session.accessToken,
                userId: session.userId,
                projectId: project.id,
                role: "user",
                content: text
            ) {
                messages.removeAll { $0.id == localId }
                messages.append(saved)
            }

            // Спрашиваем модель
            guard let ai = state.makeAI() else { throw AppError.noAIKey }
            var history: [AIMessage] = [
                AIMessage(role: "system", content: "Ты — полезный ИИ-ассистент внутри приложения. Отвечай на языке пользователя, по умолчанию по-русски.")
            ]
            history += messages.suffix(20).map { AIMessage(role: $0.role, content: $0.content) }

            streamingText = ""
            var full = ""
            do {
                for try await chunk in ai.stream(messages: history, model: state.model) {
                    full += chunk
                    streamingText = full
                }
            } catch {
                streamingText = nil
                if full.isEmpty { throw error }
                errorText = "Соединение прервалось — ответ сохранён частично"
            }
            streamingText = nil

            if !full.isEmpty {
                if let saved = try? await state.supabase.insertMessage(
                    token: session.accessToken,
                    userId: session.userId,
                    projectId: project.id,
                    role: "assistant",
                    content: full
                ) {
                    messages.append(saved)
                } else {
                    messages.append(ChatMessage(id: UUID(), projectId: project.id, role: "assistant", content: full, createdAt: Date()))
                }
            }
        } catch {
            errorText = AppState.describe(error)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if streamingText != nil {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Облачко сообщения

private struct Bubble: View {
    let text: String
    let mine: Bool

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(mine ? Color.blue : Color(uiColor: .secondarySystemBackground))
                .foregroundStyle(mine ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            if !mine { Spacer(minLength: 40) }
        }
    }
}
