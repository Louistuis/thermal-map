import Foundation
import CoreGraphics

/// Steady-state two-layer heat conduction on a 2 mm grid.
///
/// Layer 1 (internal): logic board, heat sink, battery and trackpad sitting on the aluminium top case.
///   k(x,y) is the in-plane sheet conductance of whatever is at that spot; the real sensor readings are
///   held fixed (Dirichlet) at the cells they measure.
/// Layer 2 (bottom case): ~1 mm aluminium sheet. It is coupled to layer 1 by g(x,y) (strong under the heat
///   sink, weak through the air gap over the battery) and loses heat to room air by convection.
///
///   layer 1:  sum_faces k_f (T_n - T) + g (Tc - T) + h_i (Ta - T) = 0
///   layer 2:  sum_faces kc  (Tc_n - Tc) + g (T - Tc) + h_c (Ta - Tc) = 0
///
/// Solved by red-black SOR, warm-started from the previous frame, so a few dozen sweeps per frame keep
/// it converged while readings drift. Constants are relative (per-cell) values tuned so the characteristic
/// spreading lengths match the materials: ~35 mm over bare top case, ~140 mm along the heat sink,
/// ~55 mm in the bottom case.
final class HeatSolver {
    static let dx = 2.0
    let nx = Int((Board.width / HeatSolver.dx).rounded(.up))   // 153
    let ny = Int((Board.depth / HeatSolver.dx).rounded(.up))   // 108
    private(set) var internalT: [Float]
    private(set) var caseT: [Float]
    private var kE: [Float], kS: [Float]   // face conductance to east / south neighbour (0 at the edge)
    private var g: [Float]
    private var fixed: [Float]             // NaN = free
    private let hInt: Float = 0.004
    private let hCase: Float = 0.018
    private let kCase: Float = 8.0
    private var warm = false
    let kMap: [Float]

    init() {
        let nx = Int((Board.width / HeatSolver.dx).rounded(.up)), ny = Int((Board.depth / HeatSolver.dx).rounded(.up))
        let n = nx * ny
        var k = [Float](repeating: 10, count: n)      // bare aluminium top case + keyboard stack
        var gg = [Float](repeating: 0.004, count: n)  // air gap to the bottom case
        func paint(_ r: CGRect, _ kv: Float, _ gv: Float) {
            let x0 = max(0, Int(r.minX / HeatSolver.dx)), x1 = min(nx - 1, Int(r.maxX / HeatSolver.dx))
            let y0 = max(0, Int(r.minY / HeatSolver.dx)), y1 = min(ny - 1, Int(r.maxY / HeatSolver.dx))
            guard x0 <= x1, y0 <= y1 else { return }
            for y in y0...y1 { for x in x0...x1 { k[y * nx + x] = kv; gg[y * nx + x] = gv } }
        }
        // order matters: later parts sit on top
        for p in Board.parts where p.kind == .battery { paint(p.rect, 12, 0.003) }
        for p in Board.parts where p.kind == .trackpad { paint(p.rect, 9, 0.003) }
        for p in Board.parts where p.kind == .board { paint(p.rect, 30, 0.006) }
        for p in Board.parts where p.kind == .module { paint(p.rect, 14, 0.006) }
        for p in Board.parts where p.kind == .chip { paint(p.rect, 45, 0.012) }
        for p in Board.parts where p.kind == .sink { paint(p.rect, 160, 0.015) }
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

    struct Pin { let at: CGPoint; let radius: Double; let t: Double }

    func solve(pins: [Pin], ambient: Double) {
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
        let sweeps = warm ? 12 : 600
        warm = true
        let w: Float = 1.82
        internalT.withUnsafeMutableBufferPointer { T in
        caseT.withUnsafeMutableBufferPointer { C in
        kE.withUnsafeBufferPointer { kE in
        kS.withUnsafeBufferPointer { kS in
        g.withUnsafeBufferPointer { g in
        fixed.withUnsafeBufferPointer { fx in
            let nx = self.nx, ny = self.ny, hI = self.hInt, hC = self.hCase, kc = self.kCase / 4
            for _ in 0..<sweeps {
                for colour in 0..<2 {
                    for y in 0..<ny {
                        var x = (y + colour) & 1
                        while x < nx {
                            let i = y * nx + x
                            // internal layer
                            let f = fx[i]
                            if f.isNaN {
                                var num = hI * ta + g[i] * C[i], den = hI + g[i]
                                if x > 0 { let c = kE[i - 1]; num += c * T[i - 1]; den += c }
                                if x + 1 < nx { let c = kE[i]; num += c * T[i + 1]; den += c }
                                if y > 0 { let c = kS[i - nx]; num += c * T[i - nx]; den += c }
                                if y + 1 < ny { let c = kS[i]; num += c * T[i + nx]; den += c }
                                T[i] += w * (num / den - T[i])
                            } else { T[i] = f }
                            // bottom case layer
                            var num = hC * ta + g[i] * T[i], den = hC + g[i]
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
        }}}}}}
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
