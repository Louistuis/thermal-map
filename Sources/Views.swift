import SwiftUI

// MARK: - Design tokens
//
// Apple-native type (SF Pro text, SF Pro Rounded for big numbers, tabular digits), sentence case,
// soft graphite surfaces with hairline light edges, Liquid Glass on the controls only (macOS 26),
// quiet springs and crossfades. The thermal image itself stays solid: glass never sits on data.

enum UI {
    static let bgTop = Color(red: 0.067, green: 0.071, blue: 0.082)
    static let bgBottom = Color(red: 0.039, green: 0.043, blue: 0.051)
    static let sidebar = Color(red: 0.078, green: 0.082, blue: 0.094)
    static let card = Color.white.opacity(0.045)
    static let hairline = Color.white.opacity(0.085)
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.34)
    static let accent = Color(red: 0.63, green: 0.82, blue: 1.0)
    static let live = Color(red: 0.42, green: 0.92, blue: 0.62)

    static func text(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w) }
    static func rounded(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .rounded) }
    static let spring = Animation.spring(response: 0.36, dampingFraction: 0.86)
    static func fmt(_ v: Double, _ d: Int = 1) -> String { v.isNaN ? "–" : String(format: "%.\(d)f", v) }
}

extension ViewSide { var title: String { self == .bottom ? "Bottom" : "Top" } }
extension FieldMode { var title: String { self == .internalMode ? "Internal" : "Bottom case" } }
extension Palette {
    var title: String {
        switch self { case .ironbow: "Ironbow"; case .rainbow: "Rainbow"; case .arctic: "Arctic"; case .white: "White hot" }
    }
    var gradient: LinearGradient {
        LinearGradient(stops: (0...12).map { Gradient.Stop(color: color(Double($0) / 12), location: Double($0) / 12) },
                       startPoint: .leading, endPoint: .trailing)
    }
}

/// Display names for the board parts and die blocks (the layout keys stay terse).
enum Names {
    static func part(_ n: String) -> String {
        switch n {
        case "LOGIC BOARD": "Logic board"
        case "HEAT SINK": "Heat sink"
        case "SPK L": "Speaker L"
        case "SPK R": "Speaker R"
        case "TRACKPAD": "Trackpad"
        case "AUDIO": "Audio"
        case "MAGSAFE": "MagSafe"
        case "3.5": "3.5 mm"
        default: n.hasPrefix("CELL") ? "Cell" + n.dropFirst(4) : n
        }
    }
    static func die(_ n: String) -> String {
        switch n {
        case "P-CLUSTER": "P-cores"
        case "E-CLUSTER": "E-cores"
        case "NPU": "Neural Engine"
        case "GPU  10-CORE": "GPU · 10 cores"
        case "SLC / FABRIC": "Cache + fabric"
        default: n
        }
    }
}

// MARK: - Surfaces

/// Liquid Glass on macOS 26 for live windows; a drawn soft-glass look elsewhere (older systems and the
/// headless renderer, which cannot capture real glass).
struct GlassSurface: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *), !ThermalModel.renderMode {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(Color(white: 0.16).opacity(0.72)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
    }
}

struct CardSurface: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(UI.card))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.11), .white.opacity(0.035)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 0.6))
    }
}

extension View {
    func glass(_ r: CGFloat = 18) -> some View { modifier(GlassSurface(radius: r)) }
    func card(_ r: CGFloat = 14) -> some View { modifier(CardSurface(radius: r)) }
}

// MARK: - Root

struct ContentView: View {
    @ObservedObject var m: ThermalModel
    /// remembered per Mac model, so the notice stays closed once closed
    @AppStorage("modelNoticeDismissed." + ThermalModel.hwModel) private var noticeDismissed = false
    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Header(m: m)
                    ChassisView(m: m)
                        .padding(.bottom, 64)
                }
                Legend(m: m).padding(.bottom, 18)
                if !MacModel.isSupported && !noticeDismissed {
                    VStack {
                        ModelNotice { withAnimation(UI.spring) { noticeDismissed = true } }.padding(.top, 70)
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(LinearGradient(colors: [UI.bgTop, UI.bgBottom], startPoint: .top, endPoint: .bottom))
            Rectangle().fill(UI.hairline).frame(width: 0.5)
            Sidebar(m: m).frame(width: 352)
        }
        .foregroundStyle(UI.primary)
        .frame(minWidth: 1180, minHeight: 760)
    }
}

// MARK: - Controls

struct Segmented<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var sel: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                let on = sel == o
                Text(label(o))
                    .font(UI.text(12, on ? .semibold : .medium))
                    .foregroundStyle(on ? UI.primary : UI.secondary)
                    .padding(.horizontal, 13).frame(height: 26)
                    .background {
                        if on {
                            Capsule(style: .continuous).fill(Color.white.opacity(0.15))
                                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(UI.spring) { sel = o } }
            }
        }
        .padding(3)
        .glass(16)
    }
}

struct PalettePicker: View {
    @Binding var sel: Palette
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Palette.allCases, id: \.self) { p in
                let on = sel == p
                Circle().fill(AngularGradient(gradient: Gradient(colors: (0...8).map { p.color(Double($0) / 8) }), center: .center,
                                              startAngle: .degrees(-90), endAngle: .degrees(270)))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.white.opacity(on ? 0.95 : 0.18), lineWidth: on ? 1.6 : 0.5))
                    .scaleEffect(on ? 1.0 : 0.86)
                    .padding(2)
                    .contentShape(Circle())
                    .onTapGesture { withAnimation(UI.spring) { sel = p } }
                    .help(p.title)
            }
        }
        .padding(.horizontal, 7).frame(height: 32)
        .glass(16)
    }
}

struct ToggleChip: View {
    let title: String
    let symbol: String
    @Binding var on: Bool
    @State private var hover = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .medium))
            Text(title).font(UI.text(11.5, .medium))
        }
        .foregroundStyle(on ? UI.primary : UI.tertiary)
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(on ? 0.12 : (hover ? 0.06 : 0))))
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .onTapGesture { withAnimation(UI.spring) { on.toggle() } }
    }
}

struct LiveDot: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(UI.live.opacity(0.35)).frame(width: 12, height: 12)
                .scaleEffect(pulse ? 1.0 : 0.4).opacity(pulse ? 0 : 0.9)
            Circle().fill(UI.live).frame(width: 6, height: 6)
        }
        .frame(width: 12, height: 12)
        .onAppear {
            guard !ThermalModel.renderMode else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Shown on a Mac that has no layout of its own yet. Small, closable, and points to the guide in the repo.
struct ModelNotice: View {
    var close: () -> Void
    static let guide = URL(string: "https://github.com/Louistuis/thermal-map/blob/main/docs/ADD-A-MAC.md")!
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(red: 1, green: 0.78, blue: 0.35))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Made for the \(MacModel.macBookAir13M3.name)").font(UI.text(12.5, .semibold))
                Text("This Mac is \(ThermalModel.hwModel). The readings are real, but the map shows the M3 Air's board, so it won't match this machine.")
                    .font(UI.text(11)).foregroundStyle(UI.secondary).fixedSize(horizontal: false, vertical: true)
                Group {
                    if ThermalModel.renderMode {   // headless renders cannot draw Link
                        Text("Add your Mac to Thermal Map  →").font(UI.text(11, .semibold)).foregroundStyle(UI.accent)
                    } else {
                        Link(destination: ModelNotice.guide) {
                            Text("Add your Mac to Thermal Map  →").font(UI.text(11, .semibold)).foregroundStyle(UI.accent)
                        }
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 4)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(UI.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 560, alignment: .leading)
        // solid enough to read over the heat map (glass would let the colours through)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.09).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
    }
}

// MARK: - Header

struct Header: View {
    @ObservedObject var m: ThermalModel
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Thermal Map").font(UI.text(15, .semibold))
                    LiveDot()
                }
                Text("Made for the \(MacModel.active.name)  ·  \(m.side == .bottom ? "seen from below, like an IR camera" : "seen from above, through the keyboard")")
                    .font(UI.text(11.5)).foregroundStyle(UI.secondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 16)
            Segmented(options: ViewSide.allCases, label: { $0.title }, sel: $m.side)
            Segmented(options: FieldMode.allCases, label: { $0.title }, sel: $m.mode)
            PalettePicker(sel: $m.palette)
        }
        .padding(.leading, 86)      // clear of the traffic lights
        .padding(.trailing, 20)
        .frame(height: 62)
    }
}

// MARK: - Chassis map

struct ChassisView: View {
    @ObservedObject var m: ThermalModel
    @ObservedObject private var fs: FrameStore
    init(m: ThermalModel) { _m = ObservedObject(wrappedValue: m); _fs = ObservedObject(wrappedValue: m.frameStore) }
    @State private var hover: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let pad: CGFloat = 50
            let s = min((geo.size.width - pad * 2) / Board.width, (geo.size.height - pad * 2) / Board.depth)
            let w = Board.width * s, h = Board.depth * s
            let ox = (geo.size.width - w) / 2, oy = (geo.size.height - h) / 2
            let map = Mapper(s: s, ox: ox, oy: oy, mirror: m.side == .bottom)
            let shape = RoundedRectangle(cornerRadius: Board.corner * s, style: .continuous)

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in drawBackdrop(ctx, size, map) }
                // soft contact shadow under the machine
                shape.fill(Color.black.opacity(0.55))
                    .frame(width: w, height: h)
                    .blur(radius: 22).offset(x: ox, y: oy + 14)
                // the field crossfades between updates, so 5 Hz data reads as continuous motion
                CrossfadeField(frame: fs.frame, map: map, isotherms: m.showIsotherms)
                .frame(width: geo.size.width, height: geo.size.height)
                .mask(shape.frame(width: w, height: h).offset(x: ox, y: oy).frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading))
                Canvas { ctx, size in drawOverlay(ctx, size, map) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let p) = phase { hover = p } else { hover = nil }
            }
        }
    }

    struct Mapper {
        let s: CGFloat, ox: CGFloat, oy: CGFloat, mirror: Bool
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + (mirror ? Board.width - p.x : p.x) * s, y: oy + p.y * s) }
        func rect(_ r: CGRect) -> CGRect {
            let x = mirror ? Board.width - r.maxX : r.minX
            return CGRect(x: ox + x * s, y: oy + r.minY * s, width: r.width * s, height: r.height * s)
        }
        func top(fromView v: CGPoint) -> CGPoint {
            let x = (v.x - ox) / s, y = (v.y - oy) / s
            return CGPoint(x: mirror ? Board.width - x : x, y: y)
        }
    }

    /// The new frame is drawn fully opaque underneath; only the previous frame fades out on top of it, so the
    /// field never dips in brightness between updates.
    struct CrossfadeField: View {
        let frame: Frame
        let map: Mapper
        let isotherms: Bool
        @State private var last: Frame?
        @State private var prev: Frame?
        @State private var fade: Double = 0
        var body: some View {
            ZStack(alignment: .topLeading) {
                FieldLayer(frame: frame, map: map, isotherms: isotherms)
                if let prev, fade > 0.001 {
                    FieldLayer(frame: prev, map: map, isotherms: isotherms).opacity(fade)
                }
            }
            .onAppear { last = frame }
            .onChange(of: frame.serial) {
                guard !ThermalModel.renderMode else { last = frame; return }
                prev = last
                last = frame
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { fade = 1 }
                // start the fade on the next runloop pass, after the opaque old frame has been committed
                DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.22)) { fade = 0 } }
            }
        }
    }

    /// The heat image plus its isotherms: one unit, so they fade together.
    struct FieldLayer: View {
        let frame: Frame
        let map: Mapper
        let isotherms: Bool
        var body: some View {
            ZStack(alignment: .topLeading) {
                if let img = frame.image {
                    Image(decorative: img, scale: 1)
                        .resizable().interpolation(.high)
                        .frame(width: Board.width * map.s, height: Board.depth * map.s)
                        .offset(x: map.ox, y: map.oy)
                }
                if isotherms {
                    Canvas { ctx, _ in
                        for c in frame.contours {
                            var path = Path(); var i = 0
                            let segs = c.segments
                            while i + 1 < segs.count { path.move(to: map.pt(segs[i])); path.addLine(to: map.pt(segs[i + 1])); i += 2 }
                            ctx.stroke(path, with: .color(.white.opacity(c.major ? 0.55 : 0.22)),
                                       style: StrokeStyle(lineWidth: c.major ? 0.9 : 0.5, lineCap: .round, lineJoin: .round))
                        }
                        for c in frame.contours where c.major {
                            var best = CGPoint.zero, bestScore = CGFloat.greatestFiniteMagnitude, k = 0
                            while k < c.segments.count {
                                let q = c.segments[k]
                                let score: CGFloat = abs(q.y - 105) + abs(q.x - 152) * 0.2
                                if score < bestScore { bestScore = score; best = q }
                                k += 2
                            }
                            let v = map.pt(best)
                            let lbl = ctx.resolve(Text("\(Int(c.level))°").font(UI.rounded(9.5, .semibold)).foregroundStyle(.white))
                            let sz = lbl.measure(in: CGSize(width: 60, height: 20))
                            let box = CGRect(x: v.x - sz.width / 2 - 5, y: v.y - sz.height / 2 - 1.5, width: sz.width + 10, height: sz.height + 3)
                            ctx.fill(Path(roundedRect: box, cornerRadius: box.height / 2, style: .continuous), with: .color(.black.opacity(0.5)))
                            ctx.draw(lbl, at: v)
                        }
                    }
                }
            }
        }
    }

    private func drawBackdrop(_ ctx: GraphicsContext, _ size: CGSize, _ map: Mapper) {
        // 10 mm dot grid: quieter than lines
        let step = 10 * map.s
        var dots = Path()
        var y = map.oy.truncatingRemainder(dividingBy: step)
        while y < size.height {
            var x = map.ox.truncatingRemainder(dividingBy: step)
            while x < size.width { dots.addEllipse(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)); x += step }
            y += step
        }
        ctx.fill(dots, with: .color(.white.opacity(0.07)))

        // rulers
        let w = Board.width * map.s, h = Board.depth * map.s
        var ticks = Path()
        for mm in stride(from: 0, through: Int(Board.width), by: 10) {
            let px = map.ox + CGFloat(mm) * map.s
            let len: CGFloat = mm % 50 == 0 ? 6 : 3
            ticks.move(to: CGPoint(x: px, y: map.oy - 12)); ticks.addLine(to: CGPoint(x: px, y: map.oy - 12 - len))
            if mm % 50 == 0 {
                ctx.draw(Text("\(mm)").font(UI.text(9.5).monospacedDigit()).foregroundStyle(UI.tertiary), at: CGPoint(x: px, y: map.oy - 26))
            }
        }
        for mm in stride(from: 0, through: Int(Board.depth), by: 10) {
            let py = map.oy + CGFloat(mm) * map.s
            let len: CGFloat = mm % 50 == 0 ? 6 : 3
            ticks.move(to: CGPoint(x: map.ox - 12, y: py)); ticks.addLine(to: CGPoint(x: map.ox - 12 - len, y: py))
            if mm % 50 == 0 {
                ctx.draw(Text("\(mm)").font(UI.text(9.5).monospacedDigit()).foregroundStyle(UI.tertiary), at: CGPoint(x: map.ox - 30, y: py))
            }
        }
        ctx.stroke(ticks, with: .color(.white.opacity(0.22)), lineWidth: 0.6)
        ctx.draw(Text("304.1 mm").font(UI.text(10, .medium)).foregroundStyle(UI.tertiary), at: CGPoint(x: map.ox + w / 2, y: map.oy + h + 16))
        ctx.draw(Text("215 mm").font(UI.text(10, .medium)).foregroundStyle(UI.tertiary), at: CGPoint(x: map.ox + w + 28, y: map.oy + h / 2))
    }

    private func drawOverlay(_ ctx: GraphicsContext, _ size: CGSize, _ map: Mapper) {
        let s = map.s
        let chassis = CGRect(x: map.ox, y: map.oy, width: Board.width * s, height: Board.depth * s)
        let shell = Path(roundedRect: chassis, cornerRadius: Board.corner * s, style: .continuous)
        // machined edge: bright hairline with a soft inner bevel
        ctx.stroke(shell, with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0.22)]),
                                                startPoint: CGPoint(x: chassis.midX, y: chassis.minY), endPoint: CGPoint(x: chassis.midX, y: chassis.maxY)),
                   lineWidth: 1)
        ctx.stroke(Path(roundedRect: chassis.insetBy(dx: 3.5, dy: 3.5), cornerRadius: Board.corner * s - 3.5, style: .continuous),
                   with: .color(.white.opacity(0.06)), lineWidth: 0.6)

        ctx.draw(Text("Hinge").font(UI.text(10, .medium)).foregroundStyle(UI.tertiary), at: CGPoint(x: chassis.midX, y: chassis.minY - 9))
        ctx.draw(Text("Front").font(UI.text(10, .medium)).foregroundStyle(UI.tertiary), at: CGPoint(x: chassis.midX, y: chassis.maxY + 31))

        if m.showParts {
            for p in Board.parts {
                let r = map.rect(p.rect)
                let path = Path(roundedRect: r, cornerRadius: p.kind == .chip ? 2.5 : 6, style: .continuous)
                switch p.kind {
                case .battery: ctx.stroke(path, with: .color(.white.opacity(0.2)), style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                case .trackpad: ctx.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 0.6)
                case .board: ctx.stroke(path, with: .color(.white.opacity(0.26)), lineWidth: 0.7)
                case .chip: ctx.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 0.8)
                case .module, .port: ctx.stroke(path, with: .color(.white.opacity(0.32)), lineWidth: 0.6)
                case .sink: ctx.stroke(path, with: .color(.white.opacity(0.38)), style: StrokeStyle(lineWidth: 0.7, dash: [6, 2, 1, 2]))
                }
                if p.kind != .port {
                    let strong = p.kind == .chip
                    let t = Text(Names.part(p.name)).font(UI.text(strong ? 9.5 : 9.5, strong ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(strong ? 0.88 : 0.5))
                    if p.kind == .sink { ctx.draw(t, at: CGPoint(x: r.minX + 5, y: r.maxY - 3), anchor: .bottomLeading) }
                    else { ctx.draw(t, at: CGPoint(x: r.minX + 5, y: r.minY + 3), anchor: .topLeading) }
                }
            }
            if m.side == .bottom {
                for c in Board.feet {
                    let v = map.pt(c); let r = 5.5 * s
                    ctx.stroke(Path(ellipseIn: CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.24)), lineWidth: 0.7)
                }
            }
        }

        let f = m.frame
        let span = max(f.hi - f.lo, 0.1)
        let live = m.liveSensors

        if m.showSensors {
            for sn in live where sn.valid && sn.placement != nil && sn.placement?.die == nil && !sn.value.isNaN {
                let v = map.pt(sn.placement!.point)
                let r: CGFloat = sn.source == "HID" ? 2.2 : 2.8
                let dot = Path(ellipseIn: CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r))
                if sn.source == "HID" || m.mode == .surface {
                    // on the bottom-case view the readings are internal, so they are marked, not coloured
                    ctx.stroke(dot, with: .color(.white.opacity(m.mode == .surface ? 0.45 : 0.7)), lineWidth: 0.7)
                } else {
                    ctx.fill(dot, with: .color(m.palette.color((sn.value - f.lo) / span)))
                    ctx.stroke(dot, with: .color(.white.opacity(0.85)), lineWidth: 0.7)
                }
                if m.showLabels && sn.source == "SMC" {
                    ctx.draw(Text("\(sn.key) \(UI.fmt(sn.value))").font(UI.text(8.5, .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.88)),
                             at: CGPoint(x: v.x + 5, y: v.y), anchor: .leading)
                }
            }
            let dieN = live.filter { $0.valid && $0.placement?.die != nil }.count
            let dc = map.pt(Board.dieCenter)
            ctx.stroke(Path(ellipseIn: CGRect(x: dc.x - 6, y: dc.y - 6, width: 12, height: 12)), with: .color(.white.opacity(0.9)), lineWidth: 1)
            ctx.draw(Text("\(dieN) die sensors").font(UI.text(9.5, .medium)).foregroundStyle(.white.opacity(0.8)),
                     at: CGPoint(x: dc.x, y: dc.y + 13 + 3 * s), anchor: .top)
        }

        if let hl = m.highlighted, let sn = live.first(where: { $0.id == hl }), let p = sn.placement {
            let v = map.pt(p.point)
            for (rad, a) in [(8.0, 0.95), (14.0, 0.4)] {
                ctx.stroke(Path(ellipseIn: CGRect(x: v.x - rad, y: v.y - rad, width: 2 * rad, height: 2 * rad)), with: .color(UI.accent.opacity(a)), lineWidth: 1.1)
            }
            pill(ctx, strong: "\(UI.fmt(sn.value))°", rest: "\(sn.key)  ·  \(p.zone)", at: CGPoint(x: v.x + 18, y: v.y - 18), tint: UI.accent)
        }

        // hotspot
        let hp = map.pt(f.hotspot)
        var cross = Path()
        for (dx, dy) in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1)] {
            cross.move(to: CGPoint(x: hp.x + dx * 5, y: hp.y + dy * 5)); cross.addLine(to: CGPoint(x: hp.x + dx * 13, y: hp.y + dy * 13))
        }
        ctx.stroke(cross, with: .color(.white), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        let peak = (m.mode == .internalMode && !f.corePeak.isNaN) ? "Hottest point  ·  core peak \(UI.fmt(f.corePeak))°" : "Hottest point"
        pill(ctx, strong: "\(UI.fmt(f.hotValue))°", rest: peak, at: CGPoint(x: hp.x + 16, y: hp.y + 18), tint: .white)

        // cursor probe
        if let hv = hover {
            let top = map.top(fromView: hv)
            if let t = m.value(atTop: top) {
                var c = Path()
                c.addEllipse(in: CGRect(x: hv.x - 5, y: hv.y - 5, width: 10, height: 10))
                ctx.stroke(c, with: .color(UI.accent), lineWidth: 1.1)
                let near = live.filter { $0.valid && $0.placement != nil && $0.source == "SMC" }
                    .min { dist($0.placement!.point, top) < dist($1.placement!.point, top) }
                let nearTxt = near.map { "  ·  near \($0.key), \($0.zone) \(UI.fmt($0.value))°" } ?? ""
                pill(ctx, strong: "\(UI.fmt(t))°", rest: "\(Int(top.x)), \(Int(top.y)) mm\(nearTxt)", at: CGPoint(x: hv.x + 12, y: hv.y - 22), tint: UI.accent)
            }
        }
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// A soft dark capsule: bold reading, then quieter context.
    private func pill(_ ctx: GraphicsContext, strong: String, rest: String, at p: CGPoint, tint: Color) {
        let a = ctx.resolve(Text(strong).font(UI.rounded(12, .semibold).monospacedDigit()).foregroundStyle(tint))
        let b = ctx.resolve(Text(rest).font(UI.text(10.5, .medium)).foregroundStyle(.white.opacity(0.7)))
        let sa = a.measure(in: CGSize(width: 300, height: 40)), sb = b.measure(in: CGSize(width: 600, height: 40))
        let hgt = max(sa.height, sb.height) + 9
        let r = CGRect(x: p.x, y: p.y - hgt / 2, width: sa.width + sb.width + 26, height: hgt)
        let shape = Path(roundedRect: r, cornerRadius: hgt / 2, style: .continuous)
        ctx.fill(shape, with: .color(Color(white: 0.06).opacity(0.82)))
        ctx.stroke(shape, with: .color(.white.opacity(0.16)), lineWidth: 0.5)
        ctx.draw(a, at: CGPoint(x: r.minX + 10, y: r.midY), anchor: .leading)
        ctx.draw(b, at: CGPoint(x: r.minX + 16 + sa.width, y: r.midY), anchor: .leading)
    }
}

// MARK: - Legend (floating glass bar)

struct Legend: View {
    @ObservedObject var m: ThermalModel
    @ObservedObject private var fs: FrameStore
    init(m: ThermalModel) { _m = ObservedObject(wrappedValue: m); _fs = ObservedObject(wrappedValue: m.frameStore) }
    var body: some View {
        let f = m.frame
        HStack(spacing: 12) {
            Text(UI.fmt(f.lo) + "°").font(UI.rounded(12, .medium).monospacedDigit()).foregroundStyle(UI.secondary)
                .frame(width: 40, alignment: .trailing)
            VStack(spacing: 3) {
                Capsule(style: .continuous).fill(m.palette.gradient).frame(height: 6)
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                Canvas { ctx, size in
                    let span = max(f.hi - f.lo, 0.1)
                    let step: Double = span > 40 ? 10 : (span > 16 ? 5 : 2)
                    var v = (f.lo / step).rounded(.up) * step
                    while v <= f.hi {
                        let x = (v - f.lo) / span * size.width
                        ctx.draw(Text("\(Int(v))").font(UI.text(9).monospacedDigit()).foregroundStyle(UI.tertiary), at: CGPoint(x: x, y: size.height / 2))
                        v += step
                    }
                }
                .frame(height: 11)
            }
            .frame(width: 300)
            Text(UI.fmt(f.hi) + "°").font(UI.rounded(12, .medium).monospacedDigit()).foregroundStyle(UI.secondary)
                .frame(width: 40, alignment: .leading)
            Rectangle().fill(UI.hairline).frame(width: 0.5, height: 20)
            HStack(spacing: 2) {
                ToggleChip(title: "Auto range", symbol: "arrow.up.and.down", on: $m.autoRange)
                ToggleChip(title: "Isotherms", symbol: "point.topleft.down.to.point.bottomright.curvepath", on: $m.showIsotherms)
                ToggleChip(title: "Parts", symbol: "square.dashed", on: $m.showParts)
                ToggleChip(title: "Sensors", symbol: "smallcircle.filled.circle", on: $m.showSensors)
                ToggleChip(title: "Keys", symbol: "textformat", on: $m.showLabels)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glass(22)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @ObservedObject var m: ThermalModel
    @State private var query = ""
    @State private var expanded: [String: Bool] = [:]

    var body: some View {
        scroller {
            VStack(alignment: .leading, spacing: 22) {
                readouts
                section("M3 die", detail: "every die sensor") { DieInset(m: m) }
                section("Last two minutes") { HistoryChart(history: m.history).frame(height: 104) }
                sensorList
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(m.smcKeyCount) SMC keys scanned, \(m.smcTempCount) are temperatures, plus \(m.hidCount) HID thermal services. Read in \(UI.fmt(m.lastSampleMs)) ms once a second; the map updates five times a second.")
                    Text("Thermal Map, its heat model and its board layout were made specifically to show the heat inside the 13-inch MacBook Air with M3 (Mac15,12). Other Macs can be added: see docs/ADD-A-MAC.md in the repo.")
                    Text("The layout is calibrated to Apple's Self Service Repair manual for this machine (J613), within about 3 to 5 mm. Each reading is pinned at the part it measures, and a two-layer heat-conduction model fills in everything between them. Bottom case shows the modelled outer aluminium, which is what an IR camera would see.")
                }
                .font(UI.text(10.5)).foregroundStyle(UI.tertiary).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 24)
        }
        .background(UI.sidebar)
    }

    @ViewBuilder private func scroller<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        if ThermalModel.renderMode {
            let content = c()
            GeometryReader { g in content.frame(width: g.size.width, alignment: .top) }.clipped()
        } else { ScrollView { c() }.scrollIndicators(.never) }
    }

    private func section<C: View>(_ title: String, detail: String? = nil, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(UI.text(13, .semibold))
                Spacer()
                if let detail { Text(detail).font(UI.text(11)).foregroundStyle(UI.tertiary) }
            }
            c()
        }
    }

    private func avg(_ f: (Sensor) -> Bool) -> Double {
        let v = m.sensors.filter { $0.valid && f($0) }.map(\.value).filter { !$0.isNaN }
        return v.isEmpty ? .nan : v.reduce(0, +) / Double(v.count)
    }
    private func mx(_ f: (Sensor) -> Bool) -> Double {
        m.sensors.filter { $0.valid && f($0) }.map(\.value).filter { !$0.isNaN }.max() ?? .nan
    }

    private var readouts: some View {
        let smc: (Sensor) -> Bool = { $0.source == "SMC" }
        let cards: [(String, Double, String)] = [
            ("Chip hotspot", mx { $0.placement?.die != nil }, "Hottest die sensor"),
            ("P-cores", avg { smc($0) && $0.placement?.die == .p }, "Average"),
            ("E-cores", avg { smc($0) && $0.placement?.die == .e }, "Average"),
            ("GPU", avg { smc($0) && $0.placement?.die == .gpu }, "Average"),
            ("Power ICs", avg { smc($0) && ($0.key.hasPrefix("TPD") || $0.key.hasPrefix("TRD")) }, "PMU and PMU2"),
            ("Storage", avg { $0.zone == "NAND" }, "NAND flash"),
            ("Battery", avg { smc($0) && $0.zone.hasPrefix("Battery") }, "Cells"),
            ("Palm rest", avg { $0.key == "Ts0P" || $0.key == "Ts1P" }, "Skin temperature"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(cards, id: \.0) { c in
                // fixed 20 to 100 °C scale, so the bars mean the same thing in every view
                let t = c.1.isNaN ? 0 : Swift.min(1, Swift.max(0, (c.1 - 20) / 80))
                VStack(alignment: .leading, spacing: 5) {
                    Text(c.0).font(UI.text(11.5, .medium)).foregroundStyle(UI.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(UI.fmt(c.1)).font(UI.rounded(27, .medium).monospacedDigit())
                            .contentTransition(.numericText(value: c.1.isNaN ? 0 : c.1))
                            .animation(.smooth(duration: 0.5), value: c.1)
                        Text("°").font(UI.rounded(20)).foregroundStyle(UI.secondary)
                    }
                    // position of this reading in the current colour range
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(m.palette.color(0.2 + 0.8 * t)).frame(width: Swift.max(4, g.size.width * t))
                                .animation(.smooth(duration: 0.5), value: t)
                        }
                    }
                    .frame(height: 3)
                    Text(c.2).font(UI.text(10)).foregroundStyle(UI.tertiary).lineLimit(1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }

    private static let zoneOrder = ["SoC", "Heat sink", "Memory", "PMU", "NAND", "Storage", "VDD", "SoC rail", "Regulator", "Charger", "Power", "I/O", "5 V", "Wi-Fi", "Display", "Ambient", "Aux", "Battery", "Gas", "Palm", "Unmapped"]

    private var sensorList: some View {
        func rank(_ z: String) -> Int { Sidebar.zoneOrder.firstIndex { z.hasPrefix($0) } ?? Sidebar.zoneOrder.count }
        let q = query.lowercased()
        let rows = m.sensors
            .filter { q.isEmpty || $0.key.lowercased().contains(q) || $0.zone.lowercased().contains(q) }
            .sorted { (rank($0.zone), $0.zone, $0.source, $0.key) < (rank($1.zone), $1.zone, $1.source, $1.key) }
        var groups: [(String, [Sensor])] = []
        for s in rows {
            if groups.last?.0 == s.zone { groups[groups.count - 1].1.append(s) } else { groups.append((s.zone, [s])) }
        }
        let validN = m.sensors.filter(\.valid).count
        return section("Sensors", detail: "\(validN) live of \(m.sensors.count)") {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(UI.tertiary)
                if ThermalModel.renderMode {   // the headless renderer cannot draw AppKit text fields
                    Text("Search keys or parts").font(UI.text(12)).foregroundStyle(UI.tertiary)
                    Spacer()
                } else {
                    TextField("Search keys or parts", text: $query).textFieldStyle(.plain).font(UI.text(12))
                }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .card(9)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(groups.enumerated()), id: \.element.0) { gi, g in
                    let open = expanded[g.0] ?? (!q.isEmpty || g.1.count <= 8)
                    if !ThermalModel.renderMode || gi < 4 {
                        SensorGroup(m: m, title: g.0, sensors: ThermalModel.renderMode ? Array(g.1.prefix(6)) : g.1, total: g.1.count, open: open) {
                            withAnimation(UI.spring) { expanded[g.0] = !open }
                        }
                    }
                }
            }
        }
    }
}

struct SensorGroup: View {
    @ObservedObject var m: ThermalModel
    let title: String
    let sensors: [Sensor]
    let total: Int
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        let f = m.frame
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(UI.tertiary)
                Text(title).font(UI.text(12, .semibold)).foregroundStyle(UI.primary.opacity(0.85))
                Spacer()
                if !open {
                    let vals = sensors.filter(\.valid).map(\.value).filter { !$0.isNaN }
                    if let lo = vals.min(), let hi = vals.max() {
                        Text(lo == hi ? "\(UI.fmt(lo))°" : "\(UI.fmt(lo, 0))–\(UI.fmt(hi, 0))°").font(UI.rounded(11.5, .medium).monospacedDigit()).foregroundStyle(UI.secondary)
                    }
                }
                Text("\(total)").font(UI.text(10.5, .medium).monospacedDigit()).foregroundStyle(UI.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            .padding(.horizontal, 8).frame(height: 28)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)

            if open {
                VStack(spacing: 0) {
                    ForEach(sensors) { s in SensorRow(m: m, s: s, lo: f.lo, hi: f.hi) }
                }
                .padding(4)
                .card(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct SensorRow: View {
    @ObservedObject var m: ThermalModel
    let s: Sensor
    let lo: Double, hi: Double
    @State private var hover = false
    var body: some View {
        let selected = m.highlighted == s.id
        HStack(spacing: 8) {
            Circle().fill(s.valid ? m.palette.color(0.2 + 0.8 * (s.value - lo) / max(hi - lo, 1)) : Color.white.opacity(0.15))
                .frame(width: 7, height: 7)
            Text(s.key).font(UI.text(12, .medium).monospacedDigit()).lineLimit(1)
            if s.source == "HID" {
                Text("HID").font(UI.text(8.5, .semibold)).foregroundStyle(UI.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            Spacer(minLength: 4)
            if s.valid {
                Text(UI.fmt(s.value) + "°").font(UI.rounded(12.5, .medium).monospacedDigit())
            } else {
                Text(s.raw == nil ? "No data" : "Inactive").font(UI.text(10.5)).foregroundStyle(UI.tertiary)
            }
        }
        .padding(.horizontal, 8).frame(height: 25)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selected ? UI.accent.opacity(0.18) : Color.white.opacity(hover ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { withAnimation(UI.spring) { m.highlighted = selected ? nil : s.id } }
        .help(s.valid ? "\(s.key) (\(s.type)), min \(UI.fmt(s.min))°, max \(UI.fmt(s.max))°" : "\(s.key) (\(s.type)), raw \(s.raw.map { String($0) } ?? "none")")
    }
}

// MARK: - Die inset

struct DieInset: View {
    @ObservedObject var m: ThermalModel
    @ObservedObject private var fs: FrameStore
    init(m: ThermalModel) { _m = ObservedObject(wrappedValue: m); _fs = ObservedObject(wrappedValue: m.frameStore) }
    var body: some View {
        let f = m.frame
        ZStack {
            if let img = f.dieImage {
                Image(decorative: img, scale: 1).resizable().interpolation(.high)
            } else { Color.black }
            Canvas { ctx, size in
                if m.showIsotherms {
                    for c in m.frame.dieContours {
                        var path = Path(); var i = 0
                        while i + 1 < c.segments.count {
                            let a = c.segments[i], b = c.segments[i + 1]
                            path.move(to: CGPoint(x: a.x * size.width, y: a.y * size.height))
                            path.addLine(to: CGPoint(x: b.x * size.width, y: b.y * size.height)); i += 2
                        }
                        ctx.stroke(path, with: .color(.white.opacity(c.major ? 0.5 : 0.22)), style: StrokeStyle(lineWidth: c.major ? 0.8 : 0.45, lineCap: .round))
                    }
                }
                for b in Board.dieBlocks {
                    let r = CGRect(x: b.rect.minX * size.width, y: b.rect.minY * size.height, width: b.rect.width * size.width, height: b.rect.height * size.height)
                    ctx.stroke(Path(roundedRect: r, cornerRadius: 4, style: .continuous), with: .color(.white.opacity(0.4)), lineWidth: 0.6)
                    ctx.draw(Text(Names.die(b.name)).font(UI.text(9.5, .semibold)).foregroundStyle(.white.opacity(0.9)), at: CGPoint(x: r.minX + 5, y: r.minY + 3), anchor: .topLeading)
                }
                for s in m.liveSensors where s.valid {
                    guard let p = m.dieSlot(s.id) else { continue }
                    let v = CGPoint(x: p.x * size.width, y: p.y * size.height)
                    let hl = m.highlighted == s.id
                    let r: CGFloat = hl ? 4 : 1.5
                    ctx.fill(Path(ellipseIn: CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)), with: .color(hl ? UI.accent : .white.opacity(0.65)))
                    if hl {
                        ctx.draw(Text("\(s.key) \(UI.fmt(s.value))°").font(UI.text(10, .semibold)).foregroundStyle(UI.accent), at: CGPoint(x: v.x + 6, y: v.y), anchor: .leading)
                    }
                }
                ctx.draw(Text("\(UI.fmt(f.dieLo, 0)) to \(UI.fmt(f.dieHi, 0))°").font(UI.text(9.5, .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.8)),
                         at: CGPoint(x: size.width - 6, y: size.height - 4), anchor: .bottomTrailing)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 237)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6))
    }
}

// MARK: - History

struct HistoryChart: View {
    let history: [HistoryPoint]
    var body: some View {
        let series: [(String, Color, KeyPath<HistoryPoint, Double>)] = [
            ("Chip", Color(red: 1, green: 0.52, blue: 0.3), \.soc),
            ("Power ICs", Color(red: 1, green: 0.82, blue: 0.4), \.pmu),
            ("Battery", UI.accent, \.battery),
            ("Palm rest", Color(red: 0.72, green: 0.66, blue: 1), \.palm),
        ]
        VStack(alignment: .leading, spacing: 8) {
            Canvas { ctx, size in
                let vals = history.flatMap { h in series.map { h[keyPath: $0.2] } }.filter { !$0.isNaN }
                guard let lo0 = vals.min(), let hi0 = vals.max(), history.count > 1 else { return }
                let lo = floor(lo0 - 1), hi = ceil(hi0 + 1)
                func y(_ v: Double) -> CGFloat { size.height * (1 - (v - lo) / (hi - lo)) }
                func x(_ i: Int) -> CGFloat { size.width * CGFloat(i + 120 - history.count) / 119 }
                for g in stride(from: ceil(lo / 10) * 10, through: hi, by: 10) {
                    var p = Path(); p.move(to: CGPoint(x: 0, y: y(g))); p.addLine(to: CGPoint(x: size.width, y: y(g)))
                    ctx.stroke(p, with: .color(.white.opacity(0.06)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    ctx.draw(Text("\(Int(g))°").font(UI.text(9).monospacedDigit()).foregroundStyle(UI.tertiary), at: CGPoint(x: 4, y: y(g) - 6), anchor: .leading)
                }
                for (idx, (_, col, kp)) in series.enumerated() {
                    let pts: [CGPoint] = history.enumerated().compactMap { i, h in
                        let v = h[keyPath: kp]; return v.isNaN ? nil : CGPoint(x: x(i), y: y(v))
                    }
                    guard pts.count > 1 else { continue }
                    // smooth curve through the samples (midpoint quadratic)
                    var p = Path(); p.move(to: pts[0])
                    for i in 1..<pts.count {
                        let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
                        p.addQuadCurve(to: mid, control: pts[i - 1])
                    }
                    p.addLine(to: pts[pts.count - 1])
                    if idx == 0 {
                        var area = p
                        area.addLine(to: CGPoint(x: pts.last!.x, y: size.height)); area.addLine(to: CGPoint(x: pts[0].x, y: size.height)); area.closeSubpath()
                        ctx.fill(area, with: .linearGradient(Gradient(colors: [col.opacity(0.28), col.opacity(0)]),
                                                             startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
                    }
                    ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    let last = pts[pts.count - 1]
                    ctx.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)), with: .color(col))
                }
            }
            .padding(8)
            .card(12)
            HStack(spacing: 12) {
                ForEach(series, id: \.0) { s in
                    HStack(spacing: 5) {
                        Circle().fill(s.1).frame(width: 6, height: 6)
                        Text(s.0).font(UI.text(10.5)).foregroundStyle(UI.secondary)
                    }
                }
            }
        }
    }
}
