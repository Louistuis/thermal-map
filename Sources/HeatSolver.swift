import Foundation
import CoreGraphics

/// Two-layer heat conduction on a 2 mm grid.
///
/// Layer 1 (internal): logic board, heat sink, battery and trackpad sitting on the aluminium top case.
///   k(x,y) is the in-plane sheet conductance of whatever is at that spot; the real sensor readings are
///   held fixed (Dirichlet) at the cells they measure.
/// Layer 2 (bottom case): ~1 mm aluminium sheet. It is coupled to layer 1 by g(x,y) (strong under the heat
///   sink, weak through the air gap over the battery), loses heat to room air by convection, and carries
///   thermal mass, so it lags the internals the way a real bottom case does.
///
///   layer 1:  sum_faces k_f (T_n - T) + g (Tc - T) + h_i (Ta - T) = 0
///   layer 2:  sum_faces kc  (Tc_n - Tc) + g (T - Tc) + h_c (Ta - Tc) = cap (Tc - Tc_prev) / dt
///
/// Solved by red-black SOR, warm-started from the previous frame, so a dozen sweeps per frame keep it
/// converged while readings drift. Constants are relative per-cell values; the internal-layer ones are fitted
/// with a held-out sensor test (Calibrate.swift, `--fit`).
final class HeatSolver {
    struct Params: Codable, Equatable {
        var kBase: Float = 10, kBattery: Float = 12, kTrackpad: Float = 9, kBoard: Float = 30
        var kModule: Float = 14, kChip: Float = 45, kSink: Float = 160
        var gBase: Float = 0.004, gBattery: Float = 0.003, gBoard: Float = 0.006, gModule: Float = 0.006
        var gChip: Float = 0.012, gSink: Float = 0.015
        var hInt: Float = 0.004, hCase: Float = 0.018, kCase: Float = 8
        /// bottom-case time constant against room air in seconds (1 mm aluminium: rho*c*d / h, about 150 s)
        var caseTau: Float = 150
        /// air inside the closed chassis sits above room temperature (display, backlight, board losses)
        var innerAir: Float = 0
    }

    static let dx = 2.0
    let nx = Int((Board.width / HeatSolver.dx).rounded(.up))   // 153
    let ny = Int((Board.depth / HeatSolver.dx).rounded(.up))   // 108
    let params: Params
    private(set) var internalT: [Float]
    private(set) var caseT: [Float]
    private var kE: [Float], kS: [Float]   // face conductance to east / south neighbour (0 at the edge)
    private var g: [Float]
    private var fixed: [Float]             // NaN = free
    private var warm = false
    let kMap: [Float]

    init(_ pr: Params = HeatSolver.fitted) {
        params = pr
        let nx = Int((Board.width / HeatSolver.dx).rounded(.up)), ny = Int((Board.depth / HeatSolver.dx).rounded(.up))
        let n = nx * ny
        var k = [Float](repeating: pr.kBase, count: n)      // bare aluminium top case + keyboard stack
        var gg = [Float](repeating: pr.gBase, count: n)     // air gap to the bottom case
        func paint(_ r: CGRect, _ kv: Float, _ gv: Float) {
            let x0 = max(0, Int(r.minX / HeatSolver.dx)), x1 = min(nx - 1, Int(r.maxX / HeatSolver.dx))
            let y0 = max(0, Int(r.minY / HeatSolver.dx)), y1 = min(ny - 1, Int(r.maxY / HeatSolver.dx))
            guard x0 <= x1, y0 <= y1 else { return }
            for y in y0...y1 { for x in x0...x1 { k[y * nx + x] = kv; gg[y * nx + x] = gv } }
        }
        // order matters: later parts sit on top
        for p in Board.parts where p.kind == .battery { paint(p.rect, pr.kBattery, pr.gBattery) }
        for p in Board.parts where p.kind == .trackpad { paint(p.rect, pr.kTrackpad, pr.gBattery) }
        for p in Board.parts where p.kind == .board { paint(p.rect, pr.kBoard, pr.gBoard) }
        for p in Board.parts where p.kind == .module { paint(p.rect, pr.kModule, pr.gModule) }
        for p in Board.parts where p.kind == .chip { paint(p.rect, pr.kChip, pr.gChip) }
        for p in Board.parts where p.kind == .sink { paint(p.rect, pr.kSink, pr.gSink) }
        kMap = k
        g = gg
        // harmonic-mean face conductances
        kE = [Float](repeating: 0, count: n); kS = [Float](repeating: 0, count: n)
        for y in 0..<ny {
            for x in 0..<nx {
                let i = y * nx + x
                if x + 1 < nx { let a = k[i], b = k[i + 1]; kE[i] = 2 * a * b / (a + b) / 4 }
                if y + 1 < ny { let a = k[i], b = k[i + nx]; kS[i] = 2 * a * b / (a + b) / 4 }
            }
        }
        internalT = [Float](repeating: 25, count: n)
        caseT = [Float](repeating: 25, count: n)
        fixed = [Float](repeating: .nan, count: n)
    }

    struct Pin: Codable { var at: CGPoint; var radius: Double; var t: Double; var key: String = "" }

    /// `dt`: seconds since the previous solve. A short real step keeps the bottom case's thermal mass
    /// (implicit Euler, unconditionally stable); nil or a gap over 5 s solves the steady state.
    func solve(pins: [Pin], ambient: Double, dt: Double? = nil, sweeps forced: Int? = nil) {
        let n = nx * ny
        // rebuild the fixed-temperature mask (several pins on one cell average)
        var sum = [Float](repeating: 0, count: n), cnt = [Float](repeating: 0, count: n)
        for p in pins {
            let r = max(p.radius, HeatSolver.dx * 0.75)
            let cx = p.at.x / HeatSolver.dx - 0.5, cy = p.at.y / HeatSolver.dx - 0.5
            let rc = r / HeatSolver.dx
            let x0 = max(0, Int((cx - rc).rounded(.down))), x1 = min(nx - 1, Int((cx + rc).rounded(.up)))
            let y0 = max(0, Int((cy - rc).rounded(.down))), y1 = min(ny - 1, Int((cy + rc).rounded(.up)))
            var hit = false
            if x0 <= x1 && y0 <= y1 {
                for y in y0...y1 { for x in x0...x1 where hypot(Double(x) - cx, Double(y) - cy) <= rc {
                    sum[y * nx + x] += Float(p.t); cnt[y * nx + x] += 1; hit = true
                } }
            }
            if !hit {
                let x = min(nx - 1, max(0, Int(cx.rounded()))), y = min(ny - 1, max(0, Int(cy.rounded())))
                sum[y * nx + x] += Float(p.t); cnt[y * nx + x] += 1
            }
        }
        for i in 0..<n { fixed[i] = cnt[i] > 0 ? sum[i] / cnt[i] : .nan }

        let ta = Float(ambient)
        if !warm {
            for i in 0..<n { internalT[i] = ta + 5; caseT[i] = ta + 3 }
        }
        let transient = warm && (dt.map { $0 > 0 && $0 < 5 } ?? false)
        let cap: Float = transient ? params.hCase * params.caseTau / Float(dt!) : 0
        let cOld = caseT
        let sweeps = forced ?? (warm ? 12 : 600)
        warm = true
        let w: Float = 1.82
        internalT.withUnsafeMutableBufferPointer { T in
        caseT.withUnsafeMutableBufferPointer { C in
        kE.withUnsafeBufferPointer { kE in
        kS.withUnsafeBufferPointer { kS in
        g.withUnsafeBufferPointer { g in
        fixed.withUnsafeBufferPointer { fx in
        cOld.withUnsafeBufferPointer { co in
            let tIn = ta + self.params.innerAir
            let nx = self.nx, ny = self.ny, hI = self.params.hInt, hC = self.params.hCase, kc = self.params.kCase / 4
            for _ in 0..<sweeps {
                for colour in 0..<2 {
                    for y in 0..<ny {
                        var x = (y + colour) & 1
                        while x < nx {
                            let i = y * nx + x
                            // internal layer
                            let f = fx[i]
                            if f.isNaN {
                                var num = hI * tIn + g[i] * C[i], den = hI + g[i]
                                if x > 0 { let c = kE[i - 1]; num += c * T[i - 1]; den += c }
                                if x + 1 < nx { let c = kE[i]; num += c * T[i + 1]; den += c }
                                if y > 0 { let c = kS[i - nx]; num += c * T[i - nx]; den += c }
                                if y + 1 < ny { let c = kS[i]; num += c * T[i + nx]; den += c }
                                T[i] += w * (num / den - T[i])
                            } else { T[i] = f }
                            // bottom case layer
                            var num = hC * ta + g[i] * T[i] + cap * co[i], den = hC + g[i] + cap
                            if x > 0 { num += kc * C[i - 1]; den += kc }
                            if x + 1 < nx { num += kc * C[i + 1]; den += kc }
                            if y > 0 { num += kc * C[i - nx]; den += kc }
                            if y + 1 < ny { num += kc * C[i + nx]; den += kc }
                            C[i] += w * (num / den - C[i])
                            x += 2
                        }
                    }
                }
            }
        }}}}}}}
    }

    func reset() { warm = false }
    var state: ([Float], [Float]) {
        get { (internalT, caseT) }
        set { internalT = newValue.0; caseT = newValue.1; warm = true }
    }

    /// Bilinear sample of the internal layer at a point in mm.
    func sample(at p: CGPoint) -> Float {
        let fx = min(max(Float(p.x / HeatSolver.dx) - 0.5, 0), Float(nx - 1)), fy = min(max(Float(p.y / HeatSolver.dx) - 0.5, 0), Float(ny - 1))
        let x0 = Int(fx), y0 = Int(fy), x1 = min(x0 + 1, nx - 1), y1 = min(y0 + 1, ny - 1)
        let tx = fx - Float(x0), ty = fy - Float(y0)
        let a = internalT[y0 * nx + x0], b = internalT[y0 * nx + x1], c = internalT[y1 * nx + x0], d = internalT[y1 * nx + x1]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    }

    /// Bilinear resample of a layer onto the 1 mm display grid.
    func resample(caseLayer: Bool, gw: Int, gh: Int) -> [Float] {
        let src = caseLayer ? caseT : internalT
        var out = [Float](repeating: 0, count: gw * gh)
        let s = Float(1 / HeatSolver.dx)
        for y in 0..<gh {
            let fy = min(max((Float(y) + 0.5) * s - 0.5, 0), Float(ny - 1))
            let y0 = Int(fy), y1 = min(y0 + 1, ny - 1), ty = fy - Float(y0)
            for x in 0..<gw {
                let fx = min(max((Float(x) + 0.5) * s - 0.5, 0), Float(nx - 1))
                let x0 = Int(fx), x1 = min(x0 + 1, nx - 1), tx = fx - Float(x0)
                let a = src[y0 * nx + x0], b = src[y0 * nx + x1], c = src[y1 * nx + x0], d = src[y1 * nx + x1]
                out[y * gw + x] = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
            }
        }
        return out
    }
}

extension HeatSolver {
    /// Fitted 2026-11-24 with `--fit` on idle, 70 s full-CPU load and cooling snapshots (calib/*.json).
    /// Held-out passive sensors (heat sink, battery, gas gauge, palm rests): RMS error 5.8 -> 4.0 C,
    /// mean absolute error 4.7 -> 3.0 C. Largest remaining miss: the heat-sink sensor nearest the die
    /// under load reads hotter than conduction from the die predicts (its exact spot is inferred).
    static let fitted: Params = {
        var p = Params()
        p.kSink = 636; p.kBoard = 7.56; p.kChip = 11.3; p.kTrackpad = 25.4
        p.gBattery = 0.00075; p.gSink = 0.015   // fit wanted 0.005 (rms 3.97 vs 3.99); 0.015 keeps the bottom case physical
        p.hInt = 0.0159; p.innerAir = 4
        return p
    }()
}
