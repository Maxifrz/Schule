import SwiftUI
import BlueChatCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPanicConfirm = false

    var body: some View {
        Form {
            Section("Identität") {
                LabeledContent("Name", value: appState.displayName)
                LabeledContent("Meine PeerID", value: appState.engine.identity.peerID.hex)
                    .font(.system(.body, design: .monospaced))
            }

            Section("Funk") {
                LabeledContent("Bluetooth", value: appState.engine.bluetoothReady ? "Bereit" : "Nicht bereit")
                LabeledContent("Max. Hops (TTL)", value: "7")
            }

            Section {
                Toggle("Empfangsbestätigungen senden", isOn: .constant(true)).disabled(true)
                Toggle("Lokale Benachrichtigungen", isOn: .constant(true)).disabled(true)
            } header: {
                Text("Datenschutz")
            } footer: {
                Text("BlueChat speichert keine Daten in der Cloud. Alle Inhalte bleiben verschlüsselt auf diesem Gerät.")
            }

            Section {
                Button(role: .destructive) {
                    showPanicConfirm = true
                } label: {
                    Label("Panik-Modus: Alles löschen", systemImage: "trash.fill")
                }
            } footer: {
                Text("Löscht sofort und unwiderruflich alle Chats, Kontakte, Sessions und Schlüssel von diesem Gerät.")
            }
        }
        .navigationTitle("Einstellungen")
        .confirmationDialog("Wirklich ALLE Daten löschen?", isPresented: $showPanicConfirm, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) {
                appState.engine.panicWipe()
                appState.hasOnboarded = false
                UserDefaults.standard.removeObject(forKey: "displayName")
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dieser Vorgang kann nicht rückgängig gemacht werden.")
        }
    }
}
