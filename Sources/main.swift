import SwiftUI
import AppKit

struct ThermalMapApp: App {
    @StateObject private var model: ThermalModel = {
        let m = ThermalModel(); m.start(); return m
    }()
    var body: some Scene {
        WindowGroup("Thermal Map") {
            ContentView(m: model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1440, height: 860)
        .windowStyle(.hiddenTitleBar)
    }
}

/// Headless render for testing: `ThermalMap --render=/path/out.png [--top] [--surface] [--hl=smc:TPD3]`
/// Never puts a window on screen; renders ContentView with ImageRenderer after a few seconds of live data.
if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--render=") }) {
    let out = String(arg.dropFirst("--render=".count))
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    ThermalModel.renderMode = true
    let model = ThermalModel()
    if CommandLine.arguments.contains("--top") { model.side = .top }
    if CommandLine.arguments.contains("--surface") { model.mode = .surface }
    if CommandLine.arguments.contains("--labels") { model.showLabels = true }
    if let h = CommandLine.arguments.first(where: { $0.hasPrefix("--hl=") }) { model.highlighted = String(h.dropFirst(5)) }
    model.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
        MainActor.assumeIsolated {
            let r = ImageRenderer(content: ContentView(m: model).preferredColorScheme(.dark).frame(width: 1440, height: 860).environment(\.colorScheme, .dark))
            r.scale = 2
            let f = model.frame
            print(String(format: "mode=%@ ambient=%.1f fieldMin=%.1f fieldMax=%.1f corePeak=%.1f", model.mode.rawValue, f.ambient, f.coldValue, f.hotValue, f.corePeak))
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out))
                print("wrote \(out)")
            } else { print("render failed") }
            exit(0)
        }
    }
    app.run()
} else {
    ThermalMapApp.main()
}
