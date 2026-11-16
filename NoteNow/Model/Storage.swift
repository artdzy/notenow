import Foundation

/// Tüm dosya okuma-yazmaları buradan geçer. iCloud klasöründeki dosyalar başka bir
/// cihazdan aynı anda değişebileceği için NSFileCoordinator ile korunur; henüz inmemiş
/// bir dosyayı okumak onun indirilmesini de bekler.
enum FileIO {
    static func read(_ url: URL) -> Data? {
        var out: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in
            out = try? Data(contentsOf: u)
        }
        return out
    }

    static func write(_ data: Data, to url: URL) {
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            try? data.write(to: u, options: .atomic)
        }
    }

    static func remove(_ url: URL) {
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &err) { u in
            try? FileManager.default.removeItem(at: u)
        }
    }

    static func makeFolder(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

/// iCloud Drive'daki uygulama klasörü (kullanıcının kendi hesabı; Dosyalar'da görünmez).
/// iCloud kapalıysa ya da oturum açılmamışsa notlar yalnızca bu cihazda kalır.
final class CloudSync {
    static let containerID = "iCloud.com.artunduzay.notenow"
    static let didChange = Notification.Name("NoteNowCloudDidChange")

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    /// Arka planda çağrılmalı: ilk seferde birkaç saniye sürebilir.
    static func notebooksFolder() -> URL? {
        guard FileManager.default.ubiquityIdentityToken != nil,
              let base = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else { return nil }
        let url = base.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent("Notebooks", isDirectory: true)
        FileIO.makeFolder(url)
        return url
    }

    /// Başka cihazlardan gelen değişiklikleri izler; her şeyi bu cihaza indirir.
    func start() {
        guard query == nil else { return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        q.notificationBatchingInterval = 1
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in self?.process() })
        }
        query = q
        q.start()
    }

    private func process() {
        guard let q = query else { return }
        q.disableUpdates()
        var urls: [URL] = []
        for case let item as NSMetadataItem in q.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            urls.append(url)
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            // İki cihaz aynı dosyayı yazdıysa son yazan kalır.
            if (item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool) == true {
                DispatchQueue.global(qos: .utility).async {
                    for v in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] { v.isResolved = true }
                    try? NSFileVersion.removeOtherVersionsOfItem(at: url)
                }
            }
        }
        q.enableUpdates()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
