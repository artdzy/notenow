import Foundation

/// Kitaplık: defterlerin listesi.
///
/// Her defter kendi klasöründedir (`notebook.json`, `pages.json`, çizimler, görseller).
/// iCloud açıksa klasörler kullanıcının iCloud Drive'ındaki uygulama alanında durur ve
/// aynı Apple hesabındaki tüm cihazlarda görünür; değilse yalnızca bu cihazdadır.
final class NotebookStore: ObservableObject {
    @Published private(set) var notebooks: [Notebook] = []
    /// Klasör belirlenip defterler okunana kadar false.
    @Published private(set) var ready = false
    @Published private(set) var isCloud = false

    private(set) var root: URL
    private let localRoot: URL
    private let io = DispatchQueue(label: "notenow.library", qos: .utility)
    private let cloud = CloudSync()
    private var reloadWork: DispatchWorkItem?
    private var cloudObserver: NSObjectProtocol?
    private static let createdFirstKey = "didCreateFirstNotebook"

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        localRoot = docs.appendingPathComponent("Notebooks", isDirectory: true)
        root = localRoot
        FileIO.makeFolder(localRoot)
        cloudObserver = NotificationCenter.default.addObserver(forName: CloudSync.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleReload()
        }
        DispatchQueue.global(qos: .userInitiated).async { self.setUp() }
    }

    func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func notebookURL(_ id: UUID) -> URL {
        folder(for: id).appendingPathComponent("notebook.json")
    }

    // MARK: Açılış

    private func setUp() {
        migrateLegacyLibrary()
        var useRoot = localRoot
        var cloudOn = false
        if let cloudRoot = CloudSync.notebooksFolder() {
            moveLocalNotebooks(to: cloudRoot)
            useRoot = cloudRoot
            cloudOn = true
        }
        let list = Self.scan(useRoot)
        DispatchQueue.main.async {
            self.root = useRoot
            self.isCloud = cloudOn
            self.notebooks = list
            if list.isEmpty && !UserDefaults.standard.bool(forKey: Self.createdFirstKey) {
                self.create(title: "İlk defterim", cover: .navy, paper: .lined, color: .cream)
            }
            UserDefaults.standard.set(true, forKey: Self.createdFirstKey)
            self.ready = true
            if cloudOn { self.cloud.start() }
            // Henüz okunmamış el yazılarını arka planda metne çevir.
            SearchIndex.shared.reindexAll(self.notebooks.map { self.folder(for: $0.id) })
        }
    }

    /// 0.1'deki tek `library.json` dosyasını defter başına `notebook.json`'a böler:
    /// iki cihaz aynı anda farklı defter açtığında biri ötekini silmesin diye.
    private func migrateLegacyLibrary() {
        let url = localRoot.appendingPathComponent("library.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Notebook].self, from: data) else { return }
        for nb in list {
            let dir = localRoot.appendingPathComponent(nb.id.uuidString, isDirectory: true)
            guard FileManager.default.fileExists(atPath: dir.path),
                  let out = try? JSONEncoder().encode(nb) else { continue }
            try? out.write(to: dir.appendingPathComponent("notebook.json"), options: .atomic)
        }
        try? FileManager.default.removeItem(at: url)
        if !list.isEmpty { UserDefaults.standard.set(true, forKey: Self.createdFirstKey) }
    }

    /// Bu cihazdaki defterleri iCloud'a taşır (iCloud yeni açıldıysa ya da ilk kez).
    private func moveLocalNotebooks(to cloudRoot: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: localRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for src in items where (try? src.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let dest = cloudRoot.appendingPathComponent(src.lastPathComponent, isDirectory: true)
            if fm.fileExists(atPath: dest.path) { continue }
            try? fm.setUbiquitous(true, itemAt: src, destinationURL: dest)
        }
    }

    /// Klasördeki defterleri okur. Henüz inmemiş olanlar indirilmeye başlar, sonra gelir.
    private static func scan(_ root: URL) -> [Notebook] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var list: [Notebook] = []
        for dir in items where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let file = dir.appendingPathComponent("notebook.json")
            guard fm.fileExists(atPath: file.path) else {
                try? fm.startDownloadingUbiquitousItem(at: file)
                continue
            }
            if let data = FileIO.read(file), let nb = try? JSONDecoder().decode(Notebook.self, from: data) {
                list.append(nb)
            }
        }
        return list.sorted { $0.modified > $1.modified }
    }

    /// Başka bir cihazda değişiklik olunca kitaplığı yeniden okur.
    private func scheduleReload() {
        guard ready else { return }
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let root = self.root
            self.io.async {
                let list = Self.scan(root)
                DispatchQueue.main.async {
                    if list != self.notebooks { self.notebooks = list }
                    SearchIndex.shared.reindexAll(list.map { self.folder(for: $0.id) })
                }
            }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: Yazma

    private func persist(_ nb: Notebook) {
        let url = notebookURL(nb.id)
        io.async {
            guard let data = try? JSONEncoder().encode(nb) else { return }
            FileIO.write(data, to: url)
        }
    }

    @discardableResult
    func create(title: String, cover: CoverColor, paper: PaperType, color: PaperColor) -> Notebook {
        let now = Date()
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nb = Notebook(
            id: UUID(), title: clean.isEmpty ? "Adsız defter" : clean, cover: cover, paper: paper,
            orientation: .portrait, created: now, modified: now, pageCount: 1, lastPage: 0,
            paperColor: color
        )
        let dir = folder(for: nb.id)
        FileIO.makeFolder(dir.appendingPathComponent("images"))
        let first = [PageMeta(id: UUID(), paper: paper, images: [])]
        if let data = try? JSONEncoder().encode(first) {
            FileIO.write(data, to: dir.appendingPathComponent("pages.json"))
        }
        if let data = try? JSONEncoder().encode(nb) {
            FileIO.write(data, to: notebookURL(nb.id))
        }
        notebooks.insert(nb, at: 0)
        return nb
    }

    func update(_ nb: Notebook) {
        guard let i = notebooks.firstIndex(where: { $0.id == nb.id }) else { return }
        notebooks[i] = nb
        notebooks.sort { $0.modified > $1.modified }
        persist(nb)
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

    func search(_ query: String) -> [SearchHit] {
        SearchIndex.shared.search(query, in: notebooks, folder: folder(for:))
    }

    /// Arama sonucundan: defteri o sayfada aç.
    func notebook(_ nb: Notebook, openingAt page: Int) -> Notebook {
        var copy = nb
        copy.lastPage = page
        update(copy)
        return copy
    }

    func setPaperColor(_ nb: Notebook, _ c: PaperColor) {
        var copy = nb
        copy.paperColor = c
        update(copy)
    }

    func delete(_ nb: Notebook) {
        let dir = folder(for: nb.id)
        notebooks.removeAll { $0.id == nb.id }
        io.async { FileIO.remove(dir) }
    }
}
