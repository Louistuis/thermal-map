import Foundation
import AppKit

/// Accuracy test and constant fitting for the heat model, all headless.
///
///   ThermalMap --snapshot=idle.json              save one set of pins (live readings) after 4 s
///   ThermalMap --fit=idle.json,load.json          held-out sensor test, then fit the internal-layer constants
///
/// The test: hide a group of sensors from the model, solve, and compare the model's temperature at their
/// spot with what they actually read. Only passive spots are scored (heat sink, battery, gas gauge,
/// palm rests): a pure conduction model cannot predict a part that makes its own heat, so self-heating
/// parts (chips, regulators) are always pinned and never scored.
enum Calibrate {
    struct Snapshot: Codable { var pins: [HeatSolver.Pin]; var ambient: Double; var label: String }

    static func snapshot(to path: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        ThermalModel.renderMode = true
        let model = ThermalModel()
        model.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            let valid = model.liveSensors.filter { $0.valid && !$0.value.isNaN }
            let (pins, ambient, peak) = ThermalModel.buildPins(valid)
            let snap = Snapshot(pins: pins, ambient: ambient, label: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
            if let d = try? JSONEncoder().encode(snap) { try? d.write(to: URL(fileURLWithPath: path)) }
            print(String(format: "wrote %@: %d pins, ambient %.1f, core peak %.1f", path, pins.count, ambient, peak))
            exit(0)
        }
        app.run()
    }

    /// `--dump`: every sensor this Mac exposes, tab separated, with where the active layout puts it.
    /// The starting point for adding a new Mac (docs/ADD-A-MAC.md).
    static func dump() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        ThermalModel.renderMode = true
        let model = ThermalModel()
        model.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            print("# hw.model \(ThermalModel.hwModel)  layout: \(MacModel.isSupported ? MacModel.active.name : "none yet (showing \(MacModel.active.name))")")
            print("source\tkey\ttype\tvalue_C\tzone\tx_mm\ty_mm\tin_field")
            for s in model.liveSensors.sorted(by: { ($0.source, $0.key) < ($1.source, $1.key) }) {
                let v = s.valid ? String(format: "%.2f", s.raw ?? .nan) : "-"
                let p = s.placement
                print([s.source, s.key, s.type, v, p?.zone ?? "unmapped",
                       p.map { String(format: "%.1f", $0.point.x) } ?? "-", p.map { String(format: "%.1f", $0.point.y) } ?? "-",
                       p.map { $0.inField ? "yes" : "no" } ?? "-"].joined(separator: "\t"))
            }
            exit(0)
        }
        app.run()
    }

    static let scoredPrefixes = ["Th", "TB", "TG", "Ts0P", "Ts1P"]

    /// Groups of scored pins, linked when closer than 13 mm, so a sensor is never "predicted" from its twin.
    static func groups(_ pins: [HeatSolver.Pin]) -> [[Int]] {
        let idx = pins.indices.filter { i in scoredPrefixes.contains { pins[i].key.hasPrefix($0) } }
        var group = [Int: Int]()
        var out: [[Int]] = []
        for i in idx {
            if group[i] != nil { continue }
            var g = [i]; group[i] = out.count
            var k = 0
            while k < g.count {
                let a = pins[g[k]].at
                for j in idx where group[j] == nil && hypot(pins[j].at.x - a.x, pins[j].at.y - a.y) < 13 { group[j] = out.count; g.append(j) }
                k += 1
            }
            out.append(g)
        }
        return out
    }

    struct Score { var rms: Double; var mae: Double; var worst: (String, Double) }

    static func score(_ p: HeatSolver.Params, _ snaps: [Snapshot], verbose: Bool = false) -> Score {
        var se = 0.0, ae = 0.0, n = 0.0, worst = ("", 0.0)
        for s in snaps {
            let solver = HeatSolver(p)
            solver.solve(pins: s.pins, ambient: s.ambient, sweeps: 700)
            let base = solver.state
            for g in groups(s.pins) {
                let held = Set(g)
                let kept = s.pins.enumerated().filter { !held.contains($0.offset) }.map(\.element)
                solver.state = base
                solver.solve(pins: kept, ambient: s.ambient, sweeps: 350)
                for i in g {
                    let pred = Double(solver.sample(at: s.pins[i].at)), err = pred - s.pins[i].t
                    se += err * err; ae += abs(err); n += 1
                    if abs(err) > abs(worst.1) { worst = ("\(s.label):\(s.pins[i].key)", err) }
                    if verbose { print(String(format: "  %@ %-5@ read %5.1f  model %5.1f  err %+5.1f", s.label, s.pins[i].key, s.pins[i].t, pred, err)) }
                }
            }
        }
        return Score(rms: (se / max(n, 1)).squareRoot(), mae: ae / max(n, 1), worst: worst)
    }

    static func load(_ paths: [String]) -> [Snapshot] {
        paths.compactMap { p in (try? Data(contentsOf: URL(fileURLWithPath: p))).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } }
    }
    /// Score the shipped constants only; ENV TM_MOVE="KEY:dx:dy,..." shifts pins (placement experiments).
    static func scoreOnly(_ paths: [String]) {
        var snaps = load(paths)
        if let mv = ProcessInfo.processInfo.environment["TM_MOVE"] {
            for spec in mv.split(separator: ",") {
                let f = spec.split(separator: ":"); guard f.count == 3, let dx = Double(f[1]), let dy = Double(f[2]) else { continue }
                for si in snaps.indices { for pi in snaps[si].pins.indices where snaps[si].pins[pi].key == f[0] {
                    snaps[si].pins[pi].at.x += dx; snaps[si].pins[pi].at.y += dy } }
            }
        }
        let sc = score(HeatSolver.fitted, snaps, verbose: ProcessInfo.processInfo.environment["TM_V"] != nil)
        print(String(format: "rms %.2f  mae %.2f  worst %@ %+.1f", sc.rms, sc.mae, sc.worst.0, sc.worst.1))
        exit(0)
    }

    static func fit(_ paths: [String]) {
        let snaps = paths.compactMap { p -> Snapshot? in
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: p)) else { print("cannot read \(p)"); return nil }
            return try? JSONDecoder().decode(Snapshot.self, from: d)
        }
        guard !snaps.isEmpty else { exit(1) }
        print("held-out groups per snapshot:", groups(snaps[0].pins).map { $0.map { snaps[0].pins[$0].key }.joined(separator: "+") })
        var best = HeatSolver.Params()   // fit from the hand-tuned physical starting point
        var bestScore = score(best, snaps, verbose: true)
        let start = bestScore
        let current = score(HeatSolver.fitted, snaps)
        print(String(format: "shipped constants: rms %.2f  mae %.2f", current.rms, current.mae))
        print(String(format: "start: rms %.2f  mae %.2f  worst %@ %+.1f", start.rms, start.mae, start.worst.0, start.worst.1))

        // coordinate descent on multiplicative factors, kept within 4x of the physical starting values
        let knobs: [WritableKeyPath<HeatSolver.Params, Float>] = [\.kSink, \.kBattery, \.kBoard, \.kChip, \.kTrackpad, \.hInt, \.gBattery, \.gSink, \.gBase]
        let origin = HeatSolver.Params()
        for round in 0..<4 {
            for d: Float in [-2, -1, 1, 2] {
                var trial = best
                trial.innerAir = Swift.min(10, Swift.max(0, trial.innerAir + d))
                let sc = score(trial, snaps)
                if sc.rms < bestScore.rms - 0.005 { best = trial; bestScore = sc }
            }
            for kp in knobs {
                for f: Float in [0.5, 0.71, 1.41, 2.0] {
                    var trial = best
                    trial[keyPath: kp] *= f
                    let ratio = trial[keyPath: kp] / origin[keyPath: kp]
                    if ratio < 0.25 || ratio > 4 { continue }
                    let sc = score(trial, snaps)
                    if sc.rms < bestScore.rms - 0.005 { best = trial; bestScore = sc }
                }
            }
            print(String(format: "round %d: rms %.2f  mae %.2f", round + 1, bestScore.rms, bestScore.mae))
        }
        _ = score(best, snaps, verbose: true)
        print(String(format: "fitted: rms %.2f (was %.2f)  mae %.2f (was %.2f)  worst %@ %+.1f",
                     bestScore.rms, start.rms, bestScore.mae, start.mae, bestScore.worst.0, bestScore.worst.1))
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(best), let s = String(data: d, encoding: .utf8) { print("PARAMS " + s) }
        exit(0)
    }
}
