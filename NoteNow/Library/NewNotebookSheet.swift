import SwiftUI

struct NewNotebookSheet: View {
    var onCreate: (String, CoverColor, PaperType, PageOrientation) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var cover: CoverColor = .navy
    @State private var paper: PaperType = .lined
    @State private var orientation: PageOrientation = .portrait
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Button("Vazgeç") { dismiss() }
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("Yeni defter").font(Theme.serif(26)).foregroundStyle(Theme.text)
                Spacer()
                Button("Oluştur") { onCreate(title, cover, paper, orientation) }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }

            HStack(alignment: .top, spacing: 28) {
                NotebookCover(title: title.isEmpty ? "Adsız defter" : title, cover: cover)
                    .frame(width: 150)

                VStack(alignment: .leading, spacing: 22) {
                    section("AD") {
                        TextField("Örn. Toplantı notları", text: $title)
                            .font(.system(size: 17))
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
                            .focused($titleFocused)
                            .submitLabel(.done)
                    }
                    section("KAPAK") {
                        HStack(spacing: 12) {
                            ForEach(CoverColor.allCases) { c in
                                Button { cover = c } label: {
                                    Circle().fill(c.color).frame(width: 34, height: 34)
                                        .overlay(Circle().stroke(Theme.paper, lineWidth: cover == c ? 3 : 0).padding(2))
                                        .overlay(Circle().stroke(c.color, lineWidth: cover == c ? 2 : 0).padding(-2))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(c.title)
                            }
                        }
                    }
                }
            }

            section("KÂĞIT") {
                HStack(spacing: 12) {
                    ForEach(PaperType.allCases) { p in
                        PaperChoice(paper: p, selected: paper == p) { paper = p }
                    }
                }
            }

            section("SAYFA YÖNÜ") {
                Picker("Sayfa yönü", selection: $orientation) {
                    ForEach(PageOrientation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
        .padding(28)
        .background(Theme.paper)
        .presentationDetents([.large])
        .onAppear { titleFocused = true }
    }

    private func section<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.system(size: 12, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.muted)
            content()
        }
    }
}

struct PaperChoice: View {
    let paper: PaperType
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                PaperSwatch(paper: paper)
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(paper.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
            }
            .padding(10)
            .frame(width: 128)
            .background(selected ? Theme.soft : .clear, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Theme.ink : Theme.hairline, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Kâğıt dokusunun küçük önizlemesi.
struct PaperSwatch: View {
    let paper: PaperType
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.card))
            let rule = Color(hex: 0xE3DCCB)
            switch paper {
            case .lined:
                var y: CGFloat = 12
                while y < size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(rule)); y += 12 }
            case .grid:
                var y: CGFloat = 0
                while y < size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(rule)); y += 12 }
                var x: CGFloat = 0
                while x < size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(rule)); x += 12 }
            case .dots:
                var y: CGFloat = 6
                while y < size.height {
                    var x: CGFloat = 6
                    while x < size.width { ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(Color(hex: 0xC9C0AD))); x += 12 }
                    y += 12
                }
            case .blank:
                break
            }
        }
    }
}
