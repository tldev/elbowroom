import SwiftUI

/// Ask Kibi card. The guess renders as a dashed chip labeled `Kibi's guess`
/// with the mandatory hedge line; low confidence falls back to
/// `Not sure yet. Here's what's inside` plus the top children.
public struct AskKibiSheet: View {
    @Environment(AppModel.self) private var model
    let name: String
    let path: String
    let bytes: Int64
    let children: [String]

    @State private var guess: AskKibi.Guess?
    @State private var finished = false

    public init(name: String, path: String, bytes: Int64, children: [String]) {
        self.name = name
        self.path = path
        self.bytes = bytes
        self.children = children
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BSpace.l) {
            HStack(alignment: .top, spacing: BSpace.l) {
                Image(systemName: "sparkle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(BColor.inkSoft)
                    .frame(width: 36, height: 36)
                    .background(BColor.soil, in: RoundedRectangle(cornerRadius: BRadius.control))
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(BFont.title)
                        .foregroundStyle(BColor.ink)
                    HStack(spacing: 8) {
                        Text(ByteFormat.string(bytes))
                            .font(BFont.rounded(15, .semibold))
                            .foregroundStyle(BColor.inkSoft)
                        Text(path)
                            .font(BFont.path)
                            .foregroundStyle(BColor.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !finished {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(Copy.kibiThinking)
                        .font(BFont.body)
                        .foregroundStyle(BColor.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, BSpace.xl)
            } else if let guess {
                VStack(alignment: .leading, spacing: BSpace.m) {
                    Text(guess.text)
                        .font(BFont.body)
                        .foregroundStyle(BColor.ink)
                        .lineSpacing(3)
                    HStack(spacing: BSpace.m) {
                        if let tier = guess.tier {
                            TierChip(tier, guessed: true)
                        }
                        Text(Copy.kibiHedge)
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft)
                    }
                }
                .bCard()
            } else {
                // Model declined or low confidence.
                VStack(alignment: .leading, spacing: BSpace.s) {
                    Text(Copy.kibiUnsure)
                        .font(BFont.body.weight(.medium))
                        .foregroundStyle(BColor.ink)
                    ForEach(children.prefix(8), id: \.self) { child in
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                                .foregroundStyle(BColor.inkSoft)
                            Text(child)
                                .font(BFont.meta)
                                .foregroundStyle(BColor.inkSoft)
                        }
                    }
                }
                .bCard()
            }

            Spacer()
            HStack {
                Button(Copy.revealInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
                PrimaryButton(Copy.ok) { model.sheet = nil }
            }
        }
        .padding(BSpace.sheetPadding)
        .frame(width: 480, height: 380)
        .background(BColor.bg)
        .task {
            guess = await AskKibi.explain(folderName: name, childNames: children, bytes: bytes)
            finished = true
            Analytics.shared.log("ask_kibi", ["outcome": guess == nil ? "unsure" : "guess"])
        }
    }
}
