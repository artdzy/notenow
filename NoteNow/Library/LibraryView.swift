import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: NotebookStore
    @State private var opened: Notebook?
    @State private var showNew = false
    @State private var renaming: Notebook?
    @State private var renameText = ""
    @State private var deleting: Notebook?
    @State private var query = ""
    @State private var indexVersion = 0

    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 210), spacing: 36, alignment: .top)]

    var body: some View {
        ZStack {
            Theme.desk.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        results
                    } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                        ForEach(store.notebooks) { nb in
                            Button { opened = nb } label: { NotebookTile(notebook: nb) }
                                .buttonStyle(PressableStyle())
                                .contextMenu { menu(for: nb) }
                        }
                        Button { showNew = true } label: { NewNotebookTile() }
                            .buttonStyle(PressableStyle())
                    }
                    }
                }
                .padding(.horizontal, 56)
                .padding(.top, 36)
                .padding(.bottom, 60)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SearchIndex.didChange)) { _ in indexVersion += 1 }
        .fullScreenCover(item: $opened) { nb in
            EditorView(notebook: nb, store: store)
        }
        .sheet(isPresented: $showNew) {
            NewNotebookSheet { title, cover, paper, color in
                let nb = store.create(title: title, cover: cover, paper: paper, color: color)
                showNew = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { opened = nb }
            }
        }
        .alert("Defteri yeniden adlandır", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Defter adı", text: $renameText)
            Button("Kaydet") { if let nb = renaming { store.rename(nb, to: renameText) } }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog(
            "Bu defter ve içindeki tüm sayfalar silinecek. Geri alınamaz.",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Defteri sil", role: .destructive) { if let nb = deleting { store.delete(nb) } }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR"))))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Text("Defterlerim")
                    .font(Theme.serif(50))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            searchField
            Button { showNew = true } label: {
                Label("Yeni defter", systemImage: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .foregroundStyle(Theme.paper)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Notlarda ara", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aramayı temizle")
            }
        }
        .font(.system(size: 15))
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(width: 280, height: 44)
        .background(Theme.paper, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
    }

    /// El yazısı arama sonuçları: defter, sayfa ve yazının geçtiği yer.
    private var results: some View {
        let _ = indexVersion
        let hits = store.search(query)
        return VStack(alignment: .leading, spacing: 12) {
            Text(hits.isEmpty ? "Sonuç yok" : "\(hits.count) sonuç")
                .font(.system(size: 13, weight: .semibold)).tracking(0.6)
                .foregroundStyle(Theme.muted)
            if hits.isEmpty {
                Text("El yazın birkaç saniye içinde aranabilir hâle gelir. Yeni yazdıysan biraz sonra tekrar dene.")
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
            }
            ForEach(hits) { hit in
                Button {
                    let nb = hit.pageIndex.map { store.notebook(hit.notebook, openingAt: $0) } ?? hit.notebook
                    opened = nb
                } label: {
                    HStack(alignment: .top, spacing: 16) {
                        RoundedRectangle(cornerRadius: 4).fill(hit.notebook.cover.color)
                            .frame(width: 34, height: 46)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(hit.notebook.title).font(Theme.serif(19)).foregroundStyle(Theme.text)
                                if let p = hit.pageIndex {
                                    Text("· sayfa \(p + 1)").font(.system(size: 14)).foregroundStyle(Theme.muted)
                                }
                            }
                            if hit.pageIndex != nil {
                                (Text(hit.before) + Text(hit.match).bold().foregroundColor(Theme.ink) + Text(hit.after))
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(Theme.muted).padding(.top, 4)
                    }
                    .padding(16)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    @ViewBuilder
    private func menu(for nb: Notebook) -> some View {
        Button { renameText = nb.title; renaming = nb } label: { Label("Yeniden adlandır", systemImage: "pencil") }
        Menu {
            ForEach(CoverColor.allCases) { c in
                Button(c.title) { store.setCover(nb, c) }
            }
        } label: { Label("Kapak rengi", systemImage: "paintpalette") }
        Menu {
            ForEach(PaperColor.allCases) { c in
                Button { store.setPaperColor(nb, c) } label: {
                    if nb.tint == c { Label(c.title, systemImage: "checkmark") } else { Text(c.title) }
                }
            }
        } label: { Label("Kâğıt rengi", systemImage: "doc") }
        Divider()
        Button(role: .destructive) { deleting = nb } label: { Label("Sil", systemImage: "trash") }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct NotebookTile: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NotebookCover(title: notebook.title, cover: notebook.cover)
            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(notebook.pageCount) sayfa · \(Self.relative(notebook.modified))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    static func relative(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "bugün" }
        if cal.isDateInYesterday(date) { return "dün" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}

struct NotebookCover: View {
    let title: String
    let cover: CoverColor

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4,
                                           bottomTrailingRadius: 12, topTrailingRadius: 12)
        ZStack(alignment: .topLeading) {
            shape.fill(cover.color)
            HStack(spacing: 0) {
                Rectangle().fill(.black.opacity(0.18)).frame(width: 6)
                Spacer()
                Rectangle().fill(Color(hex: 0x2B2622)).frame(width: 8)
                Spacer().frame(width: 22)
            }
            Text(title)
                .font(Theme.serif(19))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 3))
                .padding(.leading, 22)
                .padding(.trailing, 46)
                .padding(.top, 36)
        }
        .clipShape(shape)
        .aspectRatio(0.74, contentMode: .fit)
        .shadow(color: Color(hex: 0x281E0A).opacity(0.10), radius: 1, y: 1)
        .shadow(color: Color(hex: 0x281E0A).opacity(0.16), radius: 14, y: 12)
    }
}

struct NewNotebookTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12)
                .strokeBorder(Color(hex: 0xBDB4A2), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .aspectRatio(0.74, contentMode: .fit)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 26, weight: .light))
                        Text("Yeni defter").font(.system(size: 14))
                    }
                    .foregroundStyle(Theme.muted)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("Boş defter").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                Text("Kapak ve kâğıt seç").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
    }
}
