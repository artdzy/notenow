import PencilKit
import UIKit

/// Açık bir defter: sayfalar, mürekkep çizimleri ve görseller.
/// Diskte: <defter>/pages.json, <sayfa-id>.drawing, images/<dosya>
final class NotebookDocument: ObservableObject {
    /// Yayınlanmaz: her kayıtta değişen tarih yüzünden ekranın yeniden çizilmesini istemeyiz.
    private(set) var notebook: Notebook
    @Published private(set) var pages: [PageMeta] = []

    let folder: URL
    private weak var store: NotebookStore?
    private var drawingCache: [UUID: PKDrawing] = [:]
    private let imageCache = NSCache<NSString, UIImage>()
    private var pendingSaves: [UUID: DispatchWorkItem] = [:]
    private let io = DispatchQueue(label: "notenow.io", qos: .utility)

    var pageSize: CGSize { PageOrientation.portrait.size }
    private var pagesURL: URL { folder.appendingPathComponent("pages.json") }
    private var imagesFolder: URL { folder.appendingPathComponent("images", isDirectory: true) }
    private func drawingURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).drawing") }

    init(notebook: Notebook, store: NotebookStore) {
        self.notebook = notebook
        self.store = store
        self.folder = store.folder(for: notebook.id)
        try? FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: pagesURL),
           let list = try? JSONDecoder().decode([PageMeta].self, from: data) {
            pages = list
        }
        if pages.isEmpty {
            pages = [PageMeta(id: UUID(), paper: notebook.paper, images: [])]
            savePages()
        }
        if notebook.orientation == .landscape { migrateToPortrait() }
    }

    /// Sayfalar artık hep dikey (bloknot). Eski yatay defterlerin mürekkebi ve görselleri
    /// dikey sayfanın genişliğine sığacak şekilde küçültülür; hiçbir şey kırpılmaz.
    private func migrateToPortrait() {
        let from = PageOrientation.landscape.size
        let to = PageOrientation.portrait.size
        let k = to.width / from.width
        let t = CGAffineTransform(scaleX: k, y: k)
        for i in pages.indices {
            let id = pages[i].id
            let url = drawingURL(id)
            if let data = try? Data(contentsOf: url), let d = try? PKDrawing(data: data), !d.strokes.isEmpty {
                try? d.transformed(using: t).dataRepresentation().write(to: url, options: .atomic)
            }
            pages[i].images = pages[i].images.map { item in
                var item = item
                item.center = CGPoint(x: item.center.x * k, y: item.center.y * k)
                item.size = CGSize(width: item.size.width * k, height: item.size.height * k)
                return item
            }
        }
        drawingCache.removeAll()
        notebook.orientation = .portrait
        if let data = try? JSONEncoder().encode(pages) {
            try? data.write(to: pagesURL, options: .atomic)
        }
        store?.update(notebook)
    }

    func page(id: UUID) -> PageMeta? { pages.first { $0.id == id } }
    func index(of id: UUID) -> Int? { pages.firstIndex { $0.id == id } }

    // MARK: Mürekkep

    func drawing(for id: UUID) -> PKDrawing {
        if let d = drawingCache[id] { return d }
        var d = PKDrawing()
        if let data = try? Data(contentsOf: drawingURL(id)), let loaded = try? PKDrawing(data: data) {
            d = loaded
        }
        drawingCache[id] = d
        return d
    }

    func setDrawing(_ d: PKDrawing, for id: UUID) {
        drawingCache[id] = d
        pendingSaves[id]?.cancel()
        let url = drawingURL(id)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let data = d.dataRepresentation()
            self.io.async { try? data.write(to: url, options: .atomic) }
            self.pendingSaves[id] = nil
            self.touch()
        }
        pendingSaves[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// Bekleyen tüm kayıtları hemen diske yazar (arka plana geçerken, kapatırken).
    func flushAll() {
        let works = Array(pendingSaves.values)
        pendingSaves.removeAll()
        for w in works {
            w.perform()
            w.cancel()
        }
        io.sync {}
        if !works.isEmpty { SearchIndex.shared.schedule(folder: folder, delay: 0.3) }
    }

    // MARK: Sayfalar

    private func savePages() {
        let snapshot = pages
        let url = pagesURL
        io.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
        touch()
    }

    private func touch() {
        notebook.modified = Date()
        notebook.pageCount = pages.count
        store?.update(notebook)
        SearchIndex.shared.schedule(folder: folder)
    }

    func setLastPage(_ i: Int) {
        guard notebook.lastPage != i else { return }
        notebook.lastPage = i
        store?.update(notebook)
    }

    @discardableResult
    func insertPage(at index: Int) -> PageMeta {
        let paper = pages.indices.contains(index - 1) ? pages[index - 1].paper : notebook.paper
        let page = PageMeta(id: UUID(), paper: paper, images: [])
        pages.insert(page, at: max(0, min(index, pages.count)))
        savePages()
        return page
    }

    func deletePage(at index: Int) {
        guard pages.count > 1, pages.indices.contains(index) else { return }
        let page = pages.remove(at: index)
        pendingSaves[page.id]?.cancel()
        pendingSaves[page.id] = nil
        drawingCache[page.id] = nil
        let drawing = drawingURL(page.id)
        let files = page.images.map { imagesFolder.appendingPathComponent($0.fileName) }
        io.async {
            try? FileManager.default.removeItem(at: drawing)
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        savePages()
    }

    func setPaper(_ paper: PaperType, forPageAt index: Int) {
        guard pages.indices.contains(index) else { return }
        pages[index].paper = paper
        notebook.paper = paper
        savePages()
    }

    private func mutatePage(_ id: UUID, _ body: (inout PageMeta) -> Void) {
        guard let i = index(of: id) else { return }
        body(&pages[i])
        savePages()
    }

    // MARK: Görseller

    func image(_ fileName: String) -> UIImage? {
        if let img = imageCache.object(forKey: fileName as NSString) { return img }
        guard let img = UIImage(contentsOfFile: imagesFolder.appendingPathComponent(fileName).path) else { return nil }
        imageCache.setObject(img, forKey: fileName as NSString)
        return img
    }

    func addImage(_ original: UIImage, to pageID: UUID, at point: CGPoint? = nil) -> ImageItem? {
        let alpha = original.hasAlpha
        let img = original.preparedForStorage(maxPixels: 2400, opaque: !alpha)
        let name = UUID().uuidString + (alpha ? ".png" : ".jpg")
        guard let data = alpha ? img.pngData() : img.jpegData(compressionQuality: 0.9) else { return nil }
        let url = imagesFolder.appendingPathComponent(name)
        io.async { try? data.write(to: url, options: .atomic) }
        imageCache.setObject(img, forKey: name as NSString)

        let maxW = pageSize.width * 0.45
        let maxH = pageSize.height * 0.5
        let aspect = img.size.width / max(img.size.height, 1)
        var w = min(maxW, max(img.size.width, 240))
        var h = w / aspect
        if h > maxH { h = maxH; w = h * aspect }
        let c = point ?? CGPoint(x: pageSize.width / 2, y: pageSize.height / 2)
        let item = ImageItem(id: UUID(), fileName: name, center: c, size: CGSize(width: w, height: h), rotation: 0)
        mutatePage(pageID) { $0.images.append(item) }
        return item
    }

    func updateImage(_ item: ImageItem, on pageID: UUID) {
        mutatePage(pageID) { page in
            if let i = page.images.firstIndex(where: { $0.id == item.id }) { page.images[i] = item }
        }
    }

    func removeImage(_ id: UUID, on pageID: UUID) {
        var removed: ImageItem?
        mutatePage(pageID) { page in
            if let i = page.images.firstIndex(where: { $0.id == id }) { removed = page.images.remove(at: i) }
        }
        if let removed {
            let url = imagesFolder.appendingPathComponent(removed.fileName)
            io.async { try? FileManager.default.removeItem(at: url) }
        }
    }

    func bringToFront(_ id: UUID, on pageID: UUID) {
        mutatePage(pageID) { page in
            if let i = page.images.firstIndex(where: { $0.id == id }) {
                let item = page.images.remove(at: i)
                page.images.append(item)
            }
        }
    }

    // MARK: Küçük resimler

    func thumbnail(for page: PageMeta, width: CGFloat) -> UIImage {
        let size = pageSize
        let s = width / size.width
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: size.height * s))
        let ink = UITraitCollection(userInterfaceStyle: .light).performAsCurrentReturning {
            drawing(for: page.id).image(from: CGRect(origin: .zero, size: size), scale: s * 2)
        }
        return renderer.image { rc in
            let ctx = rc.cgContext
            ctx.scaleBy(x: s, y: s)
            PaperRenderer.draw(page.paper, color: notebook.tint, size: size, in: ctx)
            for item in page.images {
                guard let img = image(item.fileName) else { continue }
                ctx.saveGState()
                ctx.translateBy(x: item.center.x, y: item.center.y)
                ctx.rotate(by: item.rotation)
                img.draw(in: CGRect(x: -item.size.width / 2, y: -item.size.height / 2,
                                    width: item.size.width, height: item.size.height))
                ctx.restoreGState()
            }
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension UITraitCollection {
    func performAsCurrentReturning<T>(_ body: () -> T) -> T {
        var result: T?
        performAsCurrent { result = body() }
        return result!
    }
}

extension UIImage {
    var hasAlpha: Bool {
        guard let info = cgImage?.alphaInfo else { return false }
        return info == .first || info == .last || info == .premultipliedFirst || info == .premultipliedLast
    }

    /// Yönü düzeltir ve çok büyük görselleri küçültür.
    func preparedForStorage(maxPixels: CGFloat, opaque: Bool) -> UIImage {
        let px = CGSize(width: size.width * scale, height: size.height * scale)
        let factor = min(1, maxPixels / max(px.width, px.height))
        let target = CGSize(width: (px.width * factor).rounded(), height: (px.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        let out = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        // Sayfadaki boyut hesabı nokta cinsinden: ekran ölçeğine göre geri böl.
        guard let cg = out.cgImage else { return out }
        return UIImage(cgImage: cg, scale: max(1, scale * factor), orientation: .up)
    }
}
