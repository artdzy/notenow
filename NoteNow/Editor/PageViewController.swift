import Combine
import PencilKit
import UIKit

/// Her sayfanın kendi geri al geçmişi olsun diye.
final class NoteCanvasView: PKCanvasView {
    private let localUndo = UndoManager()
    override var undoManager: UndoManager? { localUndo }
}

/// Tek bir sayfa: kâğıt, görseller ve en üstte PencilKit tuvali.
///
/// Kalem her zaman mürekkep çizer. Parmak ise görselleri taşır, büyütür, döndürür;
/// görselin dışında iki parmakla sıkıştırmak sayfayı yakınlaştırır, tek parmakla
/// kaydırmak sayfayı çevirir (yakınlaştırılmışken sayfayı kaydırır).
final class PageViewController: UIViewController, PKCanvasViewDelegate, UIGestureRecognizerDelegate, UIDropInteractionDelegate {
    let pageID: UUID
    private let doc: NotebookDocument
    private let model: EditorModel

    let canvas = NoteCanvasView()
    private let pageLayer = UIView()
    private let paperView = PaperView()
    private let imagesLayer = UIView()
    private let menu = ImageMenuView()

    private var imageViews: [UUID: ImageItemView] = [:]
    private(set) var selectedID: UUID?
    private var interacting = Set<UUID>()
    private var bag = Set<AnyCancellable>()
    private var fitScale: CGFloat = 1
    private var laidOutSize = CGSize.zero
    private var wasZoomed = false

    /// Yakınlaştırma durumu değişince (sayfa çevirmeyi kapatıp açmak için).
    var onZoomChange: ((Bool) -> Void)?
    /// Açık defterde kalemin ya da parmağın dokunduğu sayfa etkin olur.
    var onActivate: (() -> Void)?
    var isZoomed: Bool { canvas.zoomScale > fitScale * 1.02 }

    private let pan = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()
    private let rotate = UIRotationGestureRecognizer()
    private let tap = UITapGestureRecognizer()

    private enum DragMode { case none, move, resize }
    private var dragMode = DragMode.none
    private var panID: UUID?
    private var panStartCenter = CGPoint.zero
    private var panStartSize = CGSize.zero
    private var panStartDist: CGFloat = 1
    private var pinchID: UUID?
    private var pinchStartSize = CGSize.zero
    private var rotateID: UUID?
    private var rotateStart: Double = 0

    init(pageID: UUID, doc: NotebookDocument, model: EditorModel) {
        self.pageID = pageID
        self.doc = doc
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.paperUI
        view.clipsToBounds = true

        let size = doc.pageSize
        pageLayer.bounds = CGRect(origin: .zero, size: size)
        pageLayer.isUserInteractionEnabled = false
        paperView.frame = pageLayer.bounds
        imagesLayer.frame = pageLayer.bounds
        imagesLayer.isUserInteractionEnabled = false
        pageLayer.addSubview(paperView)
        pageLayer.addSubview(imagesLayer)
        view.addSubview(pageLayer)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.isScrollEnabled = false
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.bouncesZoom = true
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.decelerationRate = .normal
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawing = doc.drawing(for: pageID)
        canvas.delegate = self
        view.addSubview(canvas)

        menu.isHidden = true
        menu.onFront = { [weak self] in self?.bringSelectedToFront() }
        menu.onCopy = { [weak self] in self?.copySelected() }
        menu.onDelete = { [weak self] in self?.deleteSelected() }
        view.addSubview(menu)

        let direct = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        rotate.addTarget(self, action: #selector(handleRotate(_:)))
        tap.addTarget(self, action: #selector(handleTap(_:)))
        for g in [pan, pinch, rotate, tap] as [UIGestureRecognizer] {
            g.allowedTouchTypes = direct
            g.delegate = self
            view.addGestureRecognizer(g)
        }

        // Görselin üstündeki hareketler önce gelir; değilse tuval yakınlaştırır / kaydırır.
        canvas.pinchGestureRecognizer?.require(toFail: pinch)
        canvas.panGestureRecognizer.require(toFail: pan)

        view.addInteraction(UIDropInteraction(delegate: self))

        doc.$pages
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncImages() }
            .store(in: &bag)
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyTool() }
            .store(in: &bag)

        syncImages()
        applyTool()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0, view.bounds.size != laidOutSize else { return }
        laidOutSize = view.bounds.size
        let size = doc.pageSize
        fitScale = view.bounds.width / size.width

        // Sayfa tam sığar; iki parmakla 5 katına kadar yakınlaşır.
        canvas.frame = view.bounds
        canvas.minimumZoomScale = fitScale
        canvas.maximumZoomScale = fitScale * 5
        canvas.zoomScale = fitScale
        updateContentSize()
        canvas.contentOffset = .zero
        syncPageLayer()
        updateZoomState()
        positionMenu()
    }

    private func updateContentSize() {
        let z = canvas.zoomScale
        let size = doc.pageSize
        canvas.contentSize = CGSize(width: size.width * z, height: size.height * z)
    }

    /// Kâğıt ve görseller tuvalle birlikte yakınlaşıp kayar.
    private func syncPageLayer() {
        let z = canvas.zoomScale
        let size = doc.pageSize
        let o = canvas.contentOffset
        pageLayer.transform = CGAffineTransform(scaleX: z, y: z)
        pageLayer.center = CGPoint(x: size.width * z / 2 - o.x, y: size.height * z / 2 - o.y)
    }

    private func updateZoomState() {
        let zoomed = isZoomed
        canvas.isScrollEnabled = zoomed
        guard zoomed != wasZoomed else { return }
        wasZoomed = zoomed
        onZoomChange?(zoomed)
    }

    func resetZoom(animated: Bool) {
        canvas.setZoomScale(fitScale, animated: animated)
    }

    // MARK: Yakınlaştırma

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentSize()
        syncPageLayer()
        positionMenu()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        syncPageLayer()
        positionMenu()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scale < fitScale * 1.02 {
            canvas.setZoomScale(fitScale, animated: true)
            canvas.setContentOffset(.zero, animated: true)
        }
        updateZoomState()
    }

    private func applyTool() {
        canvas.tool = model.pkTool()
    }

    // MARK: PencilKit

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        doc.setDrawing(canvasView.drawing, for: pageID)
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        deselect()
        onActivate?()
    }

    // MARK: Görseller

    private func syncImages() {
        guard let page = doc.page(id: pageID) else { return }
        paperView.paper = page.paper
        var seen = Set<UUID>()
        for item in page.images {
            seen.insert(item.id)
            if let v = imageViews[item.id] {
                if !interacting.contains(item.id), v.item != item {
                    v.item = item
                    v.applyItem()
                }
                imagesLayer.bringSubviewToFront(v)
            } else if let img = doc.image(item.fileName) {
                let v = ImageItemView(item: item, image: img)
                imagesLayer.addSubview(v)
                imageViews[item.id] = v
            }
        }
        let gone = imageViews.keys.filter { !seen.contains($0) }
        for id in gone {
            imageViews[id]?.removeFromSuperview()
            imageViews[id] = nil
            if selectedID == id { deselect() }
        }
        positionMenu()
    }

    func addImage(_ img: UIImage, atViewPoint vp: CGPoint? = nil) {
        let anchor = vp ?? (isZoomed ? CGPoint(x: view.bounds.midX, y: view.bounds.midY) : nil)
        let p = anchor.map { view.convert($0, to: imagesLayer) }
        guard let item = doc.addImage(img, to: pageID, at: p) else { return }
        syncImages()
        select(item.id)
    }

    private func imageID(at p: CGPoint) -> UUID? {
        for v in imagesLayer.subviews.reversed() {
            guard let iv = v as? ImageItemView else { continue }
            let local = imagesLayer.convert(p, to: iv)
            if iv.bounds.insetBy(dx: -12, dy: -12).contains(local) { return iv.item.id }
        }
        return nil
    }

    /// Seçili görselin köşe tutamağına mı dokunuldu?
    private func handleHit(_ viewPoint: CGPoint) -> UUID? {
        guard let id = selectedID, let iv = imageViews[id] else { return nil }
        for c in iv.cornerPoints(in: view) where hypot(c.x - viewPoint.x, c.y - viewPoint.y) < 30 {
            return id
        }
        return nil
    }

    private func select(_ id: UUID) {
        selectedID = id
        for v in imageViews.values { v.isSelected = v.item.id == id }
        positionMenu()
    }

    func deselect() {
        guard selectedID != nil else { return }
        selectedID = nil
        for v in imageViews.values { v.isSelected = false }
        menu.isHidden = true
    }

    private func positionMenu() {
        guard let id = selectedID, let iv = imageViews[id], interacting.isEmpty else {
            menu.isHidden = true
            return
        }
        let frame = imagesLayer.convert(iv.frame, to: view)
        let size = menu.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        var y = frame.minY - size.height - 18
        if y < 10 { y = frame.maxY + 18 }
        y = min(max(10, y), view.bounds.height - size.height - 10)
        let x = min(max(10, frame.midX - size.width / 2), view.bounds.width - size.width - 10)
        menu.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        menu.isHidden = false
        view.bringSubviewToFront(menu)
    }

    private func commit(_ id: UUID?) {
        guard let id, let iv = imageViews[id] else { return }
        interacting.remove(id)
        doc.updateImage(iv.item, on: pageID)
        positionMenu()
    }

    private func clamped(_ s: CGSize) -> CGSize {
        let aspect = s.width / max(s.height, 1)
        let w = min(max(s.width, 60), doc.pageSize.width * 1.4)
        return CGSize(width: w, height: w / aspect)
    }

    private func bringSelectedToFront() {
        guard let id = selectedID else { return }
        doc.bringToFront(id, on: pageID)
    }

    private func copySelected() {
        guard let id = selectedID, let iv = imageViews[id], let img = doc.image(iv.item.fileName) else { return }
        UIPasteboard.general.image = img
        deselect()
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        deselect()
        doc.removeImage(id, on: pageID)
    }

    // MARK: Hareketler

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        if let id = imageID(at: g.location(in: imagesLayer)) {
            onActivate?()
            select(id)
        } else {
            deselect()
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            if let id = handleHit(g.location(in: view)), let iv = imageViews[id] {
                dragMode = .resize
                panID = id
                panStartSize = iv.item.size
                panStartCenter = iv.item.center
                let p = g.location(in: imagesLayer)
                panStartDist = max(1, hypot(p.x - panStartCenter.x, p.y - panStartCenter.y))
            } else if let id = imageID(at: g.location(in: imagesLayer)), let iv = imageViews[id] {
                select(id)
                dragMode = .move
                panID = id
                panStartCenter = iv.item.center
            }
            if let id = panID { interacting.insert(id) }
            menu.isHidden = true
        case .changed:
            guard let id = panID, let iv = imageViews[id] else { return }
            if dragMode == .move {
                let t = g.translation(in: imagesLayer)
                iv.item.center = CGPoint(x: panStartCenter.x + t.x, y: panStartCenter.y + t.y)
            } else if dragMode == .resize {
                let p = g.location(in: imagesLayer)
                let d = hypot(p.x - panStartCenter.x, p.y - panStartCenter.y)
                let s = max(0.1, d / panStartDist)
                iv.item.size = clamped(CGSize(width: panStartSize.width * s, height: panStartSize.height * s))
            }
            iv.applyItem()
        default:
            let id = panID
            panID = nil
            dragMode = .none
            commit(id)
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            guard let id = imageID(at: g.location(in: imagesLayer)), let iv = imageViews[id] else { return }
            select(id)
            pinchID = id
            pinchStartSize = iv.item.size
            interacting.insert(id)
            menu.isHidden = true
        case .changed:
            guard let id = pinchID, let iv = imageViews[id] else { return }
            iv.item.size = clamped(CGSize(width: pinchStartSize.width * g.scale, height: pinchStartSize.height * g.scale))
            iv.applyItem()
        default:
            let id = pinchID
            pinchID = nil
            commit(id)
        }
    }

    @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
        switch g.state {
        case .began:
            guard let id = imageID(at: g.location(in: imagesLayer)), let iv = imageViews[id] else { return }
            rotateID = id
            rotateStart = iv.item.rotation
            interacting.insert(id)
        case .changed:
            guard let id = rotateID, let iv = imageViews[id] else { return }
            var r = rotateStart + Double(g.rotation)
            // Düz açılara hafifçe yapışsın.
            let snap = (r / (.pi / 2)).rounded() * (.pi / 2)
            if abs(r - snap) < 0.06 { r = snap }
            iv.item.rotation = r
            iv.applyItem()
        default:
            let id = rotateID
            rotateID = nil
            commit(id)
        }
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        let p = g.location(in: imagesLayer)
        if g === pan || g === pinch, imageID(at: p) != nil { onActivate?() }
        if g === tap { return imageID(at: p) != nil || selectedID != nil }
        if g === pan { return handleHit(g.location(in: view)) != nil || imageID(at: p) != nil }
        if g === pinch || g === rotate { return imageID(at: p) != nil }
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool {
        let mine: [UIGestureRecognizer] = [pan, pinch, rotate]
        return mine.contains { $0 === g } && mine.contains { $0 === o }
    }

    /// Sayfa çevirme hareketleri, önce görsel hareketlerimizin başarısız olmasını bekler.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy o: UIGestureRecognizer) -> Bool {
        guard g === pan || g === tap, let ov = o.view else { return false }
        return ov !== view && !ov.isDescendant(of: view)
    }

    // MARK: Sürükle bırak

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.canLoadObjects(ofClass: UIImage.self)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        let point = session.location(in: view)
        session.loadObjects(ofClass: UIImage.self) { [weak self] items in
            guard let img = items.first as? UIImage else { return }
            DispatchQueue.main.async { self?.addImage(img, atViewPoint: point) }
        }
    }
}
