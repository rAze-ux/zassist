import SwiftUI

/// Первый экран: решает, что показывать — настройку, вход или основное приложение.
struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if !state.ready {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Загрузка…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !state.isConfigured {
                SetupView()
            } else if state.session == nil {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .task { await state.restore() }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            ProjectsView()
                .tabItem { Label("Проекты", systemImage: "folder") }
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}
