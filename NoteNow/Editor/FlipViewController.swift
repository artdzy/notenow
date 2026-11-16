import Combine
import SwiftUI
import UIKit

/// Sayfaları gerçek bir defter gibi kıvırarak çeviren kap.
/// Parmakla sayfayı sürükleyerek ya da ‹ › düğmeleriyle çevrilir; Apple Pencil sayfayı çevirmez.
///
/// Dikey defter, iPad yatay tutulunca açık defter gibi iki sayfa yan yana gösterir
/// (sol çift, sağ tek sayfa); dikey tutulunca tek sayfa, bloknot gibi.
final class FlipViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIPencilInteractionDelegate {
    private let doc: NotebookDocument
    private let model: EditorModel
    private var pvc: UIPageViewController!
    private var isSpread = false
    private let edge1 = UIView()
    private let edge2 = UIView()
    private let base = UIView()
    private let gutter = GutterView()
    private var bag = Set<AnyCancellable>()
    private var isTurning = false

    init(doc: NotebookDocument, model: EditorModel) {
        self.doc = doc
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Görünen sayfalar

    private var visiblePages: [PageViewController] {
        (pvc?.viewControllers ?? []).compactMap { $0 as? PageViewController }
    }

    /// Etkin sayfa: kalemin son yazdığı, yoksa soldaki.
    var currentPage: PageViewController? {
        let pages = visiblePages
        return pages.first { doc.index(of: $0.pageID) == model.currentIndex } ?? pages.first
    }

    private var visibleIndices: [Int] {
        visiblePages.compactMap { doc.index(of: $0.pageID) }.sorted()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        for (v, c) in [(edge2, Theme.paperEdgeUI), (edge1, Theme.paperEdge2UI), (base, Theme.paperUI)] {
            v.backgroundColor = c
            v.layer.cornerRadius = 4
            v.layer.shadowColor = UIColor(hex: 0x3C321E).cgColor
            v.layer.shadowOpacity = 0.12
            v.layer.shadowRadius = 1.5
            v.layer.shadowOffset = CGSize(width: 0, height: 1)
            view.addSubview(v)
        }
        base.layer.shadowOpacity = 0.14
        base.layer.shadowRadius = 20
        base.layer.shadowOffset = CGSize(width: 0, height: 14)
        // Kâğıt kenarları ve gölge hiç değişmez: bir kez çizilsin, kalem yazarken her karede yeniden hesaplanmasın.
        for v in [base, edge1, edge2] {
            v.layer.shouldRasterize = true
            v.layer.rasterizationScale = UIScreen.main.scale
        }

        gutter.isUserInteractionEnabled = false
        gutter.isHidden = true
        view.addSubview(gutter)

        let start = min(max(0, model.currentIndex), doc.pages.count - 1)
        model.currentIndex = start
        buildPager(spread: wantsSpread(for: view.bounds.size), showing: start)

        let pencil = UIPencilInteraction()
        pencil.delegate = self
        view.addInteraction(pencil)

        doc.$pages
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.pagesChanged() }
            .store(in: &bag)

        model.flipper = self
    }

    /// Yatay ekran = açık defter (iki dikey sayfa).
    private func wantsSpread(for size: CGSize) -> Bool {
        size.width > size.height * 1.05
    }

    /// Sayfa çevirici kurulur; açık defter ile tek sayfa arasında geçerken yeniden kurulur.
    private func buildPager(spread: Bool, showing index: Int) {
        if let old = pvc {
            visiblePages.forEach { $0.deselect() }
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        isSpread = spread
        isTurning = false
        let p = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: (spread ? UIPageViewController.SpineLocation.mid : .min).rawValue)]
        )
        p.isDoubleSided = spread
        p.dataSource = self
        p.delegate = self
        addChild(p)
        view.insertSubview(p.view, belowSubview: gutter)
        // Köşe yuvarlatma maskesi yok: maske, PencilKit'in mürekkebi her karede ekran dışında
        // birleştirmesine yol açıp kalemde gecikme hissi yaratıyordu.
        p.view.clipsToBounds = false
        p.didMove(toParent: self)

        // Sayfa çevirme yalnızca tek parmakla; kalem mürekkep, iki parmak yakınlaştırma içindir.
        for g in p.gestureRecognizers {
            g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            (g as? UIPanGestureRecognizer)?.maximumNumberOfTouches = 1
        }
        pvc = p
        p.setViewControllers(controllers(for: index), direction: .forward, animated: false)
        gutter.isHidden = !spread
        publishVisible(active: index)
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        let spread = wantsSpread(for: view.bounds.size)
        if spread != isSpread {
            buildPager(spread: spread, showing: model.currentIndex)
        }
        let page = doc.pageSize
        let size = CGSize(width: page.width * (isSpread ? 2 : 1), height: page.height)
        let avail = view.bounds.inset(by: UIEdgeInsets(top: 4, left: 10, bottom: 16, right: 16))
        guard avail.width > 0, avail.height > 0 else { return }
        let s = min(avail.width / size.width, avail.height / size.height)
        var w = (size.width * s).rounded()
        if isSpread, Int(w) % 2 == 1 { w -= 1 }
        let h = (size.height * s).rounded()
        let rect = CGRect(x: (avail.midX - w / 2).rounded(), y: (avail.midY - h / 2).rounded(), width: w, height: h)
        guard pvc.view.frame != rect else { return }
        base.frame = rect
        edge1.frame = rect.offsetBy(dx: 3, dy: 3)
        edge2.frame = rect.offsetBy(dx: 6, dy: 6)
        for v in [base, edge1, edge2] {
            v.layer.shadowPath = UIBezierPath(roundedRect: v.bounds, cornerRadius: 4).cgPath
        }
        pvc.view.frame = rect
        gutter.frame = CGRect(x: rect.midX - 22, y: rect.minY, width: 44, height: rect.height)
    }

    // MARK: Sayfa denetleyicileri

    private func makePage(_ index: Int) -> PageViewController {
        let page = PageViewController(pageID: doc.pages[index].id, doc: doc, model: model)
        page.onZoomChange = { [weak self] _ in self?.updateCurl() }
        page.onActivate = { [weak self, weak page] in
            guard let self, let page, let i = self.doc.index(of: page.pageID), self.model.currentIndex != i else { return }
            self.model.currentIndex = i
            self.doc.setLastPage(i)
        }
        return page
    }

    private func makeBlank() -> BlankPageViewController {
        let blank = BlankPageViewController()
        blank.onAdd = { [weak self] in self?.addPageAfterCurrent() }
        return blank
    }

    /// Verilen sayfayı içeren açık defter (sol çift, sağ tek) ya da tek sayfa.
    private func controllers(for index: Int) -> [UIViewController] {
        let i = min(max(0, index), doc.pages.count - 1)
        guard isSpread else { return [makePage(i)] }
        let left = i - i % 2
        let right: UIViewController = left + 1 < doc.pages.count ? makePage(left + 1) : makeBlank()
        return [makePage(left), right]
    }

    private func spreadStart(_ i: Int) -> Int { isSpread ? i - i % 2 : i }

    private func publishVisible(active: Int?) {
        let vis = visibleIndices
        guard !vis.isEmpty else { return }
        if model.visibleIndices != vis { model.visibleIndices = vis }
        let a = active.flatMap { vis.contains($0) ? $0 : nil } ?? (vis.contains(model.currentIndex) ? model.currentIndex : vis[0])
        if model.currentIndex != a { model.currentIndex = a }
        doc.setLastPage(a)
        updateCurl()
    }

    /// Görünen sayfalardan biri yakınlaştırılmışken parmak sayfayı kaydırır, çevirmez.
    private func updateCurl() {
        let on = !visiblePages.contains { $0.isZoomed }
        for g in pvc.gestureRecognizers { g.isEnabled = on }
    }

    // MARK: Gezinme

    private func show(_ index: Int, direction: UIPageViewController.NavigationDirection, animated: Bool) {
        guard doc.pages.indices.contains(index) else { return }
        visiblePages.forEach { $0.deselect() }
        isTurning = animated
        pvc.setViewControllers(controllers(for: index), direction: direction, animated: animated) { [weak self] _ in
            self?.isTurning = false
        }
        publishVisible(active: index)
    }

    func turn(by delta: Int) {
        guard !isTurning, let first = visibleIndices.first else { return }
        let t = first + delta * (isSpread ? 2 : 1)
        guard doc.pages.indices.contains(t) else { return }
        show(t, direction: delta > 0 ? .forward : .reverse, animated: true)
    }

    func jump(to index: Int) {
        guard let first = visibleIndices.first else { return }
        if spreadStart(index) == spreadStart(first) {
            publishVisible(active: index)
            return
        }
        show(index, direction: index > first ? .forward : .reverse, animated: true)
    }

    func addPageAfterCurrent() {
        guard !isTurning else { return }
        let last = visibleIndices.last ?? model.currentIndex
        let new = last + 1
        // Açık defterde sağdaki boş yaprak dolacaksa sayfa çevirmeye gerek yok.
        let sameSpread = isSpread && spreadStart(new) == spreadStart(last)
        isTurning = true   // pagesChanged araya girmesin
        doc.insertPage(at: new)
        isTurning = false
        if sameSpread {
            pvc.setViewControllers(controllers(for: new), direction: .forward, animated: false)
            publishVisible(active: new)
        } else {
            show(new, direction: .forward, animated: true)
        }
    }

    func insertImage(_ img: UIImage) {
        currentPage?.addImage(img)
    }

    func undo() { currentPage?.canvas.undoManager?.undo() }
    func redo() { currentPage?.canvas.undoManager?.redo() }

    /// Sayfa eklenip silinince görünen yapraklar hâlâ doğru mu?
    private func pagesChanged() {
        guard let pvc, !isTurning else { return }
        let shown = (pvc.viewControllers ?? []).map { ($0 as? PageViewController)?.pageID }
        let active = currentPage.flatMap { doc.index(of: $0.pageID) } ?? min(model.currentIndex, doc.pages.count - 1)
        let want = controllers(for: active)
        if shown != want.map({ ($0 as? PageViewController)?.pageID }) {
            pvc.setViewControllers(want, direction: .reverse, animated: false)
        }
        publishVisible(active: active)
    }

    // MARK: UIPageViewController

    private func index(of vc: UIViewController) -> Int? {
        if vc is BlankPageViewController { return doc.pages.count }
        return (vc as? PageViewController).flatMap { doc.index(of: $0.pageID) }
    }

    func pageViewController(_ p: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let i = index(of: vc), i > 0 else { return nil }
        return makePage(i - 1)
    }

    func pageViewController(_ p: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let i = index(of: vc) else { return nil }
        if i + 1 < doc.pages.count { return makePage(i + 1) }
        // Açık defterde son sayfa solda kalırsa sağına boş bir yaprak gelir.
        if isSpread, i + 1 == doc.pages.count, i % 2 == 0 { return makeBlank() }
        return nil
    }

    func pageViewController(_ p: UIPageViewController, willTransitionTo pending: [UIViewController]) {
        visiblePages.forEach { $0.deselect() }
    }

    func pageViewController(_ p: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed else { return }
        publishVisible(active: visibleIndices.first)
    }

    // MARK: Apple Pencil çift dokunma / sıkma

    private func performPreferred(_ action: UIPencilPreferredAction) {
        switch action {
        case .switchEraser: model.toggleEraser()
        case .switchPrevious: model.switchToPrevious()
        case .showColorPalette: model.settingsFor = model.tool
        case .ignore: break
        default: model.settingsFor = model.tool
        }
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        performPreferred(UIPencilInteraction.preferredTapAction)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        performPreferred(UIPencilInteraction.preferredTapAction)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        performPreferred(UIPencilInteraction.preferredSqueezeAction)
    }
}

/// Açık defterin sağında, son sayfadan sonra duran boş yaprak. Dokununca yeni sayfa olur.
final class BlankPageViewController: UIViewController {
    var onAdd: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.paperUI

        let muted = UIColor(hex: 0x6B655A)
        let icon = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .light)))
        icon.tintColor = muted
        let label = UILabel()
        label.text = "Yeni sayfa için dokun"
        label.font = .systemFont(ofSize: 15)
        label.textColor = muted
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.alpha = 0.8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        view.addGestureRecognizer(tap)
    }

    @objc private func tapped() { onAdd?() }
}

/// Açık defterin ortasındaki cilt gölgesi.
final class GutterView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let g = layer as! CAGradientLayer
        let c = UIColor(hex: 0x3C321E)
        g.colors = [c.withAlphaComponent(0).cgColor, c.withAlphaComponent(0.08).cgColor,
                    c.withAlphaComponent(0.15).cgColor, c.withAlphaComponent(0.08).cgColor, c.withAlphaComponent(0).cgColor]
        g.locations = [0, 0.4, 0.5, 0.6, 1]
        g.startPoint = CGPoint(x: 0, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 0.5)
        backgroundColor = .clear
    }

    convenience init() { self.init(frame: .zero) }

    required init?(coder: NSCoder) { fatalError() }
}

struct PageFlipView: UIViewControllerRepresentable {
    let doc: NotebookDocument
    let model: EditorModel

    func makeUIViewController(context: Context) -> FlipViewController {
        FlipViewController(doc: doc, model: model)
    }

    func updateUIViewController(_ vc: FlipViewController, context: Context) {}
}
