import SwiftUI
import SwiftData
import BlueChatCore

/// 1:1-Chatansicht. Die Nachrichtenliste kommt reaktiv aus SwiftData.
struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @StateObject var viewModel: ChatViewModel
    @Environment(\.modelContext) private var context

    @Query private var messages: [MessageRecord]

    init(viewModel: ChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        let key = viewModel.peerID.hex
        // Nur Nachrichten dieses Chats, chronologisch.
        _messages = Query(
            filter: #Predicate<MessageRecord> { $0.chat?.counterpartKey == key },
            sort: \.sentAt, order: .forward
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            composer
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    VerificationView(peerID: viewModel.peerID, peerName: viewModel.title)
                } label: { Image(systemName: "lock.shield") }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if viewModel.expiryEnabled {
                HStack {
                    Image(systemName: "timer")
                    Text("Verfällt nach \(Int(viewModel.expirySeconds))s")
                    Slider(value: $viewModel.expirySeconds, in: 10...3600, step: 10)
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            HStack(spacing: 8) {
                Button { viewModel.expiryEnabled.toggle() } label: {
                    Image(systemName: viewModel.expiryEnabled ? "timer.circle.fill" : "timer.circle")
                }
                TextField("Nachricht", text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred() // Haptic
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(viewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
        .background(.ultraThinMaterial)
    }
}

private struct MessageBubble: View {
    let message: MessageRecord

    var body: some View {
        HStack {
            if message.direction == .outgoing { Spacer(minLength: 40) }
            VStack(alignment: message.direction == .outgoing ? .trailing : .leading, spacing: 2) {
                if let text = message.text { Text(text) }
                if let data = message.imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 200).cornerRadius(8)
                }
                HStack(spacing: 4) {
                    Text(message.sentAt, style: .time).font(.caption2)
                    if message.direction == .outgoing { deliveryIcon }
                    if message.expiresAt != nil { Image(systemName: "timer").font(.caption2) }
                }
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(message.direction == .outgoing ? Color.blue.opacity(0.85) : Color.gray.opacity(0.2))
            .foregroundStyle(message.direction == .outgoing ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            if message.direction == .incoming { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder private var deliveryIcon: some View {
        switch message.deliveryState {
        case .queued:    Image(systemName: "clock")
        case .sent:      Image(systemName: "checkmark")
        case .delivered: Image(systemName: "checkmark.circle")
        case .read:      Image(systemName: "checkmark.circle.fill")
        case .failed:    Image(systemName: "exclamationmark.triangle")
        }
    }
}
