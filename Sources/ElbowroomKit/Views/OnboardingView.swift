import SwiftUI

/// Onboarding: six beats in a borderless 720×560 window, progress dots
/// bottom-center. The flow is the app's first minute; there is no skip.
public struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.onboarding {
                case .welcome: WelcomeBeat()
                case .privacy: PrivacyBeat()
                case .trashFirst: TrashBeat()
                case .grant: GrantBeat()
                case .scanning: ScanBeat()
                case .reveal: RevealBeat()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            dots
        }
        .frame(width: 720, height: 560)
        .background(BColor.bg)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(i <= model.onboarding.rawValue ? BColor.brand : BColor.ink.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.bottom, BSpace.l)
        .accessibilityLabel("Step \(model.onboarding.rawValue + 1) of 6")
    }
}

// MARK: - B1 Welcome

struct WelcomeBeat: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: BSpace.xl) {
            StrataMark()
                .frame(width: 64, height: 52)
                .padding(.bottom, BSpace.s)
            Text(Copy.b1Headline)
                .font(BFont.title)
                .foregroundStyle(BColor.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Text(Copy.b1Sub)
                .font(BFont.body)
                .foregroundStyle(BColor.inkSoft)
            PrimaryButton(Copy.b1Continue) {
                withAnimation(BMotion.standard) { model.onboarding = .privacy }
            }
        }
        .padding(BSpace.huge)
    }
}

// MARK: - B2 Privacy promise

struct PrivacyBeat: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: BSpace.xl) {
            ZStack {
                Circle()
                    .fill(BColor.soil)
                    .frame(width: 96, height: 96)
                Image(systemName: "lock.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(BColor.brand)
            }
            Text(Copy.b2Headline)
                .font(BFont.title)
                .foregroundStyle(BColor.ink)
            Text(Copy.b2Body)
                .font(BFont.body)
                .foregroundStyle(BColor.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 440)
            PrimaryButton(Copy.b1Continue) {
                withAnimation(BMotion.standard) { model.onboarding = .trashFirst }
            }
        }
        .padding(BSpace.huge)
    }
}

// MARK: - The Trash decision

/// The product's one safety default, decided with room to explain it:
/// reclaims are trash-first, and this beat owns that choice. Settings can
/// change it later; each plan can override one run.
struct TrashBeat: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var settings = model.settings
        VStack(spacing: BSpace.xl) {
            ZStack {
                Circle()
                    .fill(BColor.soil)
                    .frame(width: 96, height: 96)
                Image(systemName: "trash")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(BColor.brand)
            }
            Text(Copy.trashBeatHeadline)
                .font(BFont.title)
                .foregroundStyle(BColor.ink)
            Text(Copy.trashBeatBody)
                .font(BFont.body)
                .foregroundStyle(BColor.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 440)
            Toggle(Copy.keepInTrashLabel, isOn: $settings.keepInTrashDefault)
                .toggleStyle(.checkbox)
                .font(BFont.body)
                .foregroundStyle(BColor.ink)
            PrimaryButton(Copy.b1Continue) {
                withAnimation(BMotion.standard) { model.onboarding = .grant }
            }
        }
        .padding(BSpace.huge)
    }
}

// MARK: - B3 The Grant

/// Full Disk Access first: one switch covers every consent class the scan
/// would otherwise trip mid-dig. Fallback: the home folder, with each
/// consent dialog raised deliberately before the scan.
struct GrantBeat: View {
    @Environment(AppModel.self) private var model
    @State private var pulse = false

    var body: some View {
        VStack(spacing: BSpace.xl) {
            switch model.grantPath {
            case .fdaIntro: intro
            case .fdaWaiting: waiting
            case .guided: guided
            }
        }
        .padding(BSpace.huge)
        .onAppear { pulse = true }
        .task { model.grantBeatAppeared() }
        .animation(BMotion.standard, value: model.grantPath)
    }

    @ViewBuilder private var intro: some View {
        Text(Copy.b3Headline)
            .font(BFont.title)
            .foregroundStyle(BColor.ink)
        Text(Copy.b3Body)
            .font(BFont.body)
            .foregroundStyle(BColor.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)

        settingsMock(on: model.fdaGranted, pulsing: !model.fdaGranted)

        if model.fdaGranted {
            Text(Copy.b3AlreadyOn)
                .font(BFont.body)
                .foregroundStyle(BColor.ink)
            PrimaryButton(Copy.b3StartScan) { model.startScanFromGrant() }
        } else {
            PrimaryButton(Copy.fdaOpen) { model.beginFDAWait() }
        }
        fallbackLink
    }

    @ViewBuilder private var waiting: some View {
        Text(Copy.b3Headline)
            .font(BFont.title)
            .foregroundStyle(BColor.ink)

        settingsMock(on: true, pulsing: true)

        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(Copy.b3WaitTitle)
                .font(BFont.body)
                .foregroundStyle(BColor.ink)
        }
        Text(Copy.b3WaitNote)
            .font(BFont.meta)
            .foregroundStyle(BColor.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 400)
        HStack(spacing: BSpace.m) {
            Button(Copy.fdaOpen) { DiskAccess.openFullDiskSettings() }
                .buttonStyle(SecondaryButtonStyle())
            Button(Copy.b3Relaunch) { model.relaunchApp() }
                .buttonStyle(SecondaryButtonStyle())
        }
        fallbackLink
    }

    @ViewBuilder private var guided: some View {
        Text(Copy.b3GuidedTitle)
            .font(BFont.title)
            .foregroundStyle(BColor.ink)
        Text(Copy.b3GuidedBody)
            .font(BFont.body)
            .foregroundStyle(BColor.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)

        VStack(spacing: 0) {
            ForEach(Array(model.guidedZones.enumerated()), id: \.element.id) { i, zone in
                if i > 0 { Divider().padding(.horizontal, 12) }
                HStack(spacing: 10) {
                    zoneIcon(zone.status)
                        .frame(width: 18)
                    Text(Copy.b3Zone(zone.zone))
                        .font(BFont.body)
                        .foregroundStyle(zone.status == .denied ? BColor.inkSoft : BColor.ink)
                    Spacer()
                    if zone.status == .denied {
                        Text(Copy.b3ZoneSkipped)
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 340)
        .background(BColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BColor.line, lineWidth: 1))
        .animation(BMotion.light, value: model.guidedZones)

        Text(Copy.b3HomeNote)
            .font(BFont.meta)
            .foregroundStyle(BColor.inkSoft)
    }

    @ViewBuilder private func zoneIcon(_ status: GuidedZone.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle.dotted").foregroundStyle(BColor.inkSoft)
        case .asking:
            ProgressView().controlSize(.small)
        case .allowed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(BColor.brand)
        case .denied:
            Image(systemName: "minus.circle").foregroundStyle(BColor.inkSoft)
        }
    }

    private var fallbackLink: some View {
        Button(Copy.b3Fallback) { model.startGuidedHomeGrant() }
            .buttonStyle(.plain)
            .font(BFont.meta)
            .foregroundStyle(BColor.inkSoft)
    }

    /// A built (not recorded) looping mock of the Full Disk Access row, with
    /// Elbowroom's toggle as the live status: off and pulsing while the grant is
    /// pending, on once it lands.
    private func settingsMock(on: Bool, pulsing: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(BColor.inkSoft.opacity(0.4)).frame(width: 8, height: 8)
                Circle().fill(BColor.inkSoft.opacity(0.4)).frame(width: 8, height: 8)
                Circle().fill(BColor.inkSoft.opacity(0.4)).frame(width: 8, height: 8)
                Spacer()
            }
            .padding(8)
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(BColor.brand)
                Text(Copy.fdaTitle)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.ink)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(BColor.soil)
                    .frame(width: 22, height: 22)
                    .overlay(StrataMark().frame(width: 14, height: 11))
                Text("Elbowroom")
                    .font(BFont.meta)
                    .foregroundStyle(BColor.ink)
                Spacer()
                Capsule()
                    .fill(on ? BColor.brand : BColor.ink.opacity(0.18))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: on ? .trailing : .leading) {
                        // Surface, not white: the on-state capsule is
                        // near-white in dark mode.
                        Circle().fill(BColor.surface).frame(width: 16, height: 16).padding(2)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(BColor.brand.opacity(pulsing ? (pulse ? 0.20 : 0.08) : 0))
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
            )
            .padding(8)
        }
        .frame(width: 340)
        .background(BColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BColor.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - B4 First scan

struct ScanBeat: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            excavation
                .frame(maxHeight: .infinity)
            ticker
                .frame(height: 176)
            liveCounter
                .frame(height: 24)
        }
        .padding(BSpace.xl)
        .task {
            // Resuming after a relaunch mid-onboarding: the grant is saved,
            // the scan just needs starting.
            if !model.scanning && model.result == nil {
                model.startScan()
            }
        }
        .onKeyPress(.escape) {
            model.cancelScan()
            return .handled
        }
        // B4: Command-period cancels; the grant stays intact.
        .background {
            Button("") { model.cancelScan() }
                .keyboardShortcut(".", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var fraction: Double {
        guard model.scanning else { return 1 }
        let byItems = 1 - exp(-Double(model.scanItemsSeen) / 400_000)
        let byBytes = 1 - exp(-Double(model.scanBytesSeen) / 250_000_000_000)
        return min(0.985, 0.55 * byItems + 0.45 * byBytes)
    }

    private var excavation: some View {
        VStack(alignment: .leading, spacing: BSpace.l) {
            Spacer()
            ByteCounter(bytes: model.scanBytesSeen, size: 44)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BColor.soil)
                    Capsule()
                        .fill(BColor.ink.opacity(0.8))
                        .frame(width: max(4, geo.size.width * fraction))
                        .animation(.linear(duration: 0.5), value: fraction)
                }
            }
            .frame(height: 6)
            .onHover { hovering = $0 }
            .overlay(alignment: .trailing) {
                if hovering {
                    Text("\(Int(fraction * 100))%")
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                        .offset(y: -18)
                }
            }
            Spacer()
        }
        .accessibilityLabel("Scanning. \(model.scanItemsSeen) items seen.")
    }

    private var ticker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            ForEach(Array(model.tickerLines.enumerated()), id: \.element) { _, line in
                Text(line)
                    .font(BFont.body)
                    .foregroundStyle(BColor.ink)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, BSpace.l)
        .animation(BMotion.light, value: model.tickerLines)
    }

    /// The proof of life: numbers that never stop moving while the scan runs,
    /// so a long tail cannot read as a hang.
    private var liveCounter: some View {
        HStack(spacing: 6) {
            Text(Copy.itemCount(model.scanItemsSeen))
                .contentTransition(.numericText(value: Double(model.scanItemsSeen)))
            Text("·")
            Text(ByteFormat.string(model.scanBytesSeen))
                .contentTransition(.numericText(value: Double(model.scanBytesSeen)))
        }
        .font(BFont.rounded(12, .medium))
        .foregroundStyle(BColor.inkSoft)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.linear(duration: 0.3), value: model.scanItemsSeen)
        .accessibilityHidden(true)
    }
}


// MARK: - B5 The Reveal

struct RevealBeat: View {
    @Environment(AppModel.self) private var model
    @State private var rolled: Int64 = 0

    var body: some View {
        VStack(spacing: BSpace.xl) {
            Spacer()
            hero
            Text(model.isModest ? Copy.b5ModestSub : Copy.b5Sub)
                .font(BFont.body)
                .foregroundStyle(BColor.inkSoft)
            DiskStrip()
                .frame(maxWidth: 560)
                .zIndex(1)  // the hover legend card hangs over the doors below
            // With FDA on, what stays denied is system-protected; there is
            // nothing left to expand, so the chip would only mislead.
            if !model.result!.deniedPaths.isEmpty && !model.fdaGranted {
                Button {
                    model.expandAccessFromReveal()
                } label: {
                    Label(Copy.b5PartialChip, systemImage: "eye.slash")
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                }
                .buttonStyle(.plain)
            }
            doors
            Spacer()
        }
        .padding(BSpace.huge)
        .task {
            // M1: hero digits roll 0 → N over 1.2 s ease-out.
            withAnimation(.easeOut(duration: 1.2)) { rolled = model.headroomBytes }
        }
    }

    private var hero: some View {
        VStack(spacing: BSpace.s) {
            if model.isCrisis {
                Text(Copy.b5Crisis)
                    .font(BFont.subtitle)
                    .foregroundStyle(BColor.ink)
            } else {
                Text(Copy.b5HeroPrefix)
                    .font(BFont.subtitle)
                    .foregroundStyle(BColor.inkSoft)
            }
            ByteCounter(bytes: rolled, size: 88)
            if !model.isCrisis {
                Text(Copy.b5HeroSuffix)
                    .font(BFont.subtitle)
                    .foregroundStyle(BColor.inkSoft)
            }
        }
    }

    private var doors: some View {
        HStack(alignment: .top, spacing: BSpace.l) {
            if model.isCrisis {
                let plan = model.crisisPlan()
                let total = plan.reduce(Int64(0)) { $0 + $1.bytes }
                DoorCard(
                    icon: "arrow.down.circle.fill",
                    title: Copy.b5CrisisDoor(ByteFormat.string(total)),
                    line: Copy.doorCrisisLine
                ) {
                    model.enterMain(.den)
                    model.openReclaimPlan(items: plan)
                }
            } else {
                DoorCard(icon: "arrow.down.circle.fill", title: Copy.b5DoorReclaim, line: Copy.doorReclaimLine) {
                    model.enterMain(.den)
                    model.openReclaimPlan(items: model.crisisPlan())
                }
            }
            DoorCard(icon: "map.fill", title: Copy.b5DoorExplain, line: Copy.doorExplainLine) {
                model.enterMain(.crossSection)
            }
        }
    }
}

struct DoorCard: View {
    let icon: String
    let title: String
    let line: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: BSpace.s) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(BColor.brand)
                Text(title)
                    .font(BFont.body.weight(.semibold))
                    .foregroundStyle(BColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
                    .multilineTextAlignment(.leading)
            }
            .padding(BSpace.cardPadding)
            .frame(minWidth: 150, maxWidth: 200, minHeight: 122, alignment: .topLeading)
            .background(BColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: BRadius.card)
                    .strokeBorder(hover ? BColor.brand.opacity(0.6) : BColor.line, lineWidth: 1)
            )
            .offset(y: hover ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(BMotion.light) { hover = h } }
    }
}

// MARK: - Buttons

public struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(BFont.body.weight(.semibold))
                .foregroundStyle(BColor.onBrand)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, BSpace.xl)
                .frame(height: 44)
                .background(BColor.brand, in: RoundedRectangle(cornerRadius: BRadius.control))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        // Styled labels vanish from the AX tree on macOS; name the button
        // explicitly or VoiceOver reads nothing.
        .accessibilityLabel(title)
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BFont.body)
            .foregroundStyle(BColor.ink)
            .padding(.horizontal, BSpace.l)
            .frame(height: 44)
            .background(BColor.surface, in: RoundedRectangle(cornerRadius: BRadius.control))
            .overlay(RoundedRectangle(cornerRadius: BRadius.control).strokeBorder(BColor.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
