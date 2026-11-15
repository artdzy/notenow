import SwiftUI

/// Sayfaların küçük resimleri ve kâğıt seçimi.
struct PagesSheet: View {
    @ObservedObject var doc: NotebookDocument
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sayfalar").font(Theme.serif(34)).foregroundStyle(Theme.text)
                Text("\(doc.notebook.title) · \(doc.pages.count) sayfa")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("Tamam") { dismiss() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Theme.ink, in: Capsule())
                    .buttonStyle(.plain)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(Array(doc.pages.enumerated()), id: \.element.id) { i, page in
                        Button {
                            model.flipper?.jump(to: i)
                            dismiss()
                        } label: {
                            PageThumb(doc: doc, page: page, number: i + 1, current: i == model.currentIndex)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button {
                                doc.insertPage(at: i + 1)
                            } label: { Label("Sonrasına sayfa ekle", systemImage: "plus.square") }
                            if doc.pages.count > 1 {
                                Button(role: .destructive) {
                                    doc.deletePage(at: i)
                                } label: { Label("Sayfayı sil", systemImage: "trash") }
                            }
                        }
                    }
                    Button {
                        doc.insertPage(at: doc.pages.count)
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(hex: 0xCFC6B3), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                                .aspectRatio(doc.pageSize.width / doc.pageSize.height, contentMode: .fit)
                                .overlay(Image(systemName: "plus").font(.system(size: 22)).foregroundStyle(Theme.muted))
                            Text("Sayfa ekle").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(4)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("BU SAYFANIN KÂĞIDI")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 12) {
                    ForEach(PaperType.allCases) { p in
                        let current = doc.pages.indices.contains(model.currentIndex) ? doc.pages[model.currentIndex].paper : .lined
                        PaperChoice(paper: p, selected: current == p) {
                            doc.setPaper(p, forPageAt: model.currentIndex)
                        }
                    }
                    Text("Yeni sayfalar da bu kâğıtla açılır. Basılı tutarak sayfa ekleyip silebilirsin.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: 240, alignment: .leading)
                        .padding(.leading, 8)
                }
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
        .padding(28)
        .background(Theme.paper)
        .presentationDetents([.large])
    }
}

struct PageThumb: View {
    @ObservedObject var doc: NotebookDocument
    let page: PageMeta
    let number: Int
    let current: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(uiImage: doc.thumbnail(for: page, width: 360))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.ink, lineWidth: current ? 2.5 : 0))
            Text("\(number)")
                .font(.system(size: 12, weight: current ? .semibold : .regular))
                .foregroundStyle(current ? Theme.ink : Theme.muted)
        }
    }
}
