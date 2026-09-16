import SwiftUI

/// The brand mark: three disk strata, drawn crisp. Reads at 16 pt.
public struct StrataMark: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bar = h * 0.2
            VStack(alignment: .leading, spacing: h * 0.13) {
                RoundedRectangle(cornerRadius: bar / 2).fill(BColor.ink).frame(width: w, height: bar)
                RoundedRectangle(cornerRadius: bar / 2).fill(BColor.ink.opacity(0.55)).frame(width: w * 0.72, height: bar)
                HStack(spacing: w * 0.1) {
                    RoundedRectangle(cornerRadius: bar / 2).fill(BColor.ink.opacity(0.3)).frame(width: w * 0.38, height: bar)
                    RoundedRectangle(cornerRadius: bar / 2).fill(BColor.tierRegen).frame(width: bar, height: bar)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
    }
}

/// Segmented control: a surface capsule with a sliding ink-tinted pill.
/// Replaces the system control so the header reads as one family.
public struct SegmentedTabs: View {
    @Binding var selection: MainView
    @Namespace private var pill

    public init(selection: Binding<MainView>) {
        self._selection = selection
    }

    private let tabs: [MainView] = [.den, .ledger, .crossSection]

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(BMotion.standard) { selection = tab }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == tab ? BColor.ink : BColor.inkSoft)
                        .padding(.horizontal, 18)
                        .frame(height: 28)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(BColor.surface)
                                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(BColor.soil, in: Capsule())
    }
}
