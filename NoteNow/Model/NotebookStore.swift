import Foundation

/// Kitaplık: defterlerin listesi. Documents/Notebooks/library.json içinde durur,
/// her defterin sayfaları kendi klasöründedir.
final class NotebookStore: ObservableObject {
    @Published private(set) var notebooks: [Notebook] = []

    let root: URL
    private var libraryURL: URL { root.appendingPathComponent("library.json") }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Notebooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
        if notebooks.isEmpty && !FileManager.default.fileExists(atPath: libraryURL.path) {
            create(title: "İlk defterim", cover: .navy, paper: .lined, orientation: .landscape)
        }
    }

    func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL),
              let list = try? JSONDecoder().decode([Notebook].self, from: data) else { return }
        notebooks = list.sorted { $0.modified > $1.modified }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(notebooks) else { return }
        try? data.write(to: libraryURL, options: .atomic)
    }

    @discardableResult
    func create(title: String, cover: CoverColor, paper: PaperType, orientation: PageOrientation) -> Notebook {
        let now = Date()
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nb = Notebook(
            id: UUID(), title: clean.isEmpty ? "Adsız defter" : clean, cover: cover, paper: paper,
            orientation: orientation, created: now, modified: now, pageCount: 1, lastPage: 0
        )
        let dir = folder(for: nb.id)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("images"), withIntermediateDirectories: true)
        let first = [PageMeta(id: UUID(), paper: paper, images: [])]
        if let data = try? JSONEncoder().encode(first) {
            try? data.write(to: dir.appendingPathComponent("pages.json"), options: .atomic)
        }
        notebooks.insert(nb, at: 0)
        persist()
        return nb
    }

    func update(_ nb: Notebook) {
        guard let i = notebooks.firstIndex(where: { $0.id == nb.id }) else { return }
        notebooks[i] = nb
        notebooks.sort { $0.modified > $1.modified }
        persist()
    }

    func rename(_ nb: Notebook, to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var copy = nb
        copy.title = clean
        update(copy)
    }

    func setCover(_ nb: Notebook, _ cover: CoverColor) {
        var copy = nb
        copy.cover = cover
        update(copy)
    }

    func delete(_ nb: Notebook) {
        try? FileManager.default.removeItem(at: folder(for: nb.id))
        notebooks.removeAll { $0.id == nb.id }
        persist()
    }
}
