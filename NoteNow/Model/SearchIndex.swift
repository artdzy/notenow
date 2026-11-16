import PencilKit
import UIKit
import Vision

/// Bir sayfanın tanınan yazısı. Ekranda hiç görünmez; yalnızca aramada kullanılır.
struct PageText: Codable {
    var text: String
    /// Vision'ın ikinci, üçüncü tahminleri: el yazısında doğru kelimeyi kaçırmamak için.
    var alternates: String
    /// Sayfa değişmediyse yeniden tanımaya gerek yok.
    var signature: String
}

struct SearchHit: Identifiable {
    let notebook: Notebook
    /// Sayfa sırası; yalnızca defter adı eşleştiyse nil.
    let pageIndex: Int?
    let before: String
    let match: String
    let after: String
    var id: String { "\(notebook.id)-\(pageIndex ?? -1)" }
}

/// El yazısını ve yapıştırılan görsellerdeki yazıyı cihazda (Apple Vision) metne çevirir.
/// Her defterin klasöründe `text.json` olarak durur. Hiçbir şey cihazdan çıkmaz.
final class SearchIndex {
    static let shared = SearchIndex()
    static let didChange = Notification.Name("NoteNowSearchIndexDidChange")

    private let queue = DispatchQueue(label: "notenow.ocr", qos: .utility)
    private let lock = NSLock()
    private var cache: [URL: [String: PageText]] = [:]
    private var pending: [URL: DispatchWorkItem] = [:]

    private func indexURL(_ folder: URL) -> URL { folder.appendingPathComponent("text.json") }

    // MARK: Okuma

    func index(for folder: URL) -> [String: PageText] {
        lock.lock(); defer { lock.unlock() }
        if let c = cache[folder] { return c }
        let loaded = FileIO.read(indexURL(folder)).flatMap { try? JSONDecoder().decode([String: PageText].self, from: $0) } ?? [:]
        cache[folder] = loaded
        return loaded
    }

    // MARK: Tanıma

    /// Sayfa değişince birkaç saniye bekleyip yeniden tanır (yazarken her harfte değil).
    func schedule(folder: URL, delay: TimeInterval = 3) {
        DispatchQueue.main.async {
            self.pending[folder]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.queue.async { self?.reindex(folder) }
            }
            self.pending[folder] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// Açılışta: daha önce tanınmamış ya da değişmiş sayfalar.
    func reindexAll(_ folders: [URL]) {
        queue.async { folders.forEach { self.reindex($0) } }
    }

    private func reindex(_ folder: URL) {
        guard let data = FileIO.read(folder.appendingPathComponent("pages.json")),
              let pages = try? JSONDecoder().decode([PageMeta].self, from: data) else { return }
        var idx = index(for: folder)
        var changed = false
        let ids = Set(pages.map { $0.id.uuidString })
        for key in idx.keys where !ids.contains(key) {
            idx[key] = nil
            changed = true
        }
        for page in pages {
            let key = page.id.uuidString
            let sig = signature(folder, page)
            if idx[key]?.signature == sig { continue }
            let (text, alt) = autoreleasepool { recognize(folder, page) }
            idx[key] = PageText(text: text, alternates: alt, signature: sig)
            changed = true
        }
        guard changed else { return }
        lock.lock()
        cache[folder] = idx
        lock.unlock()
        if let out = try? JSONEncoder().encode(idx) {
            FileIO.write(out, to: indexURL(folder))
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    private func signature(_ folder: URL, _ page: PageMeta) -> String {
        let url = folder.appendingPathComponent("\(page.id.uuidString).drawing")
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(Int(date * 1000))|" + page.images.map(\.fileName).joined(separator: ",")
    }

    /// Sayfayı beyaz zemine kâğıt çizgileri olmadan çizer, Vision ile okur.
    private func recognize(_ folder: URL, _ page: PageMeta) -> (String, String) {
        let size = PageOrientation.portrait.size
        let url = folder.appendingPathComponent("\(page.id.uuidString).drawing")
        var drawing = FileIO.read(url).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        // Fosforlu kalem lekeleri harfleri bozmasın.
        drawing = PKDrawing(strokes: drawing.strokes.filter { $0.ink.inkType != .marker })
        if drawing.strokes.isEmpty && page.images.isEmpty { return ("", "") }

        let scale: CGFloat = 1.5
        let ink = UITraitCollection(userInterfaceStyle: .light).performAsCurrentReturning {
            drawing.image(from: CGRect(origin: .zero, size: size), scale: scale)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { rc in
            let ctx = rc.cgContext
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for item in page.images {
                guard let img = FileIO.read(folder.appendingPathComponent("images").appendingPathComponent(item.fileName)).flatMap(UIImage.init(data:)) else { continue }
                ctx.saveGState()
                ctx.translateBy(x: item.center.x, y: item.center.y)
                ctx.rotate(by: item.rotation)
                img.draw(in: CGRect(x: -item.size.width / 2, y: -item.size.height / 2, width: item.size.width, height: item.size.height))
                ctx.restoreGState()
            }
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cg = rendered.cgImage else { return ("", "") }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let langs = ["tr-TR", "en-US"].filter { supported.contains($0) }
        if !langs.isEmpty { request.recognitionLanguages = langs }
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])

        // Yukarıdan aşağı, soldan sağa.
        let obs = (request.results ?? []).sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01 ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
        }
        var lines: [String] = []
        var alts: [String] = []
        for o in obs {
            let c = o.topCandidates(3)
            if let first = c.first { lines.append(first.string) }
            alts.append(contentsOf: c.dropFirst().map(\.string))
        }
        return (lines.joined(separator: "\n"), alts.joined(separator: "\n"))
    }

    // MARK: Arama

    /// Büyük/küçük harf, Türkçe ı/i ve şapka/çengel farkı gözetmeden arar.
    static func fold(_ s: String) -> [Character] {
        s.map { ch -> Character in
            if ch == "ı" || ch == "İ" || ch == "I" { return "i" }
            return String(ch).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR")).first ?? ch
        }
    }

    static func find(_ needle: [Character], in hay: [Character]) -> Int? {
        guard !needle.isEmpty, needle.count <= hay.count else { return nil }
        outer: for i in 0...(hay.count - needle.count) {
            for j in 0..<needle.count where hay[i + j] != needle[j] { continue outer }
            return i
        }
        return nil
    }

    func search(_ query: String, in notebooks: [Notebook], folder: (UUID) -> URL) -> [SearchHit] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map { Self.fold(String($0)) }
        guard !words.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for nb in notebooks {
            let titleFold = Self.fold(nb.title)
            if words.allSatisfy({ Self.find($0, in: titleFold) != nil }) {
                hits.append(SearchHit(notebook: nb, pageIndex: nil, before: "", match: nb.title, after: ""))
            }
            let dir = folder(nb.id)
            guard let data = FileIO.read(dir.appendingPathComponent("pages.json")),
                  let pages = try? JSONDecoder().decode([PageMeta].self, from: data) else { continue }
            let idx = index(for: dir)
            for (i, page) in pages.enumerated() {
                guard let t = idx[page.id.uuidString], !t.text.isEmpty || !t.alternates.isEmpty else { continue }
                let text = t.text.replacingOccurrences(of: "\n", with: " ")
                let chars = Array(text)
                let folded = Self.fold(text)
                let foldedAlt = Self.fold(t.alternates)
                guard words.allSatisfy({ Self.find($0, in: folded) != nil || Self.find($0, in: foldedAlt) != nil }) else { continue }
                if let at = Self.find(words[0], in: folded) {
                    let end = at + words[0].count
                    let from = max(0, at - 40)
                    let to = min(chars.count, end + 60)
                    hits.append(SearchHit(
                        notebook: nb, pageIndex: i,
                        before: (from > 0 ? "…" : "") + String(chars[from..<at]),
                        match: String(chars[at..<end]),
                        after: String(chars[end..<to]) + (to < chars.count ? "…" : "")
                    ))
                } else {
                    hits.append(SearchHit(notebook: nb, pageIndex: i, before: String(chars.prefix(100)), match: "", after: ""))
                }
            }
        }
        return hits
    }
}
