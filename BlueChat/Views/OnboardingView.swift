import SwiftUI

/// Erster Start: Anzeigenamen wählen und Bluetooth-Berechtigung anstoßen.
/// Bewusst minimal – keine Konto-Erstellung, keine E-Mail, kein Tracking
/// (Datenminimierung). Die Identität wird lokal erzeugt.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
                .symbolEffect(.variableColor.iterative, options: .repeating)

            Text("BlueChat")
                .font(.largeTitle.bold())
            Text("Offline-Messenger über Bluetooth.\nKein Internet. Kein Server. Keine Konten.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            TextField("Dein Anzeigename", text: $name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .padding(.horizontal, 40)

            Button {
                appState.completeOnboarding(name: name.trimmingCharacters(in: .whitespaces))
            } label: {
                Text("Loslegen")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 40)

            Text("Beim Tippen auf „Loslegen" fragt iOS die Bluetooth-Berechtigung ab.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .padding()
    }
}
