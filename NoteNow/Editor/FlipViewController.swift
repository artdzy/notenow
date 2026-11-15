import Combine
import SwiftUI
import UIKit

/// Sayfaları gerçek bir defter gibi kıvırarak çeviren kap.
/// Parmakla sayfayı sürükleyerek ya da ‹ › düğmeleriyle çevrilir; Apple Pencil sayfayı çevirmez.
final class FlipViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIPencilInteractionDelegate {
    private let doc: NotebookDocument
    private let model: EditorModel
    private let pvc = UIPageViewController(
        transitionStyle: .pageCurl,
        navigationOrientation: .horizontal,
        options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
    )
    private let edge1 = UIView()
    private let edge2 = UIView()
    private let base = UIView()
    private var bag = Set<AnyCancellable>()
    private var isTurning = false

    var currentPage: PageViewController? { pvc.viewControllers?.first as? PageViewController }

    init(doc: NotebookDocument, model: EditorModel) {
        self.doc = doc
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

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

        pvc.isDoubleSided = false
        pvc.dataSource = self
        pvc.delegate = self
        addChild(pvc)
        view.addSubview(pvc.view)
        pvc.view.layer.cornerRadius = 4
        pvc.view.clipsToBounds = true
        pvc.didMove(toParent: self)

        // Sayfa çevirme yalnızca parmakla; kalem dokunuşları mürekkep içindir.
        for g in pvc.gestureRecognizers {
            g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        }

        let start = min(max(0, model.currentIndex), doc.pages.count - 1)
        model.currentIndex = start
        pvc.setViewControllers([makePage(start)], direction: .forward, animated: false)

        let pencil = UIPencilInteraction()
        pencil.delegate = self
        view.addInteraction(pencil)

        doc.$pages
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.pagesChanged() }
            .store(in: &bag)

        model.flipper = self
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = doc.pageSize
        let avail = view.bounds.inset(by: UIEdgeInsets(top: 4, left: 10, bottom: 16, right: 16))
        guard avail.width > 0, avail.height > 0 else { return }
        let s = min(avail.width / size.width, avail.height / size.height)
        let w = (size.width * s).rounded()
        let h = (size.height * s).rounded()
        let rect = CGRect(x: (avail.midX - w / 2).rounded(), y: (avail.midY - h / 2).rounded(), width: w, height: h)
        base.frame = rect
        edge1.frame = rect.offsetBy(dx: 3, dy: 3)
        edge2.frame = rect.offsetBy(dx: 6, dy: 6)
        for v in [base, edge1, edge2] {
            v.layer.shadowPath = UIBezierPath(roundedRect: v.bounds, cornerRadius: 4).cgPath
        }
        pvc.view.frame = rect
    }

    private func makePage(_ index: Int) -> PageViewController {
        PageViewController(pageID: doc.pages[index].id, doc: doc, model: model)
    }

    private var currentIndex: Int? {
        currentPage.flatMap { doc.index(of: $0.pageID) }
    }

    // MARK: Gezinme

    private func show(_ index: Int, direction: UIPageViewController.NavigationDirection, animated: Bool) {
        guard doc.pages.indices.contains(index) else { return }
        currentPage?.deselect()
        isTurning = animated
        pvc.setViewControllers([makePage(index)], direction: direction, animated: animated) { [weak self] _ in
            self?.isTurning = false
        }
        model.currentIndex = index
        doc.setLastPage(index)
    }

    func turn(by delta: Int) {
        guard !isTurning, let i = currentIndex else { return }
        let t = i + delta
        guard doc.pages.indices.contains(t) else { return }
        show(t, direction: delta > 0 ? .forward : .reverse, animated: true)
    }

    func jump(to index: Int) {
        guard let i = currentIndex, index != i else { return }
        show(index, direction: index > i ? .forward : .reverse, animated: true)
    }

    func addPageAfterCurrent() {
        guard !isTurning else { return }
        let i = currentIndex ?? model.currentIndex
        doc.insertPage(at: i + 1)
        show(i + 1, direction: .forward, animated: true)
    }

    func insertImage(_ img: UIImage) {
        currentPage?.addImage(img)
    }

    func undo() { currentPage?.canvas.undoManager?.undo() }
    func redo() { currentPage?.canvas.undoManager?.redo() }

    private func pagesChanged() {
        guard let cur = currentPage else { return }
        if let i = doc.index(of: cur.pageID) {
            if model.currentIndex != i { model.currentIndex = i }
        } else {
            let i = min(model.currentIndex, doc.pages.count - 1)
            show(i, direction: .reverse, animated: false)
        }
    }

    // MARK: UIPageViewController

    func pageViewController(_ p: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let page = vc as? PageViewController, let i = doc.index(of: page.pageID), i > 0 else { return nil }
        return makePage(i - 1)
    }

    func pageViewController(_ p: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let page = vc as? PageViewController, let i = doc.index(of: page.pageID), i < doc.pages.count - 1 else { return nil }
        return makePage(i + 1)
    }

    func pageViewController(_ p: UIPageViewController, willTransitionTo pending: [UIViewController]) {
        currentPage?.deselect()
    }

    func pageViewController(_ p: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let i = currentIndex else { return }
        model.currentIndex = i
        doc.setLastPage(i)
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

struct PageFlipView: UIViewControllerRepresentable {
    let doc: NotebookDocument
    let model: EditorModel

    func makeUIViewController(context: Context) -> FlipViewController {
        FlipViewController(doc: doc, model: model)
    }

    func updateUIViewController(_ vc: FlipViewController, context: Context) {}
}
