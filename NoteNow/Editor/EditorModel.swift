import PencilKit
import SwiftUI

enum ToolKind: String, CaseIterable, Identifiable {
    case fountain, pencil, felt, highlighter, eraser
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fountain: return "Dolma kalem"
        case .pencil: return "Kurşun kalem"
        case .felt: return "Keçeli kalem"
        case .highlighter: return "Fosforlu kalem"
        case .eraser: return "Silgi"
        }
    }
}

enum WidthPreset: Int, CaseIterable, Identifiable {
    case thin, medium, thick
    var id: Int { rawValue }
    var title: String { ["İnce", "Orta", "Kalın"][rawValue] }
}

enum EraserMode: String, CaseIterable, Identifiable {
    case partial, whole
    var id: String { rawValue }
    var title: String { self == .partial ? "Kısmi" : "Tüm çizgi" }
}

/// Seçili kalem, renk ve sayfa durumu.
final class EditorModel: ObservableObject {
    @Published var tool: ToolKind = .fountain
    @Published var inkColor: UInt32 = Palette.ink[0].hex
    @Published var highlightColor: UInt32 = Palette.highlight[0].hex
    @Published var widths: [ToolKind: WidthPreset] = [:]
    @Published var eraserMode: EraserMode = .partial
    @Published var currentIndex: Int
    /// Ayar penceresi açık olan kalem.
    @Published var settingsFor: ToolKind?

    private(set) var previousTool: ToolKind = .highlighter
    weak var flipper: FlipViewController?

    init(startIndex: Int) {
        currentIndex = startIndex
    }

    func select(_ t: ToolKind) {
        if tool == t {
            settingsFor = t
        } else {
            previousTool = tool
            tool = t
        }
    }

    func toggleEraser() {
        if tool == .eraser {
            tool = previousTool == .eraser ? .fountain : previousTool
        } else {
            previousTool = tool
            tool = .eraser
        }
    }

    func switchToPrevious() {
        let p = previousTool
        previousTool = tool
        tool = p
    }

    func width(for t: ToolKind) -> WidthPreset { widths[t] ?? .medium }

    /// Seçili rengin kaleme göre değeri (fosforlu kendi paletini kullanır).
    func color(for t: ToolKind) -> UInt32 {
        t == .highlighter ? highlightColor : inkColor
    }

    func setColor(_ hex: UInt32) {
        if tool == .highlighter {
            highlightColor = hex
        } else {
            inkColor = hex
            if tool == .eraser { tool = previousTool == .eraser ? .fountain : previousTool }
        }
    }

    /// Kalınlıklar sayfa noktası cinsindendir (sayfa 1400 nokta genişliğinde).
    static func strokeWidth(_ t: ToolKind, _ w: WidthPreset) -> CGFloat {
        switch t {
        case .fountain: return [2.6, 4.2, 7][w.rawValue]
        case .pencil: return [3.2, 5.5, 9][w.rawValue]   // PencilKit: 2.4…16
        case .felt: return [1.8, 2.8, 4][w.rawValue]   // monoline: 0.5…4
        case .highlighter: return [14, 24, 36][w.rawValue]
        case .eraser: return [8, 20, 44][w.rawValue]
        }
    }

    func pkTool() -> PKTool {
        let w = Self.strokeWidth(tool, width(for: tool))
        switch tool {
        case .fountain:
            return PKInkingTool(.fountainPen, color: UIColor(hex: inkColor), width: w)
        case .pencil:
            return PKInkingTool(.pencil, color: UIColor(hex: inkColor), width: w)
        case .felt:
            return PKInkingTool(.monoline, color: UIColor(hex: inkColor), width: w)
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(hex: highlightColor), width: w)
        case .eraser:
            return eraserMode == .whole ? PKEraserTool(.vector) : PKEraserTool(.bitmap, width: w)
        }
    }
}
