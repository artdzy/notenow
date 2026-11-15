import UIKit

/// Sayfaya yapıştırılmış bir görsel. Hareketler PageViewController'da yönetilir,
/// bu görünüm yalnızca çizer.
final class ImageItemView: UIView {
    var item: ImageItem
    private let imageView = UIImageView()
    private let border = CAShapeLayer()
    private var handles: [CAShapeLayer] = []
    static let handleRadius: CGFloat = 9

    var isSelected = false {
        didSet {
            border.isHidden = !isSelected
            handles.forEach { $0.isHidden = !isSelected }
        }
    }

    init(item: ImageItem, image: UIImage) {
        self.item = item
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        imageView.image = image
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 6
        addSubview(imageView)

        layer.shadowColor = UIColor(hex: 0x28200A).cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 8)

        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = UIColor(hex: 0x2F5DAA).cgColor
        border.lineWidth = 2
        border.lineDashPattern = [8, 6]
        border.isHidden = true
        layer.addSublayer(border)

        for _ in 0..<4 {
            let h = CAShapeLayer()
            h.fillColor = UIColor.white.cgColor
            h.strokeColor = UIColor(hex: 0x2F5DAA).cgColor
            h.lineWidth = 2.5
            h.isHidden = true
            layer.addSublayer(h)
            handles.append(h)
        }
        applyItem()
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyItem() {
        transform = .identity
        bounds = CGRect(origin: .zero, size: item.size)
        center = item.center
        transform = CGAffineTransform(rotationAngle: item.rotation)
        setNeedsLayout()
    }

    /// Köşe noktaları, üst görünümün (sayfa) koordinatlarında.
    func cornerPoints(in view: UIView) -> [CGPoint] {
        let b = bounds.insetBy(dx: -8, dy: -8)
        return [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)]
            .map { convert($0, to: view) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 6).cgPath
        let b = bounds.insetBy(dx: -8, dy: -8)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        border.path = UIBezierPath(roundedRect: b, cornerRadius: 10).cgPath
        let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                       CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)]
        let r = Self.handleRadius
        for (h, c) in zip(handles, corners) {
            h.path = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).cgPath
        }
        CATransaction.commit()
    }
}

/// Seçili görselin üstünde çıkan küçük menü.
final class ImageMenuView: UIView {
    var onFront: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.inkUI
        layer.cornerRadius = 22
        layer.shadowColor = UIColor(hex: 0x141928).cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 6)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 44),
        ])
        let items: [(String, UIColor, Selector)] = [
            ("Öne getir", UIColor(hex: 0xFBF8F1), #selector(front)),
            ("Kopyala", UIColor(hex: 0xFBF8F1), #selector(copyTapped)),
            ("Sil", UIColor(hex: 0xF2A79C), #selector(deleteTapped)),
        ]
        for (i, (title, color, sel)) in items.enumerated() {
            if i > 0 {
                let sep = UIView()
                sep.backgroundColor = UIColor(white: 1, alpha: 0.2)
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
                sep.heightAnchor.constraint(equalToConstant: 18).isActive = true
                stack.addArrangedSubview(sep)
            }
            var config = UIButton.Configuration.plain()
            config.title = title
            config.baseForegroundColor = color
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var a = a
                a.font = .systemFont(ofSize: 14, weight: .medium)
                return a
            }
            let b = UIButton(configuration: config)
            b.addTarget(self, action: sel, for: .touchUpInside)
            stack.addArrangedSubview(b)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func front() { onFront?() }
    @objc private func copyTapped() { onCopy?() }
    @objc private func deleteTapped() { onDelete?() }
}
