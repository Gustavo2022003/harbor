import AppKit

// Gera o ícone do Harbor (1024x1024) — uso: make_icon <saida.png>
let S: CGFloat = 1024
let out = CommandLine.arguments[1]

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Coordenadas com y para baixo
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: Squircle de fundo (grade do macOS: 824pt de conteúdo, margem 100)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: rgb(0x000000, 0.45))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x0A1830))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()

// Oceano noturno
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x183A66), rgb(0x0B1D3A), rgb(0x040A16)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

// Brilho quente atrás da âncora
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFF9F0A, 0.32), rgb(0xFF9F0A, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 560), endRadius: 360, options: [])

// Ondas na base
func wave(y: CGFloat, amp: CGFloat, len: CGFloat, phase: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 80, y: y))
    var x: CGFloat = 80
    while x <= 944 {
        p.addLine(to: CGPoint(x: x, y: y + sin((x / len) * .pi * 2 + phase) * amp))
        x += 4
    }
    return p
}
for (i, w) in [(820.0, 0.22), (862.0, 0.14), (900.0, 0.08)].enumerated() {
    ctx.addPath(wave(y: CGFloat(w.0), amp: 12, len: 170, phase: CGFloat(i) * 1.3))
    ctx.setStrokeColor(rgb(0x64D2FF, CGFloat(w.1)))
    ctx.setLineWidth(10)
    ctx.setLineCap(.round)
    ctx.strokePath()
}

// Reflexo de vidro no topo do tile
let sheen = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 420), options: [])

// MARK: Island (notch) no topo
let island = CGRect(x: 337, y: 150, width: 350, height: 86)
let islandPath = CGPath(roundedRect: island, cornerWidth: 43, cornerHeight: 43, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 26, color: rgb(0xFF9F0A, 0.35))
ctx.addPath(islandPath)
ctx.setFillColor(rgb(0x000000))
ctx.fillPath()
ctx.restoreGState()
ctx.addPath(islandPath)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.12))
ctx.setLineWidth(2)
ctx.strokePath()

// Mini capa de álbum (esquerda)
let art = CGRect(x: 370, y: 172, width: 42, height: 42)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: art, cornerWidth: 11, cornerHeight: 11, transform: nil))
ctx.clip()
let artG = CGGradient(colorsSpace: space, colors: [rgb(0xFFB340), rgb(0xFF375F)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(artG, start: CGPoint(x: art.minX, y: art.minY), end: CGPoint(x: art.maxX, y: art.maxY), options: [])
ctx.restoreGState()

// Barras do visualizador (direita)
let bars: [CGFloat] = [18, 34, 24, 40]
for (i, h) in bars.enumerated() {
    let x = 606 + CGFloat(i) * 15
    let r = CGRect(x: x, y: 193 - h / 2, width: 8, height: h)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
}
ctx.setFillColor(rgb(0xFF9F0A))
ctx.fillPath()

// MARK: Âncora
var parts: [CGPath] = []
func addStroke(_ p: CGPath, _ w: CGFloat) {
    parts.append(p.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10))
}
// Argola
let ring = CGMutablePath()
ring.addEllipse(in: CGRect(x: 512 - 46, y: 318 - 46, width: 92, height: 92))
addStroke(ring, 34)
// Haste
let shank = CGMutablePath()
shank.move(to: CGPoint(x: 512, y: 364))
shank.addLine(to: CGPoint(x: 512, y: 772))
addStroke(shank, 46)
// Cepo (barra horizontal)
let stock = CGMutablePath()
stock.move(to: CGPoint(x: 398, y: 438))
stock.addLine(to: CGPoint(x: 626, y: 438))
addStroke(stock, 40)
// Braços (arco)
let arms = CGMutablePath()
arms.addArc(center: CGPoint(x: 512, y: 556), radius: 222,
            startAngle: .pi * 0.11, endAngle: .pi * 0.89, clockwise: false)
addStroke(arms, 44)
// Pontas (flukes)
func fluke(tip: CGPoint, a: CGPoint, b: CGPoint) {
    let p = CGMutablePath()
    p.move(to: tip); p.addLine(to: a); p.addLine(to: b); p.closeSubpath()
    parts.append(p.copy(strokingWithWidth: 14, lineCap: .round, lineJoin: .round, miterLimit: 10))
    parts.append(p)
}
let rx = 512 + 222 * cos(CGFloat.pi * 0.11), ry = 556 + 222 * sin(CGFloat.pi * 0.11)
let lx = 512 + 222 * cos(CGFloat.pi * 0.89), ly = ry
fluke(tip: CGPoint(x: rx + 44, y: ry - 70), a: CGPoint(x: rx - 46, y: ry - 22), b: CGPoint(x: rx + 40, y: ry + 34))
fluke(tip: CGPoint(x: lx - 44, y: ly - 70), a: CGPoint(x: lx + 46, y: ly - 22), b: CGPoint(x: lx - 40, y: ly + 34))

// Âncora: camada única (sombra + degradê aplicados ao conjunto)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 24, color: rgb(0x000000, 0.5))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.setFillColor(rgb(0xFFFFFF))
for p in parts { ctx.addPath(p); ctx.fillPath() }
ctx.setBlendMode(.sourceIn)
let ag = CGGradient(colorsSpace: space, colors: [rgb(0xFFD27A), rgb(0xFF9F0A), rgb(0xFF6A00)] as CFArray,
                    locations: [0, 0.45, 1])!
ctx.drawLinearGradient(ag, start: CGPoint(x: 512, y: 250), end: CGPoint(x: 512, y: 800),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
let spec = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.3), rgb(0xFFFFFF, 0)] as CFArray,
                      locations: [0, 1])!
ctx.setBlendMode(.sourceAtop)
ctx.drawLinearGradient(spec, start: CGPoint(x: 300, y: 300), end: CGPoint(x: 560, y: 560), options: [.drawsBeforeStartLocation])
ctx.endTransparencyLayer()
ctx.restoreGState()

ctx.restoreGState() // fim do clip do tile

// Borda fina do tile
ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08))
ctx.setLineWidth(3)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("ok", out)
