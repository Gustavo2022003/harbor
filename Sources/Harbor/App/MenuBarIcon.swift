import AppKit

/// Âncora desenhada em código para a barra de menus (o SF Symbols não tem uma).
/// É uma imagem *template*: o macOS a pinta de preto/branco conforme a barra.
enum MenuBarIcon {
    static func anchor(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width / 18          // desenho feito numa grade 18×18
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
            NSColor.black.setStroke()

            let path = NSBezierPath()
            path.lineWidth = 1.55 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // argola
            path.appendOval(in: NSRect(x: 7.1 * s, y: 13.0 * s, width: 3.8 * s, height: 3.8 * s))
            // haste
            path.move(to: p(9, 13.0)); path.line(to: p(9, 2.1))
            // travessa
            path.move(to: p(5.6, 10.9)); path.line(to: p(12.4, 10.9))
            // braços (arco inferior)
            path.appendArc(withCenter: p(9, 8.1), radius: 6 * s, startAngle: 202, endAngle: 338, clockwise: false)
            // pontas (unhas) nas duas extremidades
            // ponta de flecha seguindo a tangente do arco (lado direito espelhado)
            for mirror in [false, true] {
                func m(_ x: CGFloat, _ y: CGFloat) -> NSPoint { p(mirror ? 18 - x : x, y) }
                path.move(to: m(5.0, 5.9)); path.line(to: m(2.8, 7.5)); path.line(to: m(2.1, 4.8))
            }
            path.stroke()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Harbor"
        return img
    }
}
