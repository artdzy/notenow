import PhotosUI
import SwiftUI

struct EditorView: View {
    @StateObject private var doc: NotebookDocument
    @StateObject private var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPages = false
    @State private var showPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var toast: String?

    init(notebook: Notebook, store: NotebookStore) {
        _doc = StateObject(wrappedValue: NotebookDocument(notebook: notebook, store: store))
        _model = StateObject(wrappedValue: EditorModel(startIndex: notebook.lastPage))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.desk.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 14)
                    .frame(height: 76)
                PageFlipView(doc: doc, model: model)
            }
            if let toast {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                    Text(toast)
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.paper)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Theme.ink.opacity(0.94), in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await MainActor.run {
                        model.flipper?.insertImage(img)
                        showToast("Görsel eklendi · kalemle üstüne yazabilirsin")
                    }
                }
                await MainActor.run { pickerItem = nil }
            }
        }
        .sheet(isPresented: $showPages) {
            PagesSheet(doc: doc, model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { doc.flushAll() }
        }
        .onDisappear { doc.flushAll() }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    doc.flushAll()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Defterlere dön")
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.notebook.title)
                        .font(Theme.serif(22))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(doc.pages.count) sayfa")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ToolTray(model: model, onPaste: paste, onPhotos: { showPicker = true })
                .layoutPriority(1)

            HStack(spacing: 2) {
                navButton("chevron.left", "Önceki sayfa") { model.flipper?.turn(by: -1) }
                    .opacity((model.visibleIndices.first ?? 0) > 0 ? 1 : 0.3)
                Button { showPages = true } label: {
                    Text("\(pageLabel) / \(doc.pages.count)")
                        .font(Theme.serif(19))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                        .frame(minWidth: 64, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sayfalar")
                if (model.visibleIndices.last ?? model.currentIndex) >= doc.pages.count - 1 {
                    navButton("plus", "Yeni sayfa") { model.flipper?.addPageAfterCurrent() }
                } else {
                    navButton("chevron.right", "Sonraki sayfa") { model.flipper?.turn(by: 1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Tek sayfada "3", açık defterde "3–4".
    private var pageLabel: String {
        let v = model.visibleIndices
        guard let a = v.first else { return "\(model.currentIndex + 1)" }
        if let b = v.last, b != a { return "\(a + 1)–\(b + 1)" }
        return "\(a + 1)"
    }

    private func navButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func paste() {
        if let img = UIPasteboard.general.image {
            model.flipper?.insertImage(img)
            showToast("Panodan yapıştırıldı · kalemle üstüne yazabilirsin")
        } else {
            showToast("Panoda görsel yok")
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.25)) { if toast == text { toast = nil } }
        }
    }
}
