import Foundation
import CoreGraphics

/// MacBook Air 13-inch with M3 (Mac15,12, board J613): the model Thermal Map was built for.
///
/// Geometry in millimetres, seen from ABOVE (keyboard side, X-ray), hinge at y = 0, front lip at y = 215.
/// Calibrated 2026-11-24 against Apple's Self Service Repair manual for this exact model
/// (support.apple.com/119579: logic board locator, heat-sink screws, battery and trackpad photos;
/// bottom-case photo mirrored to the top view) and iFixit's board shot of the same J613-family board for chip
/// positions on the PCB. Outlines are within roughly 3-5 mm. Apple does not publish sensor coordinates, so each
/// sensor sits on the part it measures; the heat-sink sensors were placed from their own readings (`--score`).
/// See docs/ADD-A-MAC.md to add another Mac the same way.
extension MacModel {
    static let macBookAir13M3: MacModel = {
        let a = Anchors(
            pmu: CGPoint(x: 161.0, y: 45.9), pmu2: CGPoint(x: 57.9, y: 42.7),
            nand: CGPoint(x: 266.4, y: 31.0), nand2: CGPoint(x: 268.1, y: 53.5),
            // three battery thermistor sites: left pack seam, centre seam, right pack seam
            cells: [CGPoint(x: 60, y: 118), CGPoint(x: 152, y: 99), CGPoint(x: 244, y: 118)],
            gauge: CGPoint(x: 152, y: 73),
            packageRadius: 19)
        var params = HeatSolver.Params()
        // fitted with --fit on calib/idle.json, load.json, cooling.json: held-out RMS 5.8 -> 2.0 C
        params.kSink = 113; params.kBoard = 7.56; params.kChip = 11.3; params.kTrackpad = 35.8; params.kBattery = 47.7
        params.gBattery = 0.003; params.gBase = 0.002
        params.gSink = 0.015   // the fit wanted 0.004; 0.015 keeps the bottom case physical (no case sensor to fit)
        params.hInt = 0.0159; params.innerAir = 4
        return MacModel(
            name: "13-inch MacBook Air with M3",
            shortName: "MacBook Air 13-inch, M3",
            identifiers: ["Mac15,12"],
            chip: "M3",
            width: 304.1, depth: 215.0, corner: 11.0,
            // M3 die centre: under the heat sink, at the right end of the logic board (top view)
            dieCenter: CGPoint(x: 207.8, y: 41.6),
            parts: [

            Board.Part(name: "LOGIC BOARD", rect: CGRect(x: 15.9, y: 8, width: 272.3, height: 62), kind: .board),
            Board.Part(name: "HEAT SINK", rect: CGRect(x: 190.8, y: 14, width: 97.4, height: 54), kind: .sink),
            Board.Part(name: "M3", rect: CGRect(x: 185.9, y: 22.1, width: 43.8, height: 39.2), kind: .chip),
            Board.Part(name: "NAND", rect: CGRect(x: 255.4, y: 23.9, width: 21.9, height: 14.3), kind: .chip),
            Board.Part(name: "NAND", rect: CGRect(x: 260.8, y: 43.7, width: 14.6, height: 19.6), kind: .chip),
            Board.Part(name: "PMU", rect: CGRect(x: 152.8, y: 37.0, width: 16.4, height: 17.8), kind: .chip),
            Board.Part(name: "PMU2", rect: CGRect(x: 50.6, y: 37.4, width: 14.6, height: 10.7), kind: .chip),
            Board.Part(name: "VR", rect: CGRect(x: 115.6, y: 33.0, width: 21.9, height: 30.0), kind: .chip),
            Board.Part(name: "Wi-Fi", rect: CGRect(x: 154.8, y: 2.5, width: 21.9, height: 16.1), kind: .module),
            Board.Part(name: "SPK L", rect: CGRect(x: 36.6, y: 2.6, width: 67.5, height: 10.4), kind: .module),
            Board.Part(name: "SPK R", rect: CGRect(x: 200.4, y: 2.6, width: 60.4, height: 10.4), kind: .module),
            Board.Part(name: "AUDIO", rect: CGRect(x: 260.7, y: 13.0, width: 21.7, height: 20.9), kind: .module),
            Board.Part(name: "I/O", rect: CGRect(x: 17.3, y: 31.3, width: 14.5, height: 33.9), kind: .module),
            Board.Part(name: "MAGSAFE", rect: CGRect(x: 0, y: 28, width: 8, height: 10), kind: .port),
            Board.Part(name: "USB-C", rect: CGRect(x: 0, y: 41, width: 8, height: 9), kind: .port),
            Board.Part(name: "USB-C", rect: CGRect(x: 0, y: 53, width: 8, height: 9), kind: .port),
            Board.Part(name: "3.5", rect: CGRect(x: 294, y: 20, width: 10, height: 10), kind: .port),
            Board.Part(name: "CELL 1", rect: CGRect(x: 13.5, y: 75.7, width: 131.6, height: 46.9), kind: .battery),
            Board.Part(name: "CELL 2", rect: CGRect(x: 158.1, y: 75.7, width: 133.0, height: 46.9), kind: .battery),
            Board.Part(name: "CELL 3", rect: CGRect(x: 9.2, y: 125.2, width: 75.6, height: 67.9), kind: .battery),
            Board.Part(name: "CELL 4", rect: CGRect(x: 218.8, y: 125.2, width: 74.2, height: 67.9), kind: .battery),
            Board.Part(name: "TRACKPAD", rect: CGRect(x: 96.9, y: 127.8, width: 108.4, height: 80.9), kind: .trackpad),
            ],
            dieBlocks: [

            Board.DieBlock(name: "P-CLUSTER", rect: CGRect(x: 0.04, y: 0.05, width: 0.50, height: 0.38)),
            Board.DieBlock(name: "E-CLUSTER", rect: CGRect(x: 0.58, y: 0.05, width: 0.38, height: 0.20)),
            Board.DieBlock(name: "NPU", rect: CGRect(x: 0.58, y: 0.28, width: 0.38, height: 0.15)),
            Board.DieBlock(name: "GPU  10-CORE", rect: CGRect(x: 0.04, y: 0.47, width: 0.92, height: 0.36)),
            Board.DieBlock(name: "SLC / FABRIC", rect: CGRect(x: 0.04, y: 0.86, width: 0.92, height: 0.10)),
            ],
            feet: [CGPoint(x: 24, y: 20), CGPoint(x: 280, y: 20), CGPoint(x: 24, y: 195), CGPoint(x: 280, y: 195)],
            anchors: a,
            sensors: [
            "Ts0P": ("Palm rest · left", CGPoint(x: 47, y: 196), 34),
            "Ts1P": ("Palm rest · right", CGPoint(x: 256, y: 196), 34),
            "TH0T": ("NAND", a.nand, 12), "TH0x": ("NAND", a.nand2, 12),
            "TSCD": ("Storage ctrl", CGPoint(x: 232, y: 52), 11),
            "Tm0B": ("Memory (on-package)", CGPoint(x: 207.8, y: 27), 11),
            "TMVR": ("Memory VR", CGPoint(x: 180, y: 20), 11),
            "TVD0": ("VDD regulator", CGPoint(x: 126.5, y: 48), 12),
            "TVS0": ("SoC rail VR", CGPoint(x: 119, y: 37), 10), "TVS1": ("SoC rail VR", CGPoint(x: 134, y: 37), 10),
            "TVSx": ("SoC rail VR", CGPoint(x: 119, y: 59), 10), "TVs1": ("SoC rail VR", CGPoint(x: 134, y: 59), 10),
            "TVA0": ("Aux / ambient", CGPoint(x: 90, y: 66), 18),
            "TAOL": ("Ambient · hinge", CGPoint(x: 112, y: 6), 22),
            "TDBP": ("Display backlight", CGPoint(x: 166, y: 3), 16),
            "TDeL": ("Display", CGPoint(x: 141, y: 3), 16),
            "TCHP": ("Charger", CGPoint(x: 40, y: 33), 13),
            "TPSP": ("Power supply prox.", CGPoint(x: 26, y: 44), 13),
            "TIOP": ("I/O prox.", CGPoint(x: 24, y: 59), 13),
            "T5SP": ("5 V supply", CGPoint(x: 46, y: 58), 11),
            "TW0P": ("Wi-Fi / BT", CGPoint(x: 165.8, y: 10.6), 14),
            "TPMP": ("PMU prox.", a.pmu, 12), "TPDX": ("PMU die max", a.pmu, 9),
            "TRDX": ("PMU2 die max", a.pmu2, 9), "TR0Z": ("PMU2 cal.", a.pmu2, 9),
            "TR2d": ("Regulator", CGPoint(x: 72, y: 30), 10), "TR4d": ("Regulator", CGPoint(x: 44, y: 28), 10),
            "TR5d": ("Regulator", CGPoint(x: 70, y: 56), 10),
            "TB0T": ("Battery · left", a.cells[0], 40), "TB1T": ("Battery · centre", a.cells[1], 40),
            "TB2T": ("Battery · right", a.cells[2], 40),
            "TG0B": ("Battery · left", CGPoint(x: 60, y: 126), 40), "TG1B": ("Battery · centre", CGPoint(x: 152, y: 105), 40),
            "TG2B": ("Battery · right", CGPoint(x: 244, y: 126), 40),
            "TG0C": ("Gas gauge", CGPoint(x: 149, y: a.gauge.y), 18), "TG0H": ("Gas gauge", CGPoint(x: 155, y: a.gauge.y), 18),
            "TG0V": ("Gas gauge", CGPoint(x: 152, y: a.gauge.y + 3), 18),
            // Th*: two triples on the heat sink over the M3. Positions estimated from the readings themselves
            // (Calibrate --score: the spots where the conduction model best predicts each triple when it is held out,
            // idle + load + cooling). The hotter triple sits ~15-20 mm from the die centre, the cooler one ~27 mm.
            "Th08": ("Heat sink · near die", CGPoint(x: 222, y: 26), 13), "Th09": ("Heat sink · near die", CGPoint(x: 222, y: 38), 13),
            "Th0A": ("Heat sink · near die", CGPoint(x: 222, y: 50), 13),
            "Th00": ("Heat sink · outer ring", CGPoint(x: 224, y: 20), 15), "Th01": ("Heat sink · outer ring", CGPoint(x: 234, y: 42), 15),
            "Th02": ("Heat sink · outer ring", CGPoint(x: 224, y: 64), 15),            ],
            params: params)
    }()
}
