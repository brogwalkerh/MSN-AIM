import SwiftUI
import CarDashCore

enum PhoneSection {
    static var descriptor: SectionDescriptor {
        SectionDescriptor(
            id: .phone,
            title: "Phone",
            systemImage: "phone.fill",
            blurb: "Favourites you can dial with one tap.",
            capabilities: [.singleton]
        ) { context in
            AnyView(PhonePaneView(context: context))
        }
    }
}

struct PhonePaneView: View {
    let context: PaneContext

    @Environment(\.dashTheme) private var theme
    @State private var picking = false
    @State private var isManaging = false
    @State private var problem: String?

    private var favourites: FavouritesStore { context.services.favourites }
    private var isDriving: Bool { context.services.location.isDriving }

    var body: some View {
        VStack(spacing: 6) {
            header

            if favourites.isEmpty {
                empty
            } else {
                grid
            }

            if let problem {
                Text(problem)
                    .font(DashFont.label(11))
                    .foregroundStyle(theme.destructive)
                    .lineLimit(2)
            }
        }
        .panePadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $picking) {
            ContactPicker { picked in
                favourites.add(contentsOf: picked)
                Haptics.edit()
            }
        }
        // Managing is a parked-car activity, and leaving the tile in a state where a tap
        // deletes someone is not something to carry into moving traffic.
        .onChange(of: isDriving) { _, driving in
            if driving { isManaging = false }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(isManaging ? "Remove a favourite" : "Favourites")
                .font(DashFont.label(12))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            // Both controls are parked-car controls. While moving the tile is nothing but
            // large buttons that dial.
            if !isDriving {
                if !favourites.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { isManaging.toggle() }
                    } label: {
                        Image(systemName: isManaging ? "checkmark" : "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(isManaging ? theme.accent : theme.tile, in: Circle())
                            .foregroundStyle(isManaging ? theme.background : theme.primaryText)
                    }
                    .accessibilityLabel(isManaging ? "Done removing" : "Remove favourites")
                }

                Button {
                    picking = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(theme.tile, in: Circle())
                        .foregroundStyle(theme.primaryText)
                }
                .disabled(favourites.isFull)
                .opacity(favourites.isFull ? 0.35 : 1)
                .accessibilityLabel("Add a favourite")
            }
        }
    }

    // Fewer and larger while moving: a target you can hit without aiming is the entire
    // argument for this tile existing rather than opening the Phone app.
    private var columns: [GridItem] {
        let minimum: CGFloat = isDriving ? 96 : 74
        return [GridItem(.adaptive(minimum: minimum), spacing: 6)]
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(favourites.entries) { favourite in
                    Button {
                        tap(favourite)
                    } label: {
                        FavouriteTile(
                            favourite: favourite,
                            isManaging: isManaging,
                            compact: context.environment.isCompact
                        )
                    }
                    .accessibilityLabel(
                        isManaging
                            ? "Remove \(favourite.displayName)"
                            : "Call \(favourite.displayName)"
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("No favourites yet.")
                .font(DashFont.label(12))
                .foregroundStyle(theme.secondaryText)
            // Said here because it is genuinely unusual and worth knowing: this button does
            // not produce a permission prompt.
            Text("CarDash never reads your contacts — you pick who appears here.")
                .font(DashFont.label(10))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Add someone") { picking = true }
                .font(DashFont.label())
                .foregroundStyle(theme.background)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(theme.accent, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tap(_ favourite: Favourite) {
        if isManaging {
            favourites.remove(favourite.id)
            Haptics.edit()
            if favourites.isEmpty { isManaging = false }
            return
        }

        guard PhoneDialer.dial(favourite.phoneNumber) else {
            // An iPad has no telephony, and a number saved as nonsense cannot be dialled.
            // Either way the button should say why rather than appear broken.
            problem = "This device can't place calls."
            return
        }
        problem = nil
    }
}

/// One face in the grid. Initials rather than a photo, because a photo would need the
/// Contacts authorization this app deliberately does not ask for.
struct FavouriteTile: View {
    let favourite: Favourite
    var isManaging = false
    var compact = false

    @Environment(\.dashTheme) private var theme

    private var diameter: CGFloat { compact ? 34 : 44 }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isManaging ? theme.destructive.opacity(0.22) : theme.accent.opacity(0.18))
                    .frame(width: diameter, height: diameter)

                if isManaging {
                    Image(systemName: "minus")
                        .font(.system(size: diameter * 0.4, weight: .bold))
                        .foregroundStyle(theme.destructive)
                } else {
                    Text(favourite.initials)
                        .font(DashFont.value(diameter * 0.38))
                        .foregroundStyle(theme.accent)
                }
            }

            if !compact {
                Text(favourite.displayName)
                    .font(DashFont.label(11))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 46 : 74)
        .background(theme.tile.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
