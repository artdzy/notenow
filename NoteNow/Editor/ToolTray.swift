import PhotosUI
import SwiftUI

/// Kalemlikteki kalem çizimleri (tasarımdaki SVG'lerin aynısı, 28×64).
struct PenGlyph: View {
    let kind: ToolKind
    let tip: Color

    var body: some View {
        Canvas { ctx, _ in
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color, r: CGFloat = 0) {
                ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r), with: .color(c))
            }
            func poly(_ pts: [(CGFloat, CGFloat)], _ c: Color) {
                var p = Path()
                p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) })
                p.closeSubpath()
                ctx.fill(p, with: .color(c))
            }
            let line = Color(hex: 0xD8D1C2)
            switch kind {
            case .fountain:
                rect(8, 26, 12, 38, Color(hex: 0x2A2724))
                rect(8, 30, 12, 3, Color(hex: 0xC9A25B))
                poly([(8, 26), (14, 6), (20, 26)], Color(hex: 0xD9C79B))
                ctx.stroke(Path { p in p.move(to: CGPoint(x: 14, y: 8)); p.addLine(to: CGPoint(x: 14, y: 20)) },
                           with: .color(tip), lineWidth: 2)
            case .pencil:
                rect(8, 26, 12, 38, Color(hex: 0xE5B04E))
                rect(12, 26, 1, 38, Color(hex: 0xD49A35))
                rect(16, 26, 1, 38, Color(hex: 0xD49A35))
                poly([(8, 26), (14, 8), (20, 26)], Color(hex: 0xEED6AA))
                poly([(12, 14), (14, 8), (16, 14)], tip)
            case .felt:
                rect(7, 24, 14, 40, .white)
                ctx.stroke(Path(CGRect(x: 7.5, y: 24.5, width: 13, height: 40)), with: .color(line), lineWidth: 1)
                rect(7, 34, 14, 5, tip)
                poly([(10, 24), (14, 10), (18, 24)], Color(hex: 0xF1ECE1))
                rect(13, 6, 2, 6, tip)
            case .highlighter:
                rect(5, 28, 18, 36, tip)
                rect(5, 40, 18, 2, .black.opacity(0.08))
                poly([(8, 28), (8, 14), (20, 18), (20, 28)], tip)
                poly([(8, 28), (8, 14), (20, 18), (20, 28)], .black.opacity(0.1))
            case .eraser:
                rect(5, 30, 18, 34, Color(hex: 0xF3EFE7), r: 3)
                ctx.stroke(Path(roundedRect: CGRect(x: 5.5, y: 30.5, width: 17, height: 33), cornerRadius: 3),
                           with: .color(line), lineWidth: 1)
                rect(5, 16, 18, 18, Color(hex: 0xE4A39B), r: 4)
            }
        }
        .frame(width: 28, height: 64)
    }
}

struct TrayPenButton: View {
    let kind: ToolKind
    @ObservedObject var model: EditorModel

    var body: some View {
        let active = model.tool == kind
        Button { model.select(kind) } label: {
            PenGlyph(kind: kind, tip: Color(hex: model.color(for: kind)))
                .offset(y: active ? 0 : 14)
                .frame(width: 34, height: 52, alignment: .top)
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: active)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(active ? .isSelected : [])
        .popover(isPresented: Binding(
            get: { model.settingsFor == kind },
            set: { if !$0 { model.settingsFor = nil } }
        )) {
            ToolSettingsView(kind: kind, model: model)
                .presentationCompactAdaptation(.popover)
        }
    }
}

struct ColorDot: View {
    let swatch: InkSwatch
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(swatch.color)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Theme.paper, lineWidth: selected ? 2 : 0).padding(-2))
                .overlay(Circle().stroke(swatch.color, lineWidth: selected ? 2 : 0).padding(-4))
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.name)
    }
}

struct TrayIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color(hex: 0x3A362F))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Üstte yüzen kalemlik: kalemler, renkler, görsel ve geri al.
struct ToolTray: View {
    @ObservedObject var model: EditorModel
    var onPaste: () -> Void
    var onPhotos: () -> Void

    private var swatches: [InkSwatch] {
        if model.tool == .highlighter { return Palette.highlight }
        var list = Array(Palette.ink.prefix(4))
        if let extra = Palette.ink.first(where: { $0.hex == model.inkColor }), !list.contains(extra) {
            list[3] = extra
        }
        return list
    }

    private var currentHex: UInt32 { model.color(for: model.tool == .eraser ? .fountain : model.tool) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ToolKind.allCases) { kind in
                TrayPenButton(kind: kind, model: model)
            }
            divider
            ForEach(swatches) { s in
                ColorDot(swatch: s, selected: model.tool != .eraser && currentHex == s.hex) {
                    model.setColor(s.hex)
                }
            }
            divider
            Menu {
                Button { onPaste() } label: { Label("Panodan yapıştır", systemImage: "doc.on.clipboard") }
                Button { onPhotos() } label: { Label("Fotoğraflardan seç", systemImage: "photo.on.rectangle") }
            } label: {
                Image(systemName: "photo")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0x3A362F))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Görsel ekle")
            TrayIconButton(systemName: "arrow.uturn.backward", label: "Geri al") { model.flipper?.undo() }
            TrayIconButton(systemName: "arrow.uturn.forward", label: "Yinele") { model.flipper?.redo() }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: 0x3C321E).opacity(0.05), radius: 0.5, y: 1)
        .shadow(color: Color(hex: 0x3C321E).opacity(0.10), radius: 12, y: 6)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 28).padding(.horizontal, 6)
    }
}

/// Seçili kaleme ikinci kez dokununca açılan ayarlar.
struct ToolSettingsView: View {
    let kind: ToolKind
    @ObservedObject var model: EditorModel

    private var swatches: [InkSwatch] { kind == .highlighter ? Palette.highlight : Palette.ink }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title).font(Theme.serif(22)).foregroundStyle(Theme.text)
                Spacer()
                if kind != .eraser || model.eraserMode == .partial {
                    Text(model.width(for: kind).title).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }

            if kind == .eraser {
                label("SİLME ŞEKLİ")
                Picker("Silme şekli", selection: $model.eraserMode) {
                    ForEach(EraserMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } else {
                preview
            }

            if kind != .eraser || model.eraserMode == .partial {
                label("KALINLIK")
                HStack(spacing: 10) {
                    ForEach(WidthPreset.allCases) { w in
                        let selected = model.width(for: kind) == w
                        Button { model.widths[kind] = w } label: {
                            Circle()
                                .fill(kind == .eraser ? Theme.muted : Color(hex: model.color(for: kind)))
                                .frame(width: [6, 11, 17][w.rawValue], height: [6, 11, 17][w.rawValue])
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(selected ? Theme.soft : Color(hex: 0xF6F2EA), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink, lineWidth: selected ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(w.title)
                    }
                }
            }

            if kind != .eraser {
                label("RENK")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
                    ForEach(swatches) { s in
                        let selected = model.color(for: kind) == s.hex
                        Button {
                            if kind == .highlighter { model.highlightColor = s.hex } else { model.inkColor = s.hex }
                        } label: {
                            Circle().fill(s.color).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Theme.card, lineWidth: selected ? 2 : 0).padding(-2))
                                .overlay(Circle().stroke(s.color, lineWidth: selected ? 2 : 0).padding(-4))
                                .frame(width: 36, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(s.name)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.card)
    }

    private var preview: some View {
        let w = EditorModel.strokeWidth(kind, model.width(for: kind)) * 0.8
        let color = Color(hex: model.color(for: kind)).opacity(kind == .highlighter ? 0.55 : 1)
        return Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: 18, y: size.height * 0.62))
            p.addCurve(to: CGPoint(x: size.width * 0.42, y: size.height * 0.5),
                       control1: CGPoint(x: size.width * 0.15, y: size.height * 0.1),
                       control2: CGPoint(x: size.width * 0.28, y: size.height * 0.9))
            p.addCurve(to: CGPoint(x: size.width - 18, y: size.height * 0.4),
                       control1: CGPoint(x: size.width * 0.6, y: size.height * 0.1),
                       control2: CGPoint(x: size.width * 0.8, y: size.height * 0.8))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: kind == .highlighter ? .butt : .round))
        }
        .frame(height: 70)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .semibold)).tracking(0.7).foregroundStyle(Theme.muted)
    }
}
