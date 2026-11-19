// Lays pictures out in a labelled grid (for the README's picture of every environment).
//
//   swift tools/grid.swift OUT COLUMNS CELL_WIDTH "Label=picture.png" ...

import AppKit

let a = CommandLine.arguments
let out = a[1], cols = Int(a[2])!, cw = CGFloat(Int(a[3])!)
let items = a.dropFirst(4).map { s -> (String, NSImage) in
    let p = s.split(separator: "=", maxSplits: 1)
    return (String(p[0]), NSImage(contentsOfFile: String(p[1]))!)
}
let ch = (cw * items[0].1.size.height / items[0].1.size.width).rounded(), gap: CGFloat = 6
let rows = (items.count + cols - 1) / cols
let W = Int(CGFloat(cols) * cw + CGFloat(cols - 1) * gap), H = Int(CGFloat(rows) * ch + CGFloat(rows - 1) * gap)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(white: 0.12, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()
for (i, (label, img)) in items.enumerated() {
    let c = CGFloat(i % cols), r = CGFloat(i / cols)
    let rect = NSRect(x: c * (cw + gap), y: CGFloat(H) - (r + 1) * ch - r * gap, width: cw, height: ch)
    img.draw(in: rect)
    let s = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: cw / 30, weight: .semibold),
                                                           .foregroundColor: NSColor.white])
    let sz = s.size(), pad = cw / 60
    NSColor(white: 0, alpha: 0.55).setFill()
    NSBezierPath(roundedRect: NSRect(x: rect.minX + pad, y: rect.maxY - pad - sz.height - pad, width: sz.width + 2 * pad,
                                     height: sz.height + pad), xRadius: pad / 1.5, yRadius: pad / 1.5).fill()
    s.draw(at: NSPoint(x: rect.minX + 2 * pad, y: rect.maxY - pad - sz.height - pad / 2))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
