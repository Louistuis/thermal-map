import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Headless frame recorder for demo videos. Never puts a window on screen.
///
///     ThermalMap --record=/path/frames --seconds=150 --fps=2 [--size=1536x864] [--scale=1.25] [--format=png|jpg]
///                [--at=60:surface] [--at=110:top] [--at=130:internal] [--at=140:bottom] [--at=20:rainbow]
///
/// Writes frame_00000.png (or .jpg) ... with live sensor data, plus frames.txt (index, seconds, mode, side, corePeak, fieldMax).
/// `--at=SEC:ACTION` switches the view at that time: surface, internal, top, bottom, fixed, auto (colour range), labels, nolabels,
/// or a palette name (ironbow, rainbow, arctic, whitehot).
enum Recorder {
    static func run(_ args: [String]) {
        func val(_ p: String) -> String? { args.first(where: { $0.hasPrefix(p) }).map { String($0.dropFirst(p.count)) } }
        let dir = URL(fileURLWithPath: val("--record=")!)
        let seconds = Double(val("--seconds=") ?? "60") ?? 60
        let fps = Double(val("--fps=") ?? "2") ?? 2
        let size = (val("--size=") ?? "1536x864").split(separator: "x").compactMap { Double($0) }
        let scale = Double(val("--scale=") ?? "1.25") ?? 1.25
        let jpeg = (val("--format=") ?? "png").lowercased().hasPrefix("j")
        let schedule: [(Double, String)] = args.filter { $0.hasPrefix("--at=") }.compactMap {
            let p = $0.dropFirst(5).split(separator: ":", maxSplits: 1)
            guard p.count == 2, let t = Double(p[0]) else { return nil }
            return (t, String(p[1]))
        }.sorted { $0.0 < $1.0 }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        ThermalModel.renderMode = true
        let model = ThermalModel()
        for a in args where a.hasPrefix("--at=0:") { apply(String(a.dropFirst(7)), model) }
        model.start()

        let writer = DispatchQueue(label: "recorder.write", qos: .userInitiated)
        let group = DispatchGroup()
        var log = "index\tseconds\tmode\tside\tcorePeak\tfieldMax\n"
        var index = 0
        var nextAction = schedule.firstIndex(where: { $0.0 > 0 }) ?? schedule.count
        let warmup = 3.0
        let t0 = CFAbsoluteTimeGetCurrent() + warmup

        func tick() {
            let t = CFAbsoluteTimeGetCurrent() - t0
            if t > seconds {
                group.notify(queue: .main) {
                    try? log.write(to: dir.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
                    print("recorded \(index) frames to \(dir.path)")
                    exit(0)
                }
                return
            }
            while nextAction < schedule.count, schedule[nextAction].0 <= t { apply(schedule[nextAction].1, model); nextAction += 1 }
            MainActor.assumeIsolated {
                let r = ImageRenderer(content: ContentView(m: model).frame(width: size[0], height: size[1]).environment(\.colorScheme, .dark))
                r.scale = scale
                let f = model.frame
                log += String(format: "%d\t%.2f\t%@\t%@\t%.1f\t%.1f\n", index, t, model.mode.rawValue, model.side.rawValue, f.corePeak, f.hotValue)
                if let cg = r.cgImage {
                    let url = dir.appendingPathComponent(String(format: "frame_%05d.%@", index, jpeg ? "jpg" : "png"))
                    group.enter()
                    writer.async {
                        let type = (jpeg ? UTType.jpeg : UTType.png).identifier as CFString
                        if let d = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) {
                            let props = [kCGImageDestinationLossyCompressionQuality: 0.93] as CFDictionary
                            CGImageDestinationAddImage(d, cg, jpeg ? props : nil); CGImageDestinationFinalize(d)
                        }
                        group.leave()
                    }
                    index += 1
                }
            }
            // schedule against the wall clock so a slow render does not stretch the timeline
            let next = t0 + Double(index) / fps
            let delay = Swift.max(0.01, next - CFAbsoluteTimeGetCurrent())
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { tick() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + warmup) { tick() }
        app.run()
    }

    private static func apply(_ action: String, _ m: ThermalModel) {
        switch action.lowercased() {
        case "surface": m.mode = .surface
        case "internal": m.mode = .internalMode
        case "top": m.side = .top
        case "bottom": m.side = .bottom
        case "fixed": m.autoRange = false
        case "auto": m.autoRange = true
        case "labels": m.showLabels = true
        case "nolabels": m.showLabels = false
        default:
            if let p = Palette.allCases.first(where: { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(action.lowercased()) }) {
                m.palette = p
            }
        }
        print("[\(action)]")
    }
}
