import Foundation
import CoreGraphics

/// One Mac model: its chassis, board parts, die floorplan, where each temperature sensor sits and the heat-model
/// constants fitted for it. Each model lives in its own file in Sources/Models/ and is listed in `MacModel.all`.
/// docs/ADD-A-MAC.md walks through adding one.
struct MacModel {
    /// e.g. "13-inch MacBook Air with M3"
    let name: String
    /// e.g. "MacBook Air 13-inch, M3"
    let shortName: String
    /// `sysctl hw.model` values this layout is for, e.g. ["Mac15,12"]
    let identifiers: [String]
    let chip: String
    /// chassis outline in mm, top view, hinge at y = 0
    let width: Double, depth: Double, corner: Double
    let dieCenter: CGPoint
    let parts: [Board.Part]
    /// die floorplan in a unit square (inset in the sidebar)
    let dieBlocks: [Board.DieBlock]
    /// rubber feet, drawn on the bottom view
    let feet: [CGPoint]
    let anchors: Anchors
    /// SMC key -> (zone label, position in mm, influence radius in mm)
    let sensors: [String: (String, CGPoint, Double)]
    let params: HeatSolver.Params

    /// Points the prefix rules hang sensor families on (PMU rings, NAND, battery sites, package ring).
    struct Anchors {
        var pmu: CGPoint, pmu2: CGPoint, nand: CGPoint, nand2: CGPoint
        var cells: [CGPoint], gauge: CGPoint
        var packageRadius: Double
    }

    /// Every model with a layout. Add yours here.
    static let all: [MacModel] = [.macBookAir13M3]

    /// The layout for this Mac, or the M3 Air's when this Mac has none yet (the app then shows a notice).
    static let active: MacModel = all.first { $0.identifiers.contains(ThermalModel.hwModel) } ?? .macBookAir13M3
    static var isSupported: Bool { all.contains { $0.identifiers.contains(ThermalModel.hwModel) } }
}

/// The active model's geometry, under the short names the drawing and solver code use.
enum Board {
    struct Part { let name: String; let rect: CGRect; let kind: Kind }
    enum Kind { case board, chip, battery, module, trackpad, port, sink }
    struct DieBlock { let name: String; let rect: CGRect }

    static var width: Double { MacModel.active.width }
    static var depth: Double { MacModel.active.depth }
    static var corner: Double { MacModel.active.corner }
    static var dieCenter: CGPoint { MacModel.active.dieCenter }
    static var parts: [Part] { MacModel.active.parts }
    static var dieBlocks: [DieBlock] { MacModel.active.dieBlocks }
    static var feet: [CGPoint] { MacModel.active.feet }
}

enum DieRegion: String { case p = "P-CLUSTER", e = "E-CLUSTER", gpu = "GPU  10-CORE" }

struct Placement {
    var zone: String
    var point: CGPoint          // mm, top view
    var sigma: Double           // spread of this sensor's influence, mm
    var die: DieRegion? = nil
    var inField = true          // contributes to the chassis field directly
}

/// Places each sensor: first the model's own table, then family rules by key prefix (Apple silicon SMC naming).
enum SensorMap {
    private static func ring(_ c: CGPoint, _ r: Double, _ i: Int, _ n: Int) -> CGPoint {
        let a = Double(i) / Double(max(n, 1)) * 2 * .pi - .pi / 2
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }
    private static func stableIndex(_ s: String, mod: Int) -> Int {
        Int(s.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 } % UInt32(mod))
    }
    private static var a: MacModel.Anchors { MacModel.active.anchors }
    /// maxima of the PMU and PMU2 die rings
    static let summaryKeys: Set<String> = ["TPDX", "TRDX"]

    static func place(smc key: String) -> Placement? {
        if let f = MacModel.active.sensors[key] {
            // summary keys (a maximum over other sensors) are listed but never pinned: pinning them on top of
            // the sensors they summarise would average two different quantities into one spot
            return Placement(zone: f.0, point: f.1, sigma: f.2, inField: !summaryKeys.contains(key))
        }
        let die = Board.dieCenter
        let p2 = key.prefix(2)
        switch p2 {
        case "Tp": return Placement(zone: "SoC · P-cluster", point: die, sigma: 22, die: .p, inField: false)
        case "Te": return Placement(zone: "SoC · E-cluster", point: die, sigma: 22, die: .e, inField: false)
        case "Tg": return Placement(zone: "SoC · GPU", point: die, sigma: 22, die: .gpu, inField: false)
        case "TC": return Placement(zone: "SoC · CPU summary", point: die, sigma: 18, inField: false)
        case "TP" where key.hasPrefix("TPD"):
            let i = Int(String(key.last!)) ?? 0
            return Placement(zone: "PMU die", point: ring(a.pmu, 5, i, 8), sigma: 11)
        case "TR" where key.hasPrefix("TRD"):
            let i = Int(String(key.last!)) ?? 0
            return Placement(zone: "PMU2 die", point: ring(a.pmu2, 5, i, 8), sigma: 11)
        case "Ts":
            let i = stableIndex(key, mod: 12)
            return Placement(zone: "SoC package", point: ring(die, a.packageRadius, i, 12), sigma: 13)
        default: return nil
        }
    }

    /// HID services are mostly mirrors of SMC keys (PMU tdie ≈ TPDn, PMU2 tdie ≈ TRDn,
    /// gas gauge ≈ TB/TG), so they are listed and positioned but not double-counted in the field.
    static func place(hid name: String) -> Placement? {
        let lower = name.lowercased()
        func idx() -> Int { Int(name.filter(\.isNumber).suffix(1)) ?? 0 }
        if lower.hasPrefix("pmu2") { return Placement(zone: "PMU2", point: ring(a.pmu2, 7, idx(), 9), sigma: 11, inField: false) }
        if lower.hasPrefix("pmu") { return Placement(zone: "PMU", point: ring(a.pmu, 7, idx(), 9), sigma: 11, inField: false) }
        if lower.contains("nand") { return Placement(zone: "NAND", point: CGPoint(x: a.nand.x + 4, y: a.nand.y), sigma: 12, inField: false) }
        if lower.contains("battery") || lower.contains("gas gauge") {
            let n = Int(name.split(separator: "#").last.flatMap { Int($0) } ?? 1)
            return Placement(zone: "Battery", point: a.cells[(n - 1) % a.cells.count], sigma: 40, inField: false)
        }
        return nil
    }
}
