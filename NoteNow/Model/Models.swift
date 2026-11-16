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

/// Kâğıdın rengi; defter açılırken seçilir. Çizgiler her renkte kâğıda uyar.
enum PaperColor: String, Codable, CaseIterable, Identifiable {
    case cream, white, yellow, gray, green
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cream: return "Krem"
        case .white: return "Beyaz"
        case .yellow: return "Sarı"
        case .gray: return "Gri"
        case .green: return "Yeşil"
        }
    }
    var paperHex: UInt32 {
        switch self {
        case .cream: return 0xFBF8F1
        case .white: return 0xFFFFFF
        case .yellow: return 0xFBF1C7
        case .gray: return 0xF1F0EC
        case .green: return 0xEEF3E8
        }
    }
    /// Çizgi, kare ve nokta renkleri.
    var ruleHex: UInt32 {
        switch self {
        case .cream: return 0xE6DECD
        case .white: return 0xE2E2E6
        case .yellow: return 0xE6D58E
        case .gray: return 0xDCDAD3
        case .green: return 0xD5DFCB
        }
    }
    var gridHex: UInt32 {
        switch self {
        case .cream: return 0xEAE3D3
        case .white: return 0xE8E8EC
        case .yellow: return 0xEBDDA0
        case .gray: return 0xE2E0DA
        case .green: return 0xDCE5D3
        }
    }
    var dotHex: UInt32 {
        switch self {
        case .cream: return 0xCFC6B3
        case .white: return 0xC9C9D0
        case .yellow: return 0xD4C27A
        case .gray: return 0xC6C3BA
        case .green: return 0xBCC9B0
        }
    }
    var paperUI: UIColor { UIColor(hex: paperHex) }
    var color: Color { Color(hex: paperHex) }
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
    /// Eski defterlerde yok: o zaman krem.
    var paperColor: PaperColor?

    var tint: PaperColor { paperColor ?? .cream }

    static func == (a: Notebook, b: Notebook) -> Bool {
        a.id == b.id && a.title == b.title && a.cover == b.cover && a.modified == b.modified
            && a.pageCount == b.pageCount && a.lastPage == b.lastPage && a.paper == b.paper
            && a.paperColor == b.paperColor
    }
    func hash(into h: inout Hasher) { h.combine(id) }
}
