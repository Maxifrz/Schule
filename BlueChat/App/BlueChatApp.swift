import SwiftUI
import SwiftData
import BlueChatCore

@main
struct BlueChatApp: App {
    /// Gemeinsamer SwiftData-Container. Datei-Schutzklasse wird per
    /// Entitlement/Default auf „complete until first unlock" gesetzt, sodass
    /// die Datenbank verschlüsselt-at-rest liegt.
    let modelContainer: ModelContainer

    @StateObject private var appState: AppState

    init() {
        do {
            let container = try ModelContainer(
                for: IdentityRecord.self, PeerRecord.self, SessionRecord.self, ChatRecord.self, MessageRecord.self
            )
            self.modelContainer = container
            _appState = StateObject(wrappedValue: AppState(context: container.mainContext))
        } catch {
            fatalError("SwiftData-Container konnte nicht erstellt werden: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .modelContainer(modelContainer)
                .preferredColorScheme(nil) // respektiert System-Dark-Mode
        }
    }
}

/// Hält die App-weiten Singletons (Engine) und steuert den Onboarding-Status.
@MainActor
final class AppState: ObservableObject {
    @Published var hasOnboarded: Bool
    @Published var displayName: String
    let engine: MessengerEngine

    init(context: ModelContext) {
        let identity = (try? KeychainStore.loadOrCreateIdentity()) ?? CryptoService.generateIdentity()
        let store = MessageStore(context: context)
        let name = UserDefaults.standard.string(forKey: "displayName") ?? ""
        self.displayName = name
        self.hasOnboarded = !name.isEmpty
        self.engine = MessengerEngine(identity: identity, displayName: name.isEmpty ? "Anonym" : name, store: store)
    }

    func completeOnboarding(name: String) {
        displayName = name
        engine.displayName = name
        UserDefaults.standard.set(name, forKey: "displayName")
        hasOnboarded = true
        engine.start()
    }

    func startIfNeeded() {
        if hasOnboarded { engine.start() }
    }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.hasOnboarded {
                PeerListView()
                    .onAppear { appState.startIfNeeded() }
            } else {
                OnboardingView()
            }
        }
    }
}
