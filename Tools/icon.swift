import AppKit
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
// squircle
let bg = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.addPath(bg); ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.055, blue: 0.07, alpha: 1)); ctx.fillPath()
// chassis
let body = CGRect(x: 190, y: 300, width: 644, height: 455)
let chassis = CGPath(roundedRect: body, cornerWidth: 34, cornerHeight: 34, transform: nil)
ctx.saveGState(); ctx.addPath(chassis); ctx.clip()
let stops: [(CGFloat, (CGFloat, CGFloat, CGFloat))] = [(0, (1, 1, 0.9)), (0.12, (1, 0.85, 0.25)), (0.3, (0.98, 0.55, 0.05)), (0.5, (0.8, 0.12, 0.45)), (0.72, (0.42, 0, 0.6)), (1, (0.1, 0, 0.3))]
let grad = CGGradient(colorsSpace: cs, colors: stops.map { CGColor(srgbRed: $0.1.0, green: $0.1.1, blue: $0.1.2, alpha: 1) } as CFArray, locations: stops.map(\.0))!
ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0, blue: 0.3, alpha: 1)); ctx.fill(body)
ctx.drawRadialGradient(grad, startCenter: CGPoint(x: 470, y: 650), startRadius: 0, endCenter: CGPoint(x: 470, y: 650), endRadius: 480, options: [.drawsAfterEndLocation])
// isotherm rings
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35)); ctx.setLineWidth(5)
for r in stride(from: 90.0, through: 420, by: 82) { ctx.strokeEllipse(in: CGRect(x: 470 - r * 1.15, y: 650 - r * 0.85, width: 2.3 * r, height: 1.7 * r)) }
ctx.restoreGState()
ctx.addPath(chassis); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.85)); ctx.setLineWidth(8); ctx.strokePath()
// crosshair
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(10)
for (a, b) in [((400, 650), (445, 650)), ((495, 650), (540, 650)), ((470, 580), (470, 625)), ((470, 675), (470, 720))] {
    ctx.move(to: CGPoint(x: a.0, y: a.1)); ctx.addLine(to: CGPoint(x: b.0, y: b.1))
}
ctx.strokePath()
// scale bar
let bar = CGRect(x: 190, y: 205, width: 644, height: 34)
ctx.saveGState(); ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 10, cornerHeight: 10, transform: nil)); ctx.clip()
ctx.drawLinearGradient(grad, start: CGPoint(x: bar.maxX, y: 0), end: CGPoint(x: bar.minX, y: 0), options: [])
ctx.restoreGState()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
