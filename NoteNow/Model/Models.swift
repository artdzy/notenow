import SwiftUI

enum PaperType: String, Codable, CaseIterable, Identifiable {
    case lined, grid, dots, blank
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lined: return "Çizgili"
        case .grid: return "Kareli"
        case .dots: return "Noktalı"
        case .blank: return "Boş"
        }
    }
}

enum PageOrientation: String, Codable, CaseIterable, Identifiable {
    case portrait, landscape
    var id: String { rawValue }
    var title: String { self == .landscape ? "Yatay" : "Dikey" }
    /// Sayfanın mantıksal boyutu (nokta). Ekrana sığacak şekilde ölçeklenir.
    var size: CGSize {
        self == .landscape ? CGSize(width: 1400, height: 1000) : CGSize(width: 1000, height: 1400)
    }
}

enum CoverColor: String, Codable, CaseIterable, Identifiable {
    case navy, terracotta, sage, ochre, charcoal, plum
    var id: String { rawValue }
    var hex: UInt32 {
        switch self {
        case .navy: return 0x1F2A44
        case .terracotta: return 0xB5573A
        case .sage: return 0x7D8F72
        case .ochre: return 0xC99A4A
        case .charcoal: return 0x2D2B28
        case .plum: return 0x6A4C6E
        }
    }
    var color: Color { Color(hex: hex) }
    var title: String {
        switch self {
        case .navy: return "Lacivert"
        case .terracotta: return "Kiremit"
        case .sage: return "Adaçayı"
        case .ochre: return "Hardal"
        case .charcoal: return "Kömür"
        case .plum: return "Mürdüm"
        }
    }
}

struct ImageItem: Codable, Identifiable, Equatable {
    var id: UUID
    var fileName: String
    var center: CGPoint
    var size: CGSize
    var rotation: Double
}

struct PageMeta: Codable, Identifiable, Equatable {
    var id: UUID
    var paper: PaperType
    var images: [ImageItem]
}

struct Notebook: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var title: String
    var cover: CoverColor
    var paper: PaperType
    var orientation: PageOrientation
    var created: Date
    var modified: Date
    var pageCount: Int
    var lastPage: Int

    static func == (a: Notebook, b: Notebook) -> Bool {
        a.id == b.id && a.title == b.title && a.cover == b.cover && a.modified == b.modified
            && a.pageCount == b.pageCount && a.lastPage == b.lastPage && a.paper == b.paper
    }
    func hash(into h: inout Hasher) { h.combine(id) }
}
