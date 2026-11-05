import SwiftUI

/// Список проектов (чатов), синхронизируемых через Supabase.
struct ProjectsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showNew = false
    @State private var newTitle = ""
    @State private var renaming: Project?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if state.projects.isEmpty {
                    if state.loadingProjects {
                        ProgressView()
                    } else {
                        emptyState
                    }
                } else {
                    projectList
                }
            }
            .navigationTitle("Проекты")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newTitle = ""
                        showNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await state.loadProjects() }
            .task { await state.loadProjects() }
            .alert("Новый проект", isPresented: $showNew) {
                TextField("Название", text: $newTitle)
                Button("Создать") { Task { await state.createProject(title: newTitle) } }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Переименовать", isPresented: renameShown) {
                TextField("Название", text: $renameText)
                Button("Сохранить") {
                    if let project = renaming {
                        Task { await state.renameProject(project, title: renameText) }
                    }
                    renaming = nil
                }
                Button("Отмена", role: .cancel) { renaming = nil }
            }
            .alert("Ошибка", isPresented: errorShown) {
                Button("Понятно", role: .cancel) { state.lastError = nil }
            } message: {
                Text(state.lastError ?? "")
            }
        }
    }

    private var projectList: some View {
        List {
            ForEach(state.projects) { project in
                NavigationLink {
                    ChatView(project: project)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title)
                            .font(.headline)
                        Text(project.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await state.deleteProject(project) }
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                    Button {
                        renameText = project.title
                        renaming = project
                    } label: {
                        Label("Переименовать", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Пока нет проектов")
                .font(.headline)
            Text("Нажмите «+», чтобы создать первый чат — он будет виден на всех ваших устройствах.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var renameShown: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { state.lastError != nil }, set: { if !$0 { state.lastError = nil } })
    }
}
