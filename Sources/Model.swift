import Foundation
import CoreGraphics
import SwiftUI
import AppKit

struct Sensor: Identifiable {
    let id: String
    let key: String
    let source: String        // "SMC" or "HID"
    let type: String
    let placement: Placement?
    var raw: Double? = nil
    var value: Double = .nan  // display-smoothed
    var min: Double = .infinity
    var max: Double = -.infinity
    var valid: Bool { raw.map { $0 > 5 && $0 < 130 } ?? false }
    var zone: String { placement?.zone ?? "Unmapped" }
}

enum ViewSide: String, CaseIterable { case bottom = "BOTTOM", top = "TOP" }
enum FieldMode: String, CaseIterable { case internalMode = "INTERNAL", surface = "BOTTOM CASE" }

struct Frame {
    var image: CGImage?
    var grid: [Float] = []           // top-view, 1 mm cells
    var gw = 0, gh = 0
    var lo: Double = 20, hi: Double = 60
    var hotspot = CGPoint.zero       // mm, top view
    var hotValue: Double = 0
    var coldValue: Double = 0
    var contours: [Contour] = []     // chassis isotherms, mm, top view
    var dieContours: [Contour] = []  // die isotherms, unit square
    var dieImage: CGImage?
    var dieLo: Double = 30, dieHi: Double = 80
    var corePeak: Double = .nan
    var ambient: Double = 25
    var serial = 0                   // bumps every field update; the map crossfades between serials
}

/// One isotherm level as line segments (pairs of points), traced with marching squares.
struct Contour { let level: Double; let major: Bool; let segments: [CGPoint] }

enum Isolines {
    static func step(for span: Double) -> Double { span > 40 ? 5 : (span > 16 ? 2 : 1) }

    /// Marching squares over cell-centred samples. Returned points are in grid units where sample (i, j)
    /// sits at (i + 0.5, j + 0.5); callers scale to mm or to the unit die square.
    static func trace(_ g: [Float], gw: Int, gh: Int, lo: Double, hi: Double) -> [Contour] {
        guard gw > 1, gh > 1, hi > lo else { return [] }
        let st = step(for: hi - lo)
        var out: [Contour] = []
        var level = (lo / st).rounded(.up) * st
        while level < hi {
            let L = Float(level)
            var seg: [CGPoint] = []
            seg.reserveCapacity(512)
            for y in 0..<(gh - 1) {
                let r0 = y * gw, r1 = (y + 1) * gw
                for x in 0..<(gw - 1) {
                    let a = g[r0 + x], b = g[r0 + x + 1], c = g[r1 + x + 1], d = g[r1 + x]
                    var idx = 0
                    if a >= L { idx |= 8 }; if b >= L { idx |= 4 }; if c >= L { idx |= 2 }; if d >= L { idx |= 1 }
                    if idx == 0 || idx == 15 { continue }
                    let fx = Double(x) + 0.5, fy = Double(y) + 0.5
                    func t(_ p: Float, _ q: Float) -> Double { Double((L - p) / (q - p)) }
                    let top = CGPoint(x: fx + t(a, b), y: fy)
                    let right = CGPoint(x: fx + 1, y: fy + t(b, c))
                    let bottom = CGPoint(x: fx + t(d, c), y: fy + 1)
                    let left = CGPoint(x: fx, y: fy + t(a, d))
                    switch idx {
                    case 1, 14: seg += [left, bottom]
                    case 2, 13: seg += [bottom, right]
                    case 3, 12: seg += [left, right]
                    case 4, 11: seg += [top, right]
                    case 6, 9: seg += [top, bottom]
                    case 7, 8: seg += [left, top]
                    case 5, 10:
                        // saddle: decide by the cell-centre average
                        let centreHigh = (a + b + c + d) / 4 >= L
                        if (idx == 5) == centreHigh { seg += [left, top, bottom, right] }
                        else { seg += [left, bottom, top, right] }
                    default: break
                    }
                }
            }
            let major = abs(level.remainder(dividingBy: st * 5)) < 0.001 || (st >= 5 && abs(level.remainder(dividingBy: 10)) < 0.001)
            if !seg.isEmpty { out.append(Contour(level: level, major: major, segments: seg)) }
            level += st
        }
        return out
    }
}

final class FrameStore: ObservableObject { @Published var frame = Frame() }

struct HistoryPoint { var soc: Double; var pmu: Double; var battery: Double; var palm: Double }

final class ThermalModel: ObservableObject {
    nonisolated(unsafe) static var renderMode = false
    /// This Mac's model identifier (THERMALMAP_FAKE_MODEL overrides it, to test the notice).
    static let hwModel: String = {
        if let f = ProcessInfo.processInfo.environment["THERMALMAP_FAKE_MODEL"] { return f }
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }()
    /// THERMALMAP_ALWAYS_RENDER=1 keeps the map updating while the window is hidden (flicker tests).
    static let alwaysRender = ProcessInfo.processInfo.environment["THERMALMAP_ALWAYS_RENDER"] == "1"
    // sidebar data (2 Hz)
    @Published var sensors: [Sensor] = []
    @Published var history: [HistoryPoint] = []
    // map data: its own store so only the map views redraw on every field update
    let frameStore = FrameStore()
    var frame: Frame { frameStore.frame }
    // settings
    @Published var side: ViewSide = .bottom
    @Published var mode: FieldMode = .internalMode
    @Published var palette: Palette = .ironbow
    @Published var autoRange = true
    @Published var showParts = true
    @Published var showSensors = true
    @Published var showLabels = false
    @Published var showIsotherms = true
    @Published var highlighted: String? = nil

    private(set) var smcKeyCount = 0
    private(set) var smcTempCount = 0
    private(set) var hidCount = 0
    var sampleCount = 0
    var lastSampleMs: Double = 0

    private var smc: SMC?
    private var hid = HIDThermal()
    private var smcKeys: [String: SMC.Key] = [:]
    private var hidServices: [String: HIDThermal.Service] = [:]
    private let ioQueue = DispatchQueue(label: "thermal.io", qos: .utility)
    private var sampleTimer: Timer?
    private var frameTimer: Timer?
    private var smoothLo = 25.0, smoothHi = 60.0
    private var dieSlots: [String: CGPoint] = [:]
    private var deadStreak: [String: Int] = [:]
    private let solver = HeatSolver()

    init() {
        smc = SMC()
        var list: [Sensor] = []
        if let smc {
            smcKeyCount = smc.totalKeys
            smcTempCount = smc.tempKeys.count
            for k in smc.tempKeys {
                smcKeys[k.name] = k
                list.append(Sensor(id: "smc:" + k.name, key: k.name, source: "SMC", type: k.type.trimmingCharacters(in: .whitespaces),
                                   placement: SensorMap.place(smc: k.name)))
            }
        }
        for s in hid.list {
            hidServices[s.id] = s
            list.append(Sensor(id: s.id, key: s.name, source: "HID", type: "event", placement: SensorMap.place(hid: s.name)))
        }
        hidCount = hid.list.count
        sensors = list
        layoutDie()
    }

    func start() {
        sample()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.sample() }
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 5.0, repeats: true) { [weak self] _ in self?.tickFrame() }
        RunLoop.main.add(sampleTimer!, forMode: .common)
        RunLoop.main.add(frameTimer!, forMode: .common)
    }

    // MARK: sampling

    private func sample() {
        // keys that never returned a usable value in their first 5 reads are only re-checked every 30 s
        let recheck = sampleCount % 30 == 0
        let ids = sensors.filter { recheck || deadStreak[$0.id, default: 0] < 5 }.map { ($0.id, $0.source, $0.key) }
        ioQueue.async { [weak self] in
            guard let self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            var values: [String: Double] = [:]
            for (id, src, key) in ids {
                if src == "SMC", let k = self.smcKeys[key], let v = self.smc?.read(k) { values[id] = v }
                else if src == "HID", let s = self.hidServices[id], let v = self.hid.read(s) { values[id] = v }
            }
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            let readIDs = Set(ids.map { $0.0 })
            DispatchQueue.main.async { self.apply(values, readIDs: readIDs, ms: ms) }
        }
    }

    private func apply(_ values: [String: Double], readIDs: Set<String>, ms: Double) {
        lastSampleMs = ms
        sampleCount += 1
        for i in sensors.indices {
            let id = sensors[i].id
            guard readIDs.contains(id) else { continue }   // skipped dead key: keep its last state
            let v = values[id]
            if v.map({ $0 > 5 && $0 < 130 }) ?? false { deadStreak[id] = 0 } else { deadStreak[id, default: 0] += 1 }
            sensors[i].raw = v
            if sensors[i].valid, let v {
                if i < _sensorsSilent.count, !_sensorsSilent[i].value.isNaN { sensors[i].value = _sensorsSilent[i].value }
                else { sensors[i].value = v }
                sensors[i].min = Swift.min(sensors[i].min, v)
                sensors[i].max = Swift.max(sensors[i].max, v)
            }
        }
        func avg(_ f: (Sensor) -> Bool) -> Double {
            let v = sensors.filter { $0.valid && f($0) }.compactMap(\.raw)
            return v.isEmpty ? .nan : v.reduce(0, +) / Double(v.count)
        }
        let soc = sensors.filter { $0.valid && $0.placement?.die != nil }.compactMap(\.raw).max() ?? .nan
        history.append(HistoryPoint(soc: soc,
                                    pmu: avg { $0.source == "SMC" && $0.key.hasPrefix("TPD") },
                                    battery: avg { $0.source == "SMC" && $0.zone.hasPrefix("Battery") },
                                    palm: avg { $0.key == "Ts0P" || $0.key == "Ts1P" }))
        if history.count > 120 { history.removeFirst(history.count - 120) }
    }

    // MARK: per-frame smoothing + field

    private func tickFrame() {
        // no visible window (minimised, hidden, fully covered): skip the field work entirely
        if !ThermalModel.renderMode && !ThermalModel.alwaysRender && !NSApp.windows.contains(where: { $0.isVisible && $0.occlusionState.contains(.visible) }) { return }
        // exponential approach toward the latest raw sample gives smooth, continuous motion between 2 Hz samples
        if _sensorsSilent.count != sensors.count { _sensorsSilent = sensors }
        var current = _sensorsSilent
        for i in current.indices {
            current[i].raw = sensors[i].raw
            current[i].min = sensors[i].min
            current[i].max = sensors[i].max
            if current[i].valid && current[i].value.isNaN { current[i].value = current[i].raw! }
        }
        for i in current.indices where current[i].valid {
            let r = current[i].raw!
            current[i].value += (r - current[i].value) * 0.45
        }
        // write back without triggering a sidebar re-render every frame
        _sensorsSilent = current
        var f = computeFrame(current)
        frameSerial += 1
        f.serial = frameSerial
        // glide the hotspot marker instead of letting it hop between grid cells; snap on a real jump
        if smoothHot == nil || hypot(f.hotspot.x - smoothHot!.x, f.hotspot.y - smoothHot!.y) > 25 { smoothHot = f.hotspot }
        else { smoothHot!.x += (f.hotspot.x - smoothHot!.x) * 0.3; smoothHot!.y += (f.hotspot.y - smoothHot!.y) * 0.3 }
        f.hotspot = smoothHot!
        // no animation transaction here: images swapped inside one crossfade both at half opacity, which
        // let the background show through (a 5 Hz blink). The map crossfades itself, see CrossfadeField.
        frameStore.frame = f
    }
    private var _sensorsSilent: [Sensor] = []
    private var frameSerial = 0
    private var smoothHot: CGPoint?
    var liveSensors: [Sensor] { _sensorsSilent.isEmpty ? sensors : _sensorsSilent }

    private func layoutDie() {
        let regions: [DieRegion] = [.p, .e, .gpu]
        for r in regions {
            guard let block = Board.dieBlocks.first(where: { $0.name == r.rawValue })?.rect else { continue }
            let members = sensors.filter { $0.source == "SMC" && $0.placement?.die == r }.map(\.id).sorted()
            let n = members.count
            guard n > 0 else { continue }
            let aspect = block.width / block.height
            let cols = Swift.max(1, Int((Double(n) * aspect).squareRoot().rounded(.up)))
            let rows = Int((Double(n) / Double(cols)).rounded(.up))
            // keep the top band of each block free for its label
            let top = block.minY + Swift.min(0.07, block.height * 0.3), hgt = block.maxY - top
            for (i, id) in members.enumerated() {
                let c = i % cols, rr = i / cols
                dieSlots[id] = CGPoint(x: block.minX + block.width * (Double(c) + 0.5) / Double(cols),
                                       y: top + hgt * (Double(rr) + 0.5) / Double(rows))
            }
        }
    }
    func dieSlot(_ id: String) -> CGPoint? { dieSlots[id] }


    /// Every in-field sensor pinned at the spot it measures, plus the die held at the mean of its sensors.
    static func buildPins(_ valid: [Sensor]) -> (pins: [HeatSolver.Pin], ambient: Double, corePeak: Double) {
        var pins: [HeatSolver.Pin] = []
        // TAOL / TVA0 read air, not a part: they set the ambient instead of pinning a spot
        for v in valid where v.placement?.inField == true && v.key != "TAOL" && v.key != "TVA0" {
            pins.append(HeatSolver.Pin(at: v.placement!.point, radius: 1.5, t: v.value, key: v.key))
        }
        let dieVals = valid.filter { $0.placement?.die != nil && $0.source == "SMC" }.map(\.value)
        if !dieVals.isEmpty {
            // the M3 die (~11 x 12 mm) is held at the mean of its 80 sensors
            pins.append(HeatSolver.Pin(at: Board.dieCenter, radius: 5.5, t: dieVals.reduce(0, +) / Double(dieVals.count), key: "die"))
        }
        let fieldVals = pins.map(\.t).sorted()
        let ambient: Double
        if let a = valid.first(where: { $0.key == "TAOL" })?.value { ambient = Swift.min(a, (fieldVals.first ?? a) - 0.5) }
        else { ambient = (fieldVals.first ?? 25) - 2 }
        return (pins, ambient, dieVals.max() ?? .nan)
    }
    private var lastSolve: Double?

    private func computeFrame(_ s: [Sensor]) -> Frame {
        var f = Frame()
        let gw = Int(Board.width.rounded()), gh = Int(Board.depth)
        f.gw = gw; f.gh = gh
        let valid = s.filter { $0.valid && !$0.value.isNaN }
        guard !valid.isEmpty else { return f }

        let (pins, ambient, corePeak) = ThermalModel.buildPins(valid)
        f.corePeak = corePeak
        f.ambient = ambient
        let now = CFAbsoluteTimeGetCurrent()
        solver.solve(pins: pins, ambient: ambient, dt: lastSolve.map { now - $0 })
        lastSolve = now
        let grid = solver.resample(caseLayer: mode == .surface, gw: gw, gh: gh)
        let n = gw * gh
        var hi: Float = -999, lo: Float = 999, hiIdx = 0
        for i in 0..<n {
            let v = grid[i]
            if v > hi { hi = v; hiIdx = i }
            if v < lo { lo = v }
        }
        f.grid = grid
        f.hotspot = CGPoint(x: Double(hiIdx % gw) + 0.5, y: Double(hiIdx / gw) + 0.5)
        f.hotValue = Double(hi); f.coldValue = Double(lo)

        if autoRange {
            smoothLo += (Double(lo) - 1 - smoothLo) * 0.08
            smoothHi += (Swift.max(Double(hi) + 1, smoothLo + 8) - smoothHi) * 0.08
            f.lo = smoothLo; f.hi = smoothHi
        } else { f.lo = 20; f.hi = 100 }

        f.image = colorize(grid, gw: gw, gh: gh, lo: f.lo, hi: f.hi, mirror: side == .bottom, isotherms: false)
        if showIsotherms { f.contours = Isolines.trace(grid, gw: gw, gh: gh, lo: f.lo, hi: f.hi) }
        computeDie(valid, &f)
        return f
    }

    private func computeDie(_ valid: [Sensor], _ f: inout Frame) {
        let gw = 160, gh = 120
        let pts: [(CGPoint, Double)] = valid.compactMap { s in dieSlots[s.id].map { ($0, s.value) } }
        guard !pts.isEmpty else { return }
        let lo = pts.map(\.1).min()!, hi = pts.map(\.1).max()!
        // separable Gaussian weights: exp(-(dx^2+dy^2)/2s^2) = ex(x) * ey(y)
        let sigma: Float = 0.085, inv = 1 / (2 * sigma * sigma)
        var num = [Float](repeating: 0, count: gw * gh), den = [Float](repeating: 0, count: gw * gh)
        var ex = [Float](repeating: 0, count: gw), ey = [Float](repeating: 0, count: gh)
        for (p, t) in pts {
            for x in 0..<gw { let d = (Float(x) + 0.5) / Float(gw) - Float(p.x); ex[x] = expf(-d * d * inv) }
            for y in 0..<gh { let d = ((Float(y) + 0.5) / Float(gh) - Float(p.y)) * 0.75; ey[y] = expf(-d * d * inv) }
            let tf = Float(t)
            for y in 0..<gh {
                let wy = ey[y]; if wy < 1e-6 { continue }
                let row = y * gw
                for x in 0..<gw { let w = wy * ex[x]; num[row + x] += w * tf; den[row + x] += w }
            }
        }
        let lof = Float(lo)
        var grid = [Float](repeating: 0, count: gw * gh)
        for i in 0..<(gw * gh) { grid[i] = (num[i] + 0.02 * lof) / (den[i] + 0.02) }
        f.dieLo = lo - 1; f.dieHi = Swift.max(hi + 1, lo + 10)
        f.dieImage = colorize(grid, gw: gw, gh: gh, lo: f.dieLo, hi: f.dieHi, mirror: false, isotherms: false)
        if showIsotherms {
            f.dieContours = Isolines.trace(grid, gw: gw, gh: gh, lo: f.dieLo, hi: f.dieHi).map { c in
                Contour(level: c.level, major: c.major, segments: c.segments.map { CGPoint(x: $0.x / Double(gw), y: $0.y / Double(gh)) })
            }
        }
    }

    private func colorize(_ grid: [Float], gw: Int, gh: Int, lo: Double, hi: Double, mirror: Bool, isotherms: Bool) -> CGImage? {
        let lut = palette.lut
        var px = [UInt8](repeating: 255, count: gw * gh * 4)
        let span = Float(Swift.max(hi - lo, 0.1)), l = Float(lo)
        let step: Float = span > 40 ? 5 : (span > 16 ? 2 : 1)
        for y in 0..<gh {
            for x in 0..<gw {
                let v = grid[y * gw + x]
                let tn = Swift.min(Swift.max((v - l) / span, 0), 1)
                let c = lut[Int(tn * 255)]
                var r = Float(c.0), gg = Float(c.1), b = Float(c.2)
                if isotherms {
                    // anti-aliased contour: distance (in cells) to the nearest band edge, via the local gradient
                    let xl = grid[y * gw + Swift.max(x - 1, 0)], xr = grid[y * gw + Swift.min(x + 1, gw - 1)]
                    let yu = grid[Swift.max(y - 1, 0) * gw + x], yd = grid[Swift.min(y + 1, gh - 1) * gw + x]
                    let g = Swift.max(sqrtf((xr - xl) * (xr - xl) + (yd - yu) * (yd - yu)) * 0.5, 1e-4)
                    let q = v / step
                    let fr = q - floorf(q)
                    let d = Swift.min(fr, 1 - fr) * step / g
                    let a = Swift.max(0, 1 - d / 0.7) * 0.6
                    if a > 0 { r += (235 - r) * a; gg += (235 - gg) * a; b += (235 - b) * a }
                }
                let ox = mirror ? gw - 1 - x : x
                let o = (y * gw + ox) * 4
                px[o] = UInt8(Swift.min(r, 255)); px[o + 1] = UInt8(Swift.min(gg, 255)); px[o + 2] = UInt8(Swift.min(b, 255))
            }
        }
        let data = Data(px) as CFData
        guard let prov = CGDataProvider(data: data) else { return nil }
        return CGImage(width: gw, height: gh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: gw * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Temperature at a top-view mm coordinate (nearest cell).
    func value(atTop p: CGPoint) -> Double? {
        let f = frame
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < f.gw, y < f.gh, !f.grid.isEmpty else { return nil }
        return Double(f.grid[y * f.gw + x])
    }
}

// MARK: - Palettes

enum Palette: String, CaseIterable {
    case ironbow = "IRONBOW", rainbow = "RAINBOW HC", arctic = "ARCTIC", white = "WHITE HOT"

    var stops: [(Double, (Double, Double, Double))] {
        switch self {
        case .ironbow: return [(0, (0, 0, 10)), (0.12, (30, 0, 90)), (0.28, (110, 0, 150)), (0.45, (190, 20, 120)),
                               (0.6, (235, 80, 40)), (0.75, (252, 150, 0)), (0.9, (255, 220, 60)), (1, (255, 255, 235))]
        case .rainbow: return [(0, (10, 0, 60)), (0.15, (20, 40, 200)), (0.32, (0, 170, 230)), (0.48, (40, 210, 90)),
                               (0.64, (240, 230, 30)), (0.8, (250, 120, 0)), (0.92, (230, 20, 20)), (1, (255, 230, 230))]
        case .arctic: return [(0, (5, 15, 50)), (0.25, (20, 70, 160)), (0.5, (60, 170, 230)), (0.7, (200, 235, 255)),
                              (0.85, (255, 190, 120)), (1, (255, 90, 40))]
        case .white: return [(0, (0, 0, 0)), (1, (255, 255, 255))]
        }
    }
    var lut: [(UInt8, UInt8, UInt8)] {
        if let c = Palette.cache[self] { return c }
        var out: [(UInt8, UInt8, UInt8)] = []
        let s = stops
        for i in 0..<256 {
            let t = Double(i) / 255
            var j = 0
            while j < s.count - 2 && t > s[j + 1].0 { j += 1 }
            let (t0, c0) = s[j], (t1, c1) = s[j + 1]
            let k = Swift.max(0, Swift.min(1, (t - t0) / (t1 - t0)))
            out.append((UInt8(c0.0 + (c1.0 - c0.0) * k), UInt8(c0.1 + (c1.1 - c0.1) * k), UInt8(c0.2 + (c1.2 - c0.2) * k)))
        }
        Palette.cache[self] = out
        return out
    }
    nonisolated(unsafe) static var cache: [Palette: [(UInt8, UInt8, UInt8)]] = [:]
    func color(_ t: Double) -> Color {
        let c = lut[Int(Swift.max(0, Swift.min(1, t)) * 255)]
        return Color(red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255)
    }
}
