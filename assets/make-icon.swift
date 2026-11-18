// Draws the-great-gui's icon: a prompt (❯ and a block cursor) on a dark tile, in the ds-next terminal
// design system's dark roles. Run assets/make-icon.sh to rebuild assets/AppIcon.icns.
//
//   swift assets/make-icon.swift OUT.png
import AppKit

// The dark roles from Sources/TerminalDesign/Tokens.swift. An icon cannot import the package, so the
// values are repeated here; if tokens.json changes them, change these and rebuild.
let bg: UInt32 = 0x1d1f20, surface: UInt32 = 0x2b2b2d, rule: UInt32 = 0x424244
let accent: UInt32 = 0x94bce3, strong: UInt32 = 0xb5d9fd, text: UInt32 = 0xe7e7ea

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ top: CGColor, _ bottom: CGColor) -> CGGradient {
    CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
}

// The tile: macOS's icon grid is an 824pt rounded square centred on a 1024pt canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.45))
ctx.addPath(tilePath); ctx.setFillColor(rgb(bg)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
ctx.drawLinearGradient(gradient(rgb(surface), rgb(bg)), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// A soft glow behind the prompt, in the accent.
let glow = CGGradient(colorsSpace: space, colors: [rgb(accent, 0.20), rgb(accent, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 470, y: 512), startRadius: 0,
                       endCenter: CGPoint(x: 470, y: 512), endRadius: 430, options: [])
ctx.restoreGState()

// The frame: one thin rule, as the design's boxes are drawn.
let frame = CGPath(roundedRect: tile.insetBy(dx: 58, dy: 58), cornerWidth: 132, cornerHeight: 132, transform: nil)
ctx.addPath(frame); ctx.setStrokeColor(rgb(rule)); ctx.setLineWidth(9); ctx.strokePath()

// The prompt: ❯ in the "you" voice (strong, shading to accent).
let chevron = CGMutablePath()
chevron.move(to: CGPoint(x: 318, y: 684)); chevron.addLine(to: CGPoint(x: 506, y: 512)); chevron.addLine(to: CGPoint(x: 318, y: 340))
let prompt = chevron.copy(strokingWithWidth: 84, lineCap: .round, lineJoin: .round, miterLimit: 10)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: rgb(accent, 0.55))
ctx.addPath(prompt); ctx.setFillColor(rgb(strong)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(prompt); ctx.clip()
ctx.drawLinearGradient(gradient(rgb(strong), rgb(accent)), start: CGPoint(x: 412, y: 726), end: CGPoint(x: 412, y: 298), options: [])
ctx.restoreGState()

// The cursor: a block in the text colour, as the design's cursor is.
let cursor = CGPath(roundedRect: CGRect(x: 592, y: 298, width: 150, height: 428), cornerWidth: 20, cornerHeight: 20, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: rgb(text, 0.35))
ctx.addPath(cursor); ctx.setFillColor(rgb(text)); ctx.fillPath()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
