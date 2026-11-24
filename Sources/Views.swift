import SwiftUI

enum UI {
    static let bg = Color(red: 0.035, green: 0.039, blue: 0.047)
    static let panel = Color(red: 0.067, green: 0.074, blue: 0.086)
    static let line = Color.white.opacity(0.09)
    static let dim = Color.white.opacity(0.48)
    static let faint = Color.white.opacity(0.28)
    static let accent = Color(red: 0.36, green: 0.86, blue: 1.0)
    static func mono(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .monospaced) }
    static func fmt(_ v: Double, _ d: Int = 1) -> String { v.isNaN ? "--" : String(format: "%.\(d)f", v) }
}

// MARK: - Root

struct ContentView: View {
    @ObservedObject var m: ThermalModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Header(m: m)
                Divider().overlay(UI.line)
                ChassisView(m: m)
                Legend(m: m).padding(.horizontal, 22).padding(.bottom, 16)
            }
            Divider().overlay(UI.line)
            Sidebar(m: m).frame(width: 360)
        }
        .background(UI.bg)
        .foregroundStyle(.white)
        .frame(minWidth: 1180, minHeight: 760)
    }
}

// MARK: - Controls

struct Seg<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var sel: T
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { o in
                Text(label(o))
                    .font(UI.mono(9.5, .medium))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(sel == o ? Color.white.opacity(0.13) : Color.clear)
                    .foregroundStyle(sel == o ? Color.white : UI.dim)
                    .contentShape(Rectangle())
                    .onTapGesture { sel = o }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.12)))
    }
}

struct Chip: View {
    let title: String
    @Binding var on: Bool
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(on ? UI.accent : Color.white.opacity(0.2)).frame(width: 5, height: 5)
            Text(title).font(UI.mono(9.5, .medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .foregroundStyle(on ? Color.white : UI.dim)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(on ? 0.08 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.1)))
        .contentShape(Rectangle())
        .onTapGesture { on.toggle() }
    }
}

// MARK: - Header

struct Header: View {
    @ObservedObject var m: ThermalModel
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                        .shadow(color: .red, radius: 4)
                        .opacity(m.sampleCount % 2 == 0 ? 1 : 0.35)
                    Text("THERMAL MAP").font(UI.mono(13, .bold)).tracking(2)
                    Text("LIVE").font(UI.mono(9, .bold)).foregroundStyle(.red)
                }
                Text("MacBook Air 13\" · M3 · Mac15,12 · \(m.side == .bottom ? "bottom case, IR-camera view" : "top, X-ray through keyboard")")
                    .font(UI.mono(9.5)).foregroundStyle(UI.dim)
            }
            Spacer()
            Seg(options: ViewSide.allCases, label: { $0.rawValue }, sel: $m.side)
            Seg(options: FieldMode.allCases, label: { $0.rawValue }, sel: $m.mode)
            Seg(options: Palette.allCases, label: { $0.rawValue }, sel: $m.palette)
        }
        .padding(.horizontal, 22).padding(.vertical, 13)
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
            let pad: CGFloat = 52
            let s = min((geo.size.width - pad * 2) / Board.width, (geo.size.height - pad * 2) / Board.depth)
            let w = Board.width * s, h = Board.depth * s
            let ox = (geo.size.width - w) / 2, oy = (geo.size.height - h) / 2
            let mirror = m.side == .bottom
            let map = Mapper(s: s, ox: ox, oy: oy, mirror: mirror)

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in drawBackdrop(ctx, size, map) }
                if let img = m.frame.image {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: Board.corner * s, style: .continuous))
                        .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
                        .offset(x: ox, y: oy)
                }
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

    private func drawBackdrop(_ ctx: GraphicsContext, _ size: CGSize, _ map: Mapper) {
        // engineering grid, 10 mm
        var grid = Path()
        let step = 10 * map.s
        var x = map.ox.truncatingRemainder(dividingBy: step)
        while x < size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += step }
        var y = map.oy.truncatingRemainder(dividingBy: step)
        while y < size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += step }
        ctx.stroke(grid, with: .color(.white.opacity(0.035)), lineWidth: 0.5)

        // rulers
        let w = Board.width * map.s, h = Board.depth * map.s
        var ticks = Path()
        for mm in stride(from: 0, through: Int(Board.width), by: 10) {
            let px = map.ox + CGFloat(mm) * map.s
            let len: CGFloat = mm % 50 == 0 ? 9 : 4
            ticks.move(to: CGPoint(x: px, y: map.oy - 14)); ticks.addLine(to: CGPoint(x: px, y: map.oy - 14 - len))
            if mm % 50 == 0 {
                ctx.draw(Text("\(mm)").font(UI.mono(8)).foregroundStyle(UI.faint), at: CGPoint(x: px, y: map.oy - 30))
            }
        }
        for mm in stride(from: 0, through: Int(Board.depth), by: 10) {
            let py = map.oy + CGFloat(mm) * map.s
            let len: CGFloat = mm % 50 == 0 ? 9 : 4
            ticks.move(to: CGPoint(x: map.ox - 14, y: py)); ticks.addLine(to: CGPoint(x: map.ox - 14 - len, y: py))
            if mm % 50 == 0 {
                ctx.draw(Text("\(mm)").font(UI.mono(8)).foregroundStyle(UI.faint), at: CGPoint(x: map.ox - 36, y: py))
            }
        }
        ctx.stroke(ticks, with: .color(.white.opacity(0.3)), lineWidth: 0.7)
        ctx.draw(Text("304.1 mm").font(UI.mono(8.5)).foregroundStyle(UI.dim), at: CGPoint(x: map.ox + w / 2, y: map.oy + h + 18))
        ctx.draw(Text("215 mm").font(UI.mono(8.5)).foregroundStyle(UI.dim), at: CGPoint(x: map.ox + w + 26, y: map.oy + h / 2))
    }

    private func drawOverlay(_ ctx: GraphicsContext, _ size: CGSize, _ map: Mapper) {
        let s = map.s
        let chassis = CGRect(x: map.ox, y: map.oy, width: Board.width * s, height: Board.depth * s)
        let shell = Path(roundedRect: chassis, cornerRadius: Board.corner * s, style: .continuous)
        ctx.stroke(shell, with: .color(.white.opacity(0.55)), lineWidth: 1.2)
        ctx.stroke(Path(roundedRect: chassis.insetBy(dx: 3, dy: 3), cornerRadius: Board.corner * s - 3, style: .continuous),
                   with: .color(.white.opacity(0.08)), lineWidth: 0.6)

        // hinge band
        var hinge = Path(); hinge.addRect(CGRect(x: chassis.minX + 22 * s, y: chassis.minY, width: chassis.width - 44 * s, height: 3.5 * s))
        ctx.stroke(hinge, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
        ctx.draw(Text("HINGE").font(UI.mono(8, .medium)).foregroundStyle(UI.dim), at: CGPoint(x: chassis.midX, y: chassis.minY - 8))
        ctx.draw(Text("FRONT · LIP").font(UI.mono(8, .medium)).foregroundStyle(UI.dim), at: CGPoint(x: chassis.midX, y: chassis.maxY + 32))

        if m.showIsotherms && !m.frame.contours.isEmpty {
            var clipped = ctx
            clipped.clip(to: shell)
            for c in m.frame.contours {
                var path = Path()
                var i = 0
                let segs = c.segments
                while i + 1 < segs.count {
                    path.move(to: map.pt(segs[i])); path.addLine(to: map.pt(segs[i + 1])); i += 2
                }
                clipped.stroke(path, with: .color(.white.opacity(c.major ? 0.62 : 0.30)),
                               style: StrokeStyle(lineWidth: c.major ? 1.0 : 0.6, lineCap: .round))
            }
            // label each major isotherm once, at its segment nearest the board's horizontal centre line
            for c in m.frame.contours where c.major {
                var best = CGPoint.zero
                var bestScore = CGFloat.greatestFiniteMagnitude
                var k = 0
                while k < c.segments.count {
                    let q = c.segments[k]
                    let dy: CGFloat = abs(q.y - 105)
                    let dx: CGFloat = abs(q.x - 152) * 0.2
                    if dy + dx < bestScore { bestScore = dy + dx; best = q }
                    k += 2
                }
                let v: CGPoint = map.pt(best)
                let lbl = clipped.resolve(Text("\(Int(c.level))°").font(UI.mono(7.5, .semibold)).foregroundStyle(.white.opacity(0.9)))
                let sz: CGSize = lbl.measure(in: CGSize(width: 60, height: 20))
                let box = CGRect(x: v.x - sz.width / 2 - 2, y: v.y - sz.height / 2 - 1, width: sz.width + 4, height: sz.height + 2)
                clipped.fill(Path(roundedRect: box, cornerRadius: 2), with: .color(.black.opacity(0.55)))
                clipped.draw(lbl, at: v)
            }
        }

        if m.showParts {
            for p in Board.parts {
                let r = map.rect(p.rect)
                let path = Path(roundedRect: r, cornerRadius: p.kind == .chip ? 1.5 : 4)
                switch p.kind {
                case .battery: ctx.stroke(path, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 0.7, dash: [4, 3]))
                case .trackpad: ctx.stroke(path, with: .color(.white.opacity(0.2)), lineWidth: 0.7)
                case .board: ctx.stroke(path, with: .color(.white.opacity(0.32)), lineWidth: 0.9)
                case .chip: ctx.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 0.9)
                case .module, .port: ctx.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 0.7)
                case .sink: ctx.stroke(path, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 0.8, dash: [6, 2, 1, 2]))
                }
                if p.kind != .port {
                    let t = Text(p.name).font(UI.mono(p.kind == .chip ? 7.5 : 8, .medium)).foregroundStyle(.white.opacity(p.kind == .chip ? 0.85 : 0.5))
                    if p.kind == .sink { ctx.draw(t, at: CGPoint(x: r.minX + 3, y: r.maxY - 2), anchor: .bottomLeading) }
                    else { ctx.draw(t, at: CGPoint(x: r.minX + 3, y: r.minY + 2), anchor: .topLeading) }
                }
            }
            if m.side == .bottom {
                for c in [CGPoint(x: 24, y: 20), CGPoint(x: 280, y: 20), CGPoint(x: 24, y: 195), CGPoint(x: 280, y: 195)] {
                    let v = map.pt(c); let r = 5.5 * s
                    ctx.stroke(Path(ellipseIn: CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.3)), lineWidth: 0.8)
                }
            }
        }

        let f = m.frame
        let span = max(f.hi - f.lo, 0.1)
        let live = m.liveSensors

        if m.showSensors {
            for sn in live where sn.valid && sn.placement != nil && sn.placement?.die == nil && !sn.value.isNaN {
                let v = map.pt(sn.placement!.point)
                let col = m.palette.color((sn.value - f.lo) / span)
                let r: CGFloat = sn.source == "HID" ? 2.2 : 3
                let dot = Path(ellipseIn: CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r))
                if sn.source == "HID" {
                    ctx.stroke(dot, with: .color(.white.opacity(0.75)), lineWidth: 0.8)
                } else {
                    ctx.fill(dot, with: .color(col))
                    ctx.stroke(dot, with: .color(.black.opacity(0.8)), lineWidth: 0.8)
                }
                if m.showLabels && sn.source == "SMC" {
                    ctx.draw(Text("\(sn.key) \(UI.fmt(sn.value))").font(UI.mono(7)).foregroundStyle(.white.opacity(0.85)),
                             at: CGPoint(x: v.x + 5, y: v.y), anchor: .leading)
                }
            }
            // SoC die marker: aggregate of every die sensor
            let dieN = live.filter { $0.valid && $0.placement?.die != nil }.count
            let dc = map.pt(Board.dieCenter)
            ctx.stroke(Path(ellipseIn: CGRect(x: dc.x - 6, y: dc.y - 6, width: 12, height: 12)), with: .color(.white.opacity(0.9)), lineWidth: 1)
            ctx.draw(Text("\(dieN) die sensors").font(UI.mono(7.5)).foregroundStyle(.white.opacity(0.8)),
                     at: CGPoint(x: dc.x, y: dc.y + 13 + 3 * s), anchor: .top)
        }

        if let hl = m.highlighted, let sn = live.first(where: { $0.id == hl }), let p = sn.placement {
            let v = map.pt(p.point)
            for (rad, a) in [(9.0, 0.95), (15.0, 0.5)] {
                ctx.stroke(Path(ellipseIn: CGRect(x: v.x - rad, y: v.y - rad, width: 2 * rad, height: 2 * rad)), with: .color(UI.accent.opacity(a)), lineWidth: 1.2)
            }
            tag(ctx, "\(sn.key)  \(UI.fmt(sn.value))°C  \(p.zone)", at: CGPoint(x: v.x + 18, y: v.y - 18), color: UI.accent)
        }

        // hotspot
        let hp = map.pt(f.hotspot)
        var cross = Path()
        cross.move(to: CGPoint(x: hp.x - 14, y: hp.y)); cross.addLine(to: CGPoint(x: hp.x - 5, y: hp.y))
        cross.move(to: CGPoint(x: hp.x + 5, y: hp.y)); cross.addLine(to: CGPoint(x: hp.x + 14, y: hp.y))
        cross.move(to: CGPoint(x: hp.x, y: hp.y - 14)); cross.addLine(to: CGPoint(x: hp.x, y: hp.y - 5))
        cross.move(to: CGPoint(x: hp.x, y: hp.y + 5)); cross.addLine(to: CGPoint(x: hp.x, y: hp.y + 14))
        ctx.stroke(cross, with: .color(.white), lineWidth: 1.4)
        let peak = (m.mode == .internalMode && !f.corePeak.isNaN) ? "  ·  core peak \(UI.fmt(f.corePeak))°" : ""
        tag(ctx, "MAX \(UI.fmt(f.hotValue))°C\(peak)", at: CGPoint(x: hp.x + 16, y: hp.y + 16), color: .white)

        // cursor probe
        if let hv = hover {
            let top = map.top(fromView: hv)
            if let t = m.value(atTop: top) {
                var c = Path()
                c.move(to: CGPoint(x: hv.x - 8, y: hv.y)); c.addLine(to: CGPoint(x: hv.x + 8, y: hv.y))
                c.move(to: CGPoint(x: hv.x, y: hv.y - 8)); c.addLine(to: CGPoint(x: hv.x, y: hv.y + 8))
                ctx.stroke(c, with: .color(UI.accent), lineWidth: 1)
                let near = live.filter { $0.valid && $0.placement != nil && $0.source == "SMC" }
                    .min { dist($0.placement!.point, top) < dist($1.placement!.point, top) }
                let nearTxt = near.map { "  ·  near \($0.key) (\($0.zone)) \(UI.fmt($0.value))°" } ?? ""
                tag(ctx, "\(UI.fmt(t))°C   x \(Int(top.x)) y \(Int(top.y)) mm\(nearTxt)", at: CGPoint(x: hv.x + 12, y: hv.y - 22), color: UI.accent)
            }
        }
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func tag(_ ctx: GraphicsContext, _ s: String, at p: CGPoint, color: Color) {
        let t = ctx.resolve(Text(s).font(UI.mono(9, .medium)).foregroundStyle(color))
        let sz = t.measure(in: CGSize(width: 600, height: 40))
        let r = CGRect(x: p.x, y: p.y - sz.height / 2 - 3, width: sz.width + 10, height: sz.height + 6)
        ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(.black.opacity(0.72)))
        ctx.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(color.opacity(0.5)), lineWidth: 0.6)
        ctx.draw(t, at: CGPoint(x: r.minX + 5, y: r.midY), anchor: .leading)
    }
}

// MARK: - Legend

struct Legend: View {
    @ObservedObject var m: ThermalModel
    @ObservedObject private var fs: FrameStore
    init(m: ThermalModel) { _m = ObservedObject(wrappedValue: m); _fs = ObservedObject(wrappedValue: m.frameStore) }
    var body: some View {
        let f = m.frame
        HStack(spacing: 14) {
            Text(UI.fmt(f.lo) + "°").font(UI.mono(10, .medium)).foregroundStyle(UI.dim).frame(width: 44, alignment: .trailing)
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    LinearGradient(stops: (0...16).map { i in
                        Gradient.Stop(color: m.palette.color(Double(i) / 16), location: Double(i) / 16)
                    }, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 9).clipShape(RoundedRectangle(cornerRadius: 2))
                    Canvas { ctx, size in
                        let span = max(f.hi - f.lo, 0.1)
                        let step: Double = span > 40 ? 10 : (span > 16 ? 5 : 2)
                        var v = (f.lo / step).rounded(.up) * step
                        while v <= f.hi {
                            let x = (v - f.lo) / span * size.width
                            var p = Path(); p.move(to: CGPoint(x: x, y: 9)); p.addLine(to: CGPoint(x: x, y: 14))
                            ctx.stroke(p, with: .color(.white.opacity(0.4)), lineWidth: 0.7)
                            ctx.draw(Text("\(Int(v))").font(UI.mono(8)).foregroundStyle(UI.faint), at: CGPoint(x: x, y: 21))
                            v += step
                        }
                    }
                    .frame(width: g.size.width, height: 28)
                }
            }
            .frame(height: 28)
            Text(UI.fmt(f.hi) + "°").font(UI.mono(10, .medium)).foregroundStyle(UI.dim).frame(width: 44, alignment: .leading)
            Chip(title: "AUTO RANGE", on: $m.autoRange)
            Chip(title: "ISOTHERMS", on: $m.showIsotherms)
            Chip(title: "PARTS", on: $m.showParts)
            Chip(title: "SENSORS", on: $m.showSensors)
            Chip(title: "KEYS", on: $m.showLabels)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @ObservedObject var m: ThermalModel
    @State private var query = ""

    var body: some View {
        scroller {
            VStack(alignment: .leading, spacing: 18) {
                readouts
                section("SoC DIE  ·  M3  ·  per-sensor field") { DieInset(m: m) }
                section("HISTORY  ·  last 2 min") { HistoryChart(history: m.history).frame(height: 96) }
                sensorTable
                Text("SMC keys scanned \(m.smcKeyCount)  ·  temperature keys \(m.smcTempCount)  ·  HID thermal services \(m.hidCount)  ·  read \(UI.fmt(m.lastSampleMs)) ms @ 1 Hz, field 5 Hz")
                    .font(UI.mono(8.5)).foregroundStyle(UI.faint)
                Text("Layout calibrated to the Apple Self Service Repair manual for MacBook Air 13-inch M3 (J613), outlines within about 3-5 mm. Every sensor reading is pinned at the part it measures; between them a two-layer steady-state heat-conduction model (2 mm grid, aluminium heat sink, PCB, battery, top case) fills in the field. BOTTOM CASE shows the modelled outer aluminium skin, which is what an IR camera would see.")
                    .font(UI.mono(8.5)).foregroundStyle(UI.faint).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .background(UI.panel)
    }

    @ViewBuilder private func scroller<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        if ThermalModel.renderMode { VStack(spacing: 0) { c(); Spacer(minLength: 0) }.frame(maxHeight: .infinity, alignment: .top).clipped() }
        else { ScrollView { c() } }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(UI.mono(9, .semibold)).tracking(1).foregroundStyle(UI.dim)
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
            ("SoC HOTSPOT", mx { $0.placement?.die != nil }, "max of die"),
            ("P-CLUSTER", avg { smc($0) && $0.placement?.die == .p }, "avg"),
            ("E-CLUSTER", avg { smc($0) && $0.placement?.die == .e }, "avg"),
            ("GPU", avg { smc($0) && $0.placement?.die == .gpu }, "avg"),
            ("PMU / PMU2", avg { smc($0) && ($0.key.hasPrefix("TPD") || $0.key.hasPrefix("TRD")) }, "die avg"),
            ("NAND", avg { $0.zone == "NAND" }, "flash"),
            ("BATTERY", avg { smc($0) && $0.zone.hasPrefix("Battery") }, "cells"),
            ("PALM REST", avg { $0.key == "Ts0P" || $0.key == "Ts1P" }, "skin"),
        ]
        let f = m.frame
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(cards, id: \.0) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.0).font(UI.mono(8.5, .semibold)).foregroundStyle(UI.dim)
                        Spacer()
                        Text(c.2).font(UI.mono(7.5)).foregroundStyle(UI.faint)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(UI.fmt(c.1)).font(UI.mono(21, .semibold))
                            .foregroundStyle(c.1.isNaN ? UI.dim : m.palette.color(0.25 + 0.75 * (c.1 - f.lo) / max(f.hi - f.lo, 1)))
                        Text("°C").font(UI.mono(10)).foregroundStyle(UI.dim)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(UI.line))
            }
        }
    }

    private var sensorTable: some View {
        let order = ["SoC", "Heat sink", "Memory", "PMU", "NAND", "Memory", "Storage", "VDD", "SoC rail", "Regulator", "Charger", "Power", "I/O", "5 V", "Wi-Fi", "Display", "Ambient", "Aux", "Battery", "Gas", "Palm", "Unmapped"]
        func rank(_ z: String) -> Int { order.firstIndex { z.hasPrefix($0) } ?? order.count }
        let q = query.lowercased()
        let rows = m.sensors
            .filter { q.isEmpty || $0.key.lowercased().contains(q) || $0.zone.lowercased().contains(q) }
            .sorted { (rank($0.zone), $0.zone, $0.source, $0.key) < (rank($1.zone), $1.zone, $1.source, $1.key) }
        let validN = m.sensors.filter(\.valid).count
        let f = m.frame
        return section("ALL SENSORS  ·  \(validN) live / \(m.sensors.count) found") {
            TextField("filter  (key or zone, e.g. Tp, battery, PMU)", text: $query)
                .textFieldStyle(.plain).font(UI.mono(10))
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { s in
                    HStack(spacing: 8) {
                        Text(s.source).font(UI.mono(7, .bold))
                            .foregroundStyle(s.source == "SMC" ? UI.accent : Color.orange)
                            .frame(width: 22, alignment: .leading)
                        Text(s.key).font(UI.mono(10, .medium)).lineLimit(1).frame(width: 118, alignment: .leading)
                        Text(s.zone).font(UI.mono(8)).foregroundStyle(UI.faint).lineLimit(1)
                        Spacer(minLength: 4)
                        if s.valid {
                            Text(UI.fmt(s.value)).font(UI.mono(10, .semibold))
                                .foregroundStyle(m.palette.color(0.25 + 0.75 * (s.value - f.lo) / max(f.hi - f.lo, 1)))
                        } else {
                            Text(s.raw == nil ? "n/a" : "inactive").font(UI.mono(8)).foregroundStyle(UI.faint)
                        }
                    }
                    .padding(.vertical, 3.5).padding(.horizontal, 5)
                    .background(m.highlighted == s.id ? UI.accent.opacity(0.14) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { m.highlighted = m.highlighted == s.id ? nil : s.id }
                    .help(s.valid ? "\(s.key) [\(s.type)]  min \(UI.fmt(s.min))  max \(UI.fmt(s.max))" : "\(s.key) [\(s.type)] raw \(s.raw.map { String($0) } ?? "none")")
                }
            }
        }
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
                        ctx.stroke(path, with: .color(.white.opacity(c.major ? 0.55 : 0.28)), lineWidth: c.major ? 0.9 : 0.5)
                    }
                }
                for b in Board.dieBlocks {
                    let r = CGRect(x: b.rect.minX * size.width, y: b.rect.minY * size.height, width: b.rect.width * size.width, height: b.rect.height * size.height)
                    ctx.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(.white.opacity(0.45)), lineWidth: 0.7)
                    ctx.draw(Text(b.name).font(UI.mono(7, .semibold)).foregroundStyle(.white.opacity(0.85)), at: CGPoint(x: r.minX + 3, y: r.minY + 2), anchor: .topLeading)
                }
                for s in m.liveSensors where s.valid {
                    guard let p = m.dieSlot(s.id) else { continue }
                    let v = CGPoint(x: p.x * size.width, y: p.y * size.height)
                    let hl = m.highlighted == s.id
                    let r: CGFloat = hl ? 4 : 1.6
                    ctx.fill(Path(ellipseIn: CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)), with: .color(hl ? UI.accent : .white.opacity(0.7)))
                    if hl {
                        ctx.draw(Text("\(s.key) \(UI.fmt(s.value))°").font(UI.mono(8, .bold)).foregroundStyle(UI.accent), at: CGPoint(x: v.x + 6, y: v.y), anchor: .leading)
                    }
                }
                ctx.draw(Text("\(UI.fmt(f.dieLo, 0))–\(UI.fmt(f.dieHi, 0))°C").font(UI.mono(7.5)).foregroundStyle(.white.opacity(0.8)),
                         at: CGPoint(x: size.width - 4, y: size.height - 3), anchor: .bottomTrailing)
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(UI.line))
    }
}

// MARK: - History

struct HistoryChart: View {
    let history: [HistoryPoint]
    var body: some View {
        let series: [(String, Color, KeyPath<HistoryPoint, Double>)] = [
            ("SoC max", Color(red: 1, green: 0.45, blue: 0.2), \.soc),
            ("PMU", Color(red: 1, green: 0.8, blue: 0.3), \.pmu),
            ("Battery", UI.accent, \.battery),
            ("Palm", Color(red: 0.6, green: 0.6, blue: 1), \.palm),
        ]
        VStack(alignment: .leading, spacing: 5) {
            Canvas { ctx, size in
                let vals = history.flatMap { h in series.map { h[keyPath: $0.2] } }.filter { !$0.isNaN }
                guard let lo0 = vals.min(), let hi0 = vals.max(), history.count > 1 else { return }
                let lo = floor(lo0 - 1), hi = ceil(hi0 + 1)
                for g in stride(from: ceil(lo / 10) * 10, through: hi, by: 10) {
                    let y = size.height * (1 - (g - lo) / (hi - lo))
                    var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(.white.opacity(0.07)), lineWidth: 0.5)
                    ctx.draw(Text("\(Int(g))").font(UI.mono(7)).foregroundStyle(UI.faint), at: CGPoint(x: 2, y: y - 5), anchor: .leading)
                }
                for (_, col, kp) in series {
                    var p = Path(); var started = false
                    for (i, h) in history.enumerated() {
                        let v = h[keyPath: kp]; if v.isNaN { continue }
                        let pt = CGPoint(x: size.width * CGFloat(i + 120 - history.count) / 119, y: size.height * (1 - (v - lo) / (hi - lo)))
                        if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                    }
                    ctx.stroke(p, with: .color(col), lineWidth: 1.3)
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.025)))
            HStack(spacing: 10) {
                ForEach(series, id: \.0) { s in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(s.1).frame(width: 9, height: 2)
                        Text(s.0).font(UI.mono(8)).foregroundStyle(UI.dim)
                    }
                }
            }
        }
    }
}
