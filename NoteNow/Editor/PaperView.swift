import UIKit

enum PaperRenderer {
    static let lineSpacing: CGFloat = 50
    static let gridSpacing: CGFloat = 40

    static func draw(_ paper: PaperType, size: CGSize, in ctx: CGContext) {
        ctx.setFillColor(Theme.paperUI.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        switch paper {
        case .lined:
            ctx.setFillColor(Theme.ruleUI.cgColor)
            var y = lineSpacing * 2
            while y < size.height - 10 {
                ctx.fill(CGRect(x: 0, y: y, width: size.width, height: 1.5))
                y += lineSpacing
            }
        case .grid:
            ctx.setFillColor(Theme.gridUI.cgColor)
            var y: CGFloat = gridSpacing
            while y < size.height {
                ctx.fill(CGRect(x: 0, y: y, width: size.width, height: 1.2))
                y += gridSpacing
            }
            var x: CGFloat = gridSpacing
            while x < size.width {
                ctx.fill(CGRect(x: x, y: 0, width: 1.2, height: size.height))
                x += gridSpacing
            }
        case .dots:
            ctx.setFillColor(Theme.dotUI.cgColor)
            var y: CGFloat = gridSpacing
            while y < size.height {
                var x: CGFloat = gridSpacing
                while x < size.width {
                    ctx.fillEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                    x += gridSpacing
                }
                y += gridSpacing
            }
        case .blank:
            break
        }
    }
}

final class PaperView: UIView {
    var paper: PaperType = .lined {
        didSet { if oldValue != paper { setNeedsDisplay() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        isOpaque = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        PaperRenderer.draw(paper, size: bounds.size, in: ctx)
    }
}
