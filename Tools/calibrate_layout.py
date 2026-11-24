# One-off: rewrites the board geometry and sensor map in Sources/Layout.swift with the
# measurements taken from Apple's Self Service Repair manual (MacBook Air 13" M3, J613).
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
p = root / 'Sources/Layout.swift'
s = p.read_text()

a = s.index('/// MacBook Air 13"'); b = s.index('    // MARK: SoC die floorplan')
s = s[:a] + '''/// MacBook Air 13" (M3, Mac15,12 / J613) internal geometry in millimetres, seen from ABOVE
/// (keyboard side, X-ray), hinge at y = 0, front lip at y = 215.
///
/// Calibrated 2026-11-24 against Apple's Self Service Repair manual for this exact model
/// (support.apple.com/119579: logic board locator, heat-sink screws, battery and trackpad photos;
/// bottom-case photo mirrored to the top view) and iFixit's board shot of the same J613-family board
/// for chip positions on the PCB. Outlines are within roughly 3-5 mm; Apple does not publish
/// sensor coordinates, so each sensor sits on the part it measures.
enum Board {
    static let width: Double = 304.1
    static let depth: Double = 215.0
    static let corner: Double = 11.0
    /// M3 die centre: under the heat sink, at the right end of the logic board (top view).
    static let dieCenter = CGPoint(x: 207.8, y: 41.6)

    struct Part { let name: String; let rect: CGRect; let kind: Kind }
    enum Kind { case board, chip, battery, module, trackpad, port, sink }

    static let parts: [Part] = [
        Part(name: "LOGIC BOARD", rect: CGRect(x: 15.9, y: 8, width: 272.3, height: 62), kind: .board),
        Part(name: "HEAT SINK", rect: CGRect(x: 190.8, y: 14, width: 97.4, height: 54), kind: .sink),
        Part(name: "M3", rect: CGRect(x: 185.9, y: 22.1, width: 43.8, height: 39.2), kind: .chip),
        Part(name: "NAND", rect: CGRect(x: 255.4, y: 23.9, width: 21.9, height: 14.3), kind: .chip),
        Part(name: "NAND", rect: CGRect(x: 260.8, y: 43.7, width: 14.6, height: 19.6), kind: .chip),
        Part(name: "PMU", rect: CGRect(x: 152.8, y: 37.0, width: 16.4, height: 17.8), kind: .chip),
        Part(name: "PMU2", rect: CGRect(x: 50.6, y: 37.4, width: 14.6, height: 10.7), kind: .chip),
        Part(name: "VR", rect: CGRect(x: 115.6, y: 33.0, width: 21.9, height: 30.0), kind: .chip),
        Part(name: "Wi-Fi", rect: CGRect(x: 154.8, y: 2.5, width: 21.9, height: 16.1), kind: .module),
        Part(name: "SPK L", rect: CGRect(x: 36.6, y: 2.6, width: 67.5, height: 10.4), kind: .module),
        Part(name: "SPK R", rect: CGRect(x: 200.4, y: 2.6, width: 60.4, height: 10.4), kind: .module),
        Part(name: "AUDIO", rect: CGRect(x: 260.7, y: 13.0, width: 21.7, height: 20.9), kind: .module),
        Part(name: "I/O", rect: CGRect(x: 17.3, y: 31.3, width: 14.5, height: 33.9), kind: .module),
        Part(name: "MAGSAFE", rect: CGRect(x: 0, y: 28, width: 8, height: 10), kind: .port),
        Part(name: "USB-C", rect: CGRect(x: 0, y: 41, width: 8, height: 9), kind: .port),
        Part(name: "USB-C", rect: CGRect(x: 0, y: 53, width: 8, height: 9), kind: .port),
        Part(name: "3.5", rect: CGRect(x: 294, y: 20, width: 10, height: 10), kind: .port),
        Part(name: "CELL 1", rect: CGRect(x: 13.5, y: 75.7, width: 131.6, height: 46.9), kind: .battery),
        Part(name: "CELL 2", rect: CGRect(x: 158.1, y: 75.7, width: 133.0, height: 46.9), kind: .battery),
        Part(name: "CELL 3", rect: CGRect(x: 9.2, y: 125.2, width: 75.6, height: 67.9), kind: .battery),
        Part(name: "CELL 4", rect: CGRect(x: 218.8, y: 125.2, width: 74.2, height: 67.9), kind: .battery),
        Part(name: "TRACKPAD", rect: CGRect(x: 96.9, y: 127.8, width: 108.4, height: 80.9), kind: .trackpad),
    ]

''' + s[b:]

a = s.index('    static let pmu = CGPoint'); b = s.index('    static func place(smc key: String)')
s = s[:a] + '''    static let pmu = CGPoint(x: 161.0, y: 45.9)
    static let pmu2 = CGPoint(x: 57.9, y: 42.7)
    static let nand = CGPoint(x: 266.4, y: 31.0)
    static let nand2 = CGPoint(x: 268.1, y: 53.5)
    /// three battery thermistor sites: left pack seam, centre seam, right pack seam
    static let cells: [CGPoint] = [CGPoint(x: 60, y: 118), CGPoint(x: 152, y: 99), CGPoint(x: 244, y: 118)]
    static let gauge = CGPoint(x: 152, y: 73)

    static let fixed: [String: (String, CGPoint, Double)] = [
        "Ts0P": ("Palm rest · left", CGPoint(x: 47, y: 196), 34),
        "Ts1P": ("Palm rest · right", CGPoint(x: 256, y: 196), 34),
        "TH0T": ("NAND", nand, 12), "TH0x": ("NAND", nand2, 12),
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
        "TPMP": ("PMU prox.", pmu, 12), "TPDX": ("PMU die max", pmu, 9),
        "TRDX": ("PMU2 die max", pmu2, 9), "TR0Z": ("PMU2 cal.", pmu2, 9),
        "TR2d": ("Regulator", CGPoint(x: 72, y: 30), 10), "TR4d": ("Regulator", CGPoint(x: 44, y: 28), 10),
        "TR5d": ("Regulator", CGPoint(x: 70, y: 56), 10),
        "TB0T": ("Battery · left", cells[0], 40), "TB1T": ("Battery · centre", cells[1], 40),
        "TB2T": ("Battery · right", cells[2], 40),
        "TG0B": ("Battery · left", CGPoint(x: 60, y: 126), 40), "TG1B": ("Battery · centre", CGPoint(x: 152, y: 105), 40),
        "TG2B": ("Battery · right", CGPoint(x: 244, y: 126), 40),
        "TG0C": ("Gas gauge", CGPoint(x: 149, y: gauge.y), 18), "TG0H": ("Gas gauge", CGPoint(x: 155, y: gauge.y), 18),
        "TG0V": ("Gas gauge", CGPoint(x: 152, y: gauge.y + 3), 18),
        // Th*: two triples on the heat sink that covers the M3 (Apple: "remove two screws from the heat sink").
        // The hotter triple (Th08-0A) sits at the die edge, the cooler one (Th00-02) out on the far end.
        "Th08": ("Heat sink · die edge", CGPoint(x: 236, y: 30), 13), "Th09": ("Heat sink · die edge", CGPoint(x: 236, y: 42), 13),
        "Th0A": ("Heat sink · die edge", CGPoint(x: 236, y: 54), 13),
        "Th00": ("Heat sink · far end", CGPoint(x: 272, y: 20), 15), "Th01": ("Heat sink · far end", CGPoint(x: 282, y: 42), 15),
        "Th02": ("Heat sink · far end", CGPoint(x: 272, y: 64), 15),
    ]

''' + s[b:]
s = s.replace('return Placement(zone: "SoC package", point: ring(die, 15, i, 12), sigma: 14)',
              'return Placement(zone: "SoC package", point: ring(die, 19, i, 12), sigma: 13)')
s = s.replace('if lower.contains("nand") { return Placement(zone: "NAND", point: nand, sigma: 14, inField: false) }',
              'if lower.contains("nand") { return Placement(zone: "NAND", point: CGPoint(x: nand.x + 4, y: nand.y), sigma: 12, inField: false) }')
p.write_text(s)

v = root / 'Sources/Views.swift'
t = v.read_text()
t = t.replace('''                case .module, .port: ctx.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 0.7)''',
'''                case .module, .port: ctx.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 0.7)
                case .sink: ctx.stroke(path, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 0.8, dash: [6, 2, 1, 2]))''')
t = t.replace('let order = ["SoC", "Heat", "PMU"', 'let order = ["SoC", "Heat sink", "Memory", "PMU"')
t = t.replace('Text("Sensor positions are reconstructed from Mac15,12 teardown layouts.',
              'Text("Layout calibrated to the Apple Self Service Repair manual for MacBook Air 13-inch M3 (J613), outlines within about 3-5 mm.')
v.write_text(t)
print("ok")
