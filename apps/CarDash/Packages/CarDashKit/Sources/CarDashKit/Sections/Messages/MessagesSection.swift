import MessageUI
import SwiftUI
import CarDashCore

enum MessagesSection {
    static var descriptor: SectionDescriptor {
        SectionDescriptor(
            id: .messages,
            title: "Messages",
            systemImage: "message.fill",
            blurb: "Prefilled replies. iOS still requires you to tap send.",
            capabilities: [.singleton]
        ) { context in
            AnyView(MessagesPaneView(context: context))
        }
    }
}

/// Sending a canned message to a favourite, in two taps.
///
/// What this tile cannot do, and why it looks the way it does: **iOS exposes no way to read
/// messages.** No third-party app can list your conversations, show an unread count, or read a
/// message aloud — there is no API, no entitlement and no permission that grants it. So this is
/// outbound only, and it says so rather than presenting an empty inbox that never fills.
///
/// It also cannot send without a tap. The composer arrives with everything filled in and the
/// send button belongs to the user. That is a deliberate iOS restriction, and pretending
/// otherwise would mean a driver believing a message went when it did not.
struct MessagesPaneView: View {
    let context: PaneContext

    @Environment(\.dashTheme) private var theme
    @State private var recipient: Favourite?
    @State private var composing: Draft?
    @State private var sentConfirmation: String?

    /// Identifiable so it can drive a sheet directly, which keeps the recipient and the body
    /// from ever being out of step with what is on screen.
    private struct Draft: Identifiable {
        let id = UUID()
        let recipient: Favourite
        let body: String
    }

    private var favourites: FavouritesStore { context.services.favourites }
    private var isDriving: Bool { context.services.location.isDriving }

    var body: some View {
        VStack(spacing: 6) {
            header

            if favourites.isEmpty {
                empty
            } else if let recipient {
                replies(to: recipient)
            } else {
                people
            }
        }
        .panePadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $composing) { draft in
            if MessageComposer.canSend {
                MessageComposer(
                    recipients: [draft.recipient.phoneNumber],
                    body: draft.body
                ) { result in
                    composing = nil
                    if result == .sent {
                        sentConfirmation = "Sent to \(draft.recipient.displayName)."
                        recipient = nil
                        Haptics.edit()
                    }
                }
                .ignoresSafeArea()
            } else {
                // A simulator, or an iPad with no messaging account. Saying so beats a blank
                // sheet the user has to dismiss to discover nothing happened.
                cannotSend
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let recipient {
                Button {
                    self.recipient = nil
                } label: {
                    Label(recipient.displayName, systemImage: "chevron.left")
                        .font(DashFont.label(12))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                }
                .accessibilityLabel("Choose someone else")
            } else {
                Text("Quick message")
                    .font(DashFont.label(12))
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 0)

            if let sentConfirmation {
                Text(sentConfirmation)
                    .font(DashFont.label(10))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .task(id: sentConfirmation) {
                        try? await Task.sleep(for: .seconds(3))
                        self.sentConfirmation = nil
                    }
            }
        }
    }

    // MARK: - Step one: who

    private var people: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: isDriving ? 96 : 74), spacing: 6)],
                spacing: 6
            ) {
                ForEach(favourites.entries) { favourite in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { recipient = favourite }
                    } label: {
                        FavouriteTile(favourite: favourite, compact: context.environment.isCompact)
                    }
                    .accessibilityLabel("Message \(favourite.displayName)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Step two: what

    private func replies(to favourite: Favourite) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(QuickReplies.all) { reply in
                    Button {
                        compose(reply, to: favourite)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: reply.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(reply.title)
                                    .font(DashFont.label(14))
                                    .foregroundStyle(theme.primaryText)
                                // The rendered text, not the template — so the arrival time
                                // is visible before the composer opens rather than being a
                                // surprise in the message field.
                                Text(body(for: reply))
                                    .font(DashFont.label(10))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: DashMetrics.minimumHitTarget)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.tile.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Text("iOS requires you to tap send.")
                    .font(DashFont.label(10))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.top, 2)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("Add someone in the Phone tile to message them here.")
                .font(DashFont.label(12))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            Text("CarDash can't read your messages — no app can. This tile only sends.")
                .font(DashFont.label(10))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cannotSend: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 28))
            Text("This device can't send messages.")
                .font(DashFont.label(14))
            Button("Close") { composing = nil }
                .font(DashFont.label())
        }
        .padding(24)
    }

    // MARK: - Composing

    /// The live arrival time, when a route is running. This is the one thing the tile knows
    /// that the Messages app does not.
    private var replyContext: QuickReplyContext {
        QuickReplyContext(
            estimatedTimeRemaining: context.services.route.guidance?.estimatedTimeRemaining,
            now: Date()
        )
    }

    private func body(for reply: QuickReply) -> String {
        QuickReplies.render(reply, context: replyContext)
    }

    private func compose(_ reply: QuickReply, to favourite: Favourite) {
        composing = Draft(recipient: favourite, body: body(for: reply))
    }
}
