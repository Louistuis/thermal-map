// Renders the title card, caption overlays and end card for the demo video as PNGs.
// Uses the system fonts (SF Pro, SF Mono) through AppKit, so no font files are needed.
//
//   cards title   OUT.png WxH "Kicker" "Title" "Subtitle"
//   cards caption OUT.png WxH "Kicker" "Text" [top|bottom]     transparent overlay, pill at the top or bottom
//   cards end     OUT.png WxH "Kicker" "Title" "Subtitle"
import AppKit

let a = CommandLine.arguments
guard a.count >= 6 else { print("usage: cards title|caption|end OUT.png WxH kicker text [sub|pos]"); exit(1) }
let kind = a[1], out = a[2]
let wh = a[3].split(separator: "x").compactMap { Double($0) }
let W = wh[0], H = wh[1]
let kicker = a[4], text = a[5], extra = a.count > 6 ? a[6] : ""
let unit = min(W, H) / 1080   // type scales with the short side

let bg = NSColor(srgbRed: 0.043, green: 0.043, blue: 0.051, alpha: 1)
let accent = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.16, alpha: 1)
let secondary = NSColor(white: 1, alpha: 0.58)

func attr(_ s: String, _ font: NSFont, _ color: NSColor, kern: Double = 0, align: NSTextAlignment = .center) -> NSAttributedString {
    let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byWordWrapping
    return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: p])
}
func size(_ s: NSAttributedString, maxW: Double) -> CGSize {
    s.boundingRect(with: CGSize(width: maxW, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading]).size
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// flip so y grows downward, like the layout math below
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

let mono = NSFont.monospacedSystemFont(ofSize: 22 * unit, weight: .medium)

switch kind {
case "title", "end":
    bg.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    // faint thermal glow behind the type, the app's ironbow ramp
    let glow = NSGradient(colors: [NSColor(srgbRed: 1, green: 0.45, blue: 0.1, alpha: 0.20),
                                   NSColor(srgbRed: 0.55, green: 0.1, blue: 0.45, alpha: 0.08),
                                   NSColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 0)])!
    glow.draw(fromCenter: NSPoint(x: W / 2, y: H * 0.5), radius: 0, toCenter: NSPoint(x: W / 2, y: H * 0.5), radius: min(W, H) * 0.62, options: [])
    let k = attr(kicker.uppercased(), mono, accent, kern: 4 * unit)
    let maxW = W * 0.82
    // headline stays on one line: shrink until it fits
    var pt = (kind == "title" ? 112 : 72) * unit
    var t = attr(text, NSFont.systemFont(ofSize: pt, weight: .semibold), .white, kern: -1.5 * unit)
    while t.size().width > maxW && pt > 20 {
        pt -= 2; t = attr(text, NSFont.systemFont(ofSize: pt, weight: .semibold), .white, kern: -1.5 * unit)
    }
    let s = attr(extra, NSFont.systemFont(ofSize: 34 * unit, weight: .regular), secondary)
    let ks = size(k, maxW: maxW), ts = size(t, maxW: maxW), ss = size(s, maxW: maxW)
    let gap1 = 26 * unit, gap2 = 22 * unit
    var y = (H - (ks.height + gap1 + ts.height + gap2 + ss.height)) / 2
    k.draw(in: NSRect(x: (W - maxW) / 2, y: y, width: maxW, height: ks.height)); y += ks.height + gap1
    t.draw(in: NSRect(x: (W - maxW) / 2, y: y, width: maxW, height: ts.height)); y += ts.height + gap2
    s.draw(in: NSRect(x: (W - maxW) / 2, y: y, width: maxW, height: ss.height))
case "caption":
    let k = attr(kicker.uppercased(), NSFont.monospacedSystemFont(ofSize: 17 * unit, weight: .semibold), accent, kern: 3 * unit, align: .left)
    let t = attr(text, NSFont.systemFont(ofSize: 38 * unit, weight: .semibold), .white, kern: -0.4 * unit, align: .left)
    let maxW = W * 0.7
    let ks = size(k, maxW: maxW), ts = size(t, maxW: maxW)
    let padX = 30 * unit, padY = 20 * unit, gap = 8 * unit
    let pw = max(ks.width, ts.width) + padX * 2, ph = ks.height + gap + ts.height + padY * 2
    let px = (W - pw) / 2, py = extra == "top" ? H * 0.11 : H - ph - H * 0.12
    let pill = NSBezierPath(roundedRect: NSRect(x: px, y: py, width: pw, height: ph), xRadius: 20 * unit, yRadius: 20 * unit)
    NSColor(white: 0.04, alpha: 0.82).setFill(); pill.fill()
    NSColor(white: 1, alpha: 0.14).setStroke(); pill.lineWidth = 1.2 * unit; pill.stroke()
    k.draw(in: NSRect(x: px + padX, y: py + padY, width: pw - padX * 2, height: ks.height))
    t.draw(in: NSRect(x: px + padX, y: py + padY + ks.height + gap, width: pw - padX * 2, height: ts.height))
default:
    print("unknown kind \(kind)"); exit(1)
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
