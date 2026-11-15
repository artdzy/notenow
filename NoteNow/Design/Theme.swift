import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: opacity))
    }
}

/// "Kâğıt & Mürekkep" tasarım dili.
enum Theme {
    static let desk = Color(hex: 0xE9E5DC)
    static let deskUI = UIColor(hex: 0xE9E5DC)
    static let paper = Color(hex: 0xFBF8F1)
    static let paperUI = UIColor(hex: 0xFBF8F1)
    static let paperEdgeUI = UIColor(hex: 0xF3EEE3)
    static let paperEdge2UI = UIColor(hex: 0xF7F3EA)
    static let card = Color(hex: 0xFFFDF8)
    static let ink = Color(hex: 0x1F2A44)
    static let inkUI = UIColor(hex: 0x1F2A44)
    static let text = Color(hex: 0x1F1D1A)
    static let muted = Color(hex: 0x6B655A)
    static let hairline = Color(hex: 0xE3DCCB)
    static let soft = Color(hex: 0xF1ECE1)
    static let danger = Color(hex: 0xC8402F)
    static let ruleUI = UIColor(hex: 0xE6DECD)
    static let gridUI = UIColor(hex: 0xEAE3D3)
    static let dotUI = UIColor(hex: 0xCFC6B3)

    /// Başlıklar için sistemin serif yazı tipi (New York).
    static func serif(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}

struct InkSwatch: Identifiable, Hashable {
    let name: String
    let hex: UInt32
    var id: UInt32 { hex }
    var color: Color { Color(hex: hex) }
}

enum Palette {
    static let ink: [InkSwatch] = [
        InkSwatch(name: "Lacivert", hex: 0x1F2A44),
        InkSwatch(name: "Kırmızı", hex: 0xC8402F),
        InkSwatch(name: "Mavi", hex: 0x2F5DAA),
        InkSwatch(name: "Yeşil", hex: 0x2E7D5B),
        InkSwatch(name: "Siyah", hex: 0x1A1A1A),
        InkSwatch(name: "Mor", hex: 0x6A4C93),
        InkSwatch(name: "Turuncu", hex: 0xD9772B),
        InkSwatch(name: "Gri", hex: 0x8C8476),
    ]
    static let highlight: [InkSwatch] = [
        InkSwatch(name: "Sarı", hex: 0xF4DC63),
        InkSwatch(name: "Yeşil", hex: 0xA8DDA0),
        InkSwatch(name: "Pembe", hex: 0xF4A7C0),
        InkSwatch(name: "Mavi", hex: 0x9CC7F0),
    ]
}
