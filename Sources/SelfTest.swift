import Foundation
import AppKit
import CoreGraphics

/// `--selftest`: headless checks of the sensors, layout, solver, field and isolines on this Mac.
/// Prints PASS/FAIL per check and exits non-zero on any failure.
enum SelfTest {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
        print((ok ? "PASS  " : "FAIL  ") + what + (ok ? "" : "  -- " + detail()))
        if !ok { failures += 1 }
    }

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        ThermalModel.renderMode = true
        let model = ThermalModel()
        model.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { MainActor.assumeIsolated { tests(model) } }
        app.run()
    }

    static func inside(_ p: CGPoint, _ margin: Double = 0) -> Bool {
        p.x >= -margin && p.y >= -margin && p.x <= Board.width + margin && p.y <= Board.depth + margin
    }

    static func tests(_ m: ThermalModel) {
        let all = m.liveSensors
        let valid = all.filter { $0.valid && !$0.value.isNaN }
        // sensors
        check(m.smcTempCount >= 100, "SMC temperature keys found (\(m.smcTempCount))", "expected 100+")
        check(m.hidCount >= 10, "HID thermal services found (\(m.hidCount))", "expected 10+")
        check(valid.count >= 150, "live sensors (\(valid.count) of \(all.count))", "expected 150+")
        check(valid.allSatisfy { $0.value > 5 && $0.value < 130 }, "every live value is between 5 and 130 C")
        check(Set(all.map(\.id)).count == all.count, "sensor ids are unique")

        // layout
        let placed = all.compactMap { s in s.placement.map { (s, $0) } }
        let outside = placed.filter { !inside($0.1.point, 2) }.map { $0.0.key }
        check(outside.isEmpty, "every placed sensor lies inside the chassis", outside.joined(separator: ","))
        let partsOut = Board.parts.filter { $0.kind != .port && !(inside(CGPoint(x: $0.rect.minX, y: $0.rect.minY), 0.5) && inside(CGPoint(x: $0.rect.maxX, y: $0.rect.maxY), 0.5)) }
        check(partsOut.isEmpty, "every part outline lies inside the chassis", partsOut.map(\.name).joined(separator: ","))
        check(inside(Board.dieCenter) && Board.parts.contains { $0.kind == .chip && $0.rect.contains(Board.dieCenter) }, "die centre sits on a chip outline")
        let fixedKeys = Set(MacModel.active.sensors.keys)
        let missing = fixedKeys.subtracting(all.filter { $0.source == "SMC" }.map(\.key))
        check(missing.isEmpty, "every key in the model's sensor table exists on this Mac", missing.sorted().joined(separator: ","))
        var dieBad: [String] = []
        for s in all where s.placement?.die != nil {
            guard let p = m.dieSlot(s.id), let block = Board.dieBlocks.first(where: { $0.name == s.placement!.die!.rawValue })?.rect else { dieBad.append(s.key); continue }
            if !block.insetBy(dx: -0.001, dy: -0.001).contains(p) || p.y < block.minY + 0.05 { dieBad.append(s.key) }
        }
        check(dieBad.isEmpty, "die sensors sit inside their block, below its label", dieBad.joined(separator: ","))
        check(MacModel.isSupported == MacModel.all.contains { $0.identifiers.contains(ThermalModel.hwModel) }, "model registry lookup (\(ThermalModel.hwModel) -> \(MacModel.active.name))")

        // pins and solver
        let (pins, ambient, peak) = ThermalModel.buildPins(valid)
        check(pins.count >= 40 && pins.allSatisfy { $0.t.isFinite && inside($0.at, 2) }, "pins (\(pins.count)) are finite and inside the chassis")
        check(ambient.isFinite && ambient < pins.map(\.t).min()!, "ambient (\(String(format: "%.1f", ambient))) is below every pin")
        check(peak.isFinite, "core peak is a number (\(String(format: "%.1f", peak)))")
        let solver = HeatSolver()
        let t0 = CFAbsoluteTimeGetCurrent()
        solver.solve(pins: pins, ambient: ambient)
        let coldMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        let lo = Float(ambient) - 0.01, hiPin = Float(pins.map(\.t).max()!) + 0.01
        let iT = solver.internalT, cT = solver.caseT
        check(iT.allSatisfy(\.isFinite) && cT.allSatisfy(\.isFinite), "solver output is finite")
        check(iT.min()! >= lo && iT.max()! <= hiPin, "internal layer stays between room air and the hottest pin (max principle)",
              "range \(iT.min()!)...\(iT.max()!) vs \(lo)...\(hiPin)")
        check(cT.min()! >= lo && cT.max()! <= hiPin, "bottom case stays between room air and the hottest pin")
        check(coldMs < 1500, "cold solve time \(Int(coldMs)) ms")
        // warm frames: speed and convergence
        let t1 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<50 { solver.solve(pins: pins, ambient: ambient) }
        let warmMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / 50
        check(warmMs < 40, "warm frame solve \(String(format: "%.1f", warmMs)) ms (budget 40 at 5 Hz)")
        // pins are honoured
        // pins are honoured: every sensor without a neighbour inside 4 mm reads its own value on the map
        func near(_ p: HeatSolver.Pin) -> [HeatSolver.Pin] { pins.filter { $0.key != p.key && hypot($0.at.x - p.at.x, $0.at.y - p.at.y) < 4 } }
        var pinErr: Float = 0, worstKey = ""
        for p in pins where p.radius < 3 && near(p).isEmpty {
            let e = abs(solver.sample(at: p.at) - Float(p.t)); if e > pinErr { pinErr = e; worstKey = p.key }
        }
        check(pinErr < 0.25, "field reads each sensor's own value at its spot (worst \(worstKey) \(String(format: "%.2f", pinErr)) C)")
        let clash = pins.filter { p in p.radius < 3 && near(p).contains { abs($0.t - p.t) > 3 } }.map(\.key)
        check(clash.isEmpty, "no two sensors within 4 mm disagree by more than 3 C (layout sanity)", clash.joined(separator: ","))
        // transient: a step in the pins moves the case slowly, monotonically and without overshoot
        let hot = pins.map { HeatSolver.Pin(at: $0.at, radius: $0.radius, t: $0.t + 10, key: $0.key) }
        let probe = CGPoint(x: Board.dieCenter.x, y: Board.dieCenter.y)
        func caseAt(_ s: HeatSolver) -> Float { let g = s.resample(caseLayer: true, gw: Int(Board.width.rounded()), gh: Int(Board.depth)); return g[Int(probe.y) * Int(Board.width.rounded()) + Int(probe.x)] }
        let before = caseAt(solver)
        var series: [Float] = []
        for _ in 0..<150 { solver.solve(pins: hot, ambient: ambient, dt: 0.2); series.append(caseAt(solver)) }
        let monotonic = zip(series, series.dropFirst()).allSatisfy { $1 >= $0 - 0.02 }
        let steady = HeatSolver(); steady.solve(pins: hot, ambient: ambient)
        let target = caseAt(steady)
        check(monotonic && series.last! <= target + 0.2 && series.last! > before, "bottom case warms gradually after a load step (\(String(format: "%.1f -> %.1f of %.1f", before, series.last!, target)) C in 30 s)")
        solver.solve(pins: hot, ambient: ambient, dt: 60)   // long gap: steady state again
        for _ in 0..<40 { solver.solve(pins: hot, ambient: ambient, dt: 60) }
        check(abs(caseAt(solver) - target) < 0.5, "a long gap snaps the bottom case to steady state")

        // field and isolines
        let f = m.frame
        check(f.image != nil && f.gw == Int(Board.width.rounded()) && f.gh == Int(Board.depth) && f.grid.count == f.gw * f.gh, "frame image and grid sizes")
        check(f.grid.allSatisfy(\.isFinite), "frame grid is finite")
        check(inside(f.hotspot) && f.hotValue >= f.coldValue, "hotspot inside the chassis, hot >= cold")
        check(f.lo < f.hi, "colour range lo < hi")
        check(m.value(atTop: CGPoint(x: 1, y: 1)) != nil && m.value(atTop: CGPoint(x: Board.width - 1, y: Board.depth - 1)) != nil
              && m.value(atTop: CGPoint(x: -3, y: 5)) == nil && m.value(atTop: CGPoint(x: 5, y: Board.depth + 3)) == nil, "hover probe inside / outside the chassis")
        let contours = Isolines.trace(f.grid, gw: f.gw, gh: f.gh, lo: f.lo, hi: f.hi)
        let segOK = contours.allSatisfy { $0.segments.count % 2 == 0 && $0.segments.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.x <= Double(f.gw) && $0.y <= Double(f.gh) } }
        check(!contours.isEmpty && segOK, "isotherms: \(contours.count) levels, segments paired and on the grid")
        check(f.dieImage != nil, "die inset image exists")
        for p in Palette.allCases {
            _ = p.color(.nan); _ = p.color(-5); _ = p.color(7)
        }
        check(Palette.allCases.allSatisfy { $0.lut.count == 256 }, "palettes have 256 entries and accept out-of-range input")
        // history
        check(m.history.count >= 2 && m.history.count <= 120, "history is filling (\(m.history.count) points)")
        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
