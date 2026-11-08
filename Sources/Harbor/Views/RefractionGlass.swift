import MetalKit
import SwiftUI

/// Liquid Glass "de verdade": refração (deslocamento) nas bordas + blur + saturate(190%) + brightness(1.05),
/// desenhado em Metal sobre a captura do que está atrás da janela.
struct RefractionGlass: NSViewRepresentable {
    /// Recuo lateral do vidro, em pontos (as abas curvas do topo do notch ficam de fora).
    var inset: CGFloat
    /// Raio dos cantos, em pontos.
    var radius: CGFloat
    /// Quanto o vidro se estende acima da view (esconde os cantos de cima).
    var topExtend: CGFloat
    /// Escurecimento 0...1.
    var dim: Double

    func makeNSView(context: Context) -> RefractionView {
        let v = RefractionView()
        v.params = (inset, radius, topExtend, dim)
        return v
    }

    func updateNSView(_ v: RefractionView, context: Context) {
        v.params = (inset, radius, topExtend, dim)
    }

    static func dismantleNSView(_ v: RefractionView, coordinator: ()) {
        v.isPaused = true
    }
}

private struct Uniforms {
    var viewSize: SIMD2<Float>
    var viewOrigin: SIMD2<Float>
    var texSize: SIMD2<Float>
    var inset: Float
    var radius: Float
    var topExtend: Float
    var bezel: Float
    var strength: Float
    var saturation: Float
    var brightness: Float
    var dim: Float
    var whiteTint: Float
    var pxScale: Float
}

final class RefractionView: MTKView {
    var params: (inset: CGFloat, radius: CGFloat, topExtend: CGFloat, dim: Double) = (0, 0, 0, 0)

    private static var pipeline: MTLRenderPipelineState?
    private let capture = BackdropCapture.shared
    private lazy var queue = capture.device.makeCommandQueue()

    init() {
        super.init(frame: .zero, device: BackdropCapture.shared.device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        preferredFramesPerSecond = 60
        autoResizeDrawable = true
        layer?.isOpaque = false
        Self.buildPipeline(device: BackdropCapture.shared.device)
    }

    required init(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        if window != nil {
            isPaused = false
            capture.retain()
        } else {
            isPaused = true
            capture.release()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let rpd = currentRenderPassDescriptor, let drawable = currentDrawable,
              let cb = queue?.makeCommandBuffer() else { return }
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }

        if let tex = capture.blurred, let pipeline = Self.pipeline, let win = window,
           capture.capturePointSize.width > 0 {
            let ds = drawableSize
            let drawScale = Float(ds.width / max(bounds.width, 1))
            let capScale = Float(CGFloat(tex.width) / capture.capturePointSize.width)
            let r = convert(bounds, to: nil) // coordenadas da janela (origem embaixo)
            let originPts = CGPoint(x: r.minX, y: win.frame.height - r.maxY)

            var u = Uniforms(
                viewSize: SIMD2(Float(ds.width), Float(ds.height)),
                viewOrigin: SIMD2(Float(originPts.x) * capScale, Float(originPts.y) * capScale),
                texSize: SIMD2(Float(tex.width), Float(tex.height)),
                inset: Float(params.inset) * drawScale,
                radius: Float(params.radius) * drawScale,
                topExtend: Float(params.topExtend) * drawScale,
                bezel: 26 * drawScale,
                strength: 16 * drawScale,
                saturation: 1.9,
                brightness: 1.05,
                dim: Float(params.dim),
                whiteTint: 0.08,
                pxScale: capScale / drawScale)
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentTexture(tex, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    private static func buildPipeline(device: MTLDevice) {
        guard pipeline == nil else { return }
        do {
            let lib = try device.makeLibrary(source: shaderSource, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "glass_vertex")
            d.fragmentFunction = lib.makeFunction(name: "glass_fragment")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            NSLog("Harbor: falha ao compilar shader de vidro: \(error)")
        }
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 pos [[position]]; float2 uv; };

    vertex VOut glass_vertex(uint vid [[vertex_id]]) {
        float2 p[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
        VOut o;
        o.pos = float4(p[vid], 0, 1);
        o.uv = float2((p[vid].x + 1) * 0.5, 1 - (p[vid].y + 1) * 0.5);
        return o;
    }

    struct Uniforms {
        float2 viewSize;
        float2 viewOrigin;
        float2 texSize;
        float inset;
        float radius;
        float topExtend;
        float bezel;
        float strength;
        float saturation;
        float brightness;
        float dim;
        float whiteTint;
        float pxScale;
    };

    static float sdRoundBox(float2 p, float2 b, float r) {
        float2 q = abs(p) - b + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    static float sdGlass(float2 px, constant Uniforms& u) {
        float2 mn = float2(u.inset, -u.topExtend);
        float2 mx = float2(u.viewSize.x - u.inset, u.viewSize.y);
        float2 c = (mn + mx) * 0.5;
        float2 b = (mx - mn) * 0.5;
        return sdRoundBox(px - c, b, min(u.radius, min(b.x, b.y)));
    }

    fragment float4 glass_fragment(VOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]],
                                   constant Uniforms& u [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 px = in.uv * u.viewSize;
        float d = sdGlass(px, u);
        float alpha = clamp(0.5 - d, 0.0, 1.0);
        if (alpha <= 0.0) { return float4(0.0); }

        // Normal da borda (aponta para fora)
        float e = 1.0;
        float2 g = float2(sdGlass(px + float2(e, 0), u) - sdGlass(px - float2(e, 0), u),
                          sdGlass(px + float2(0, e), u) - sdGlass(px - float2(0, e), u));
        float2 n = length(g) > 1e-4 ? normalize(g) : float2(0.0);

        // Refração: perto da borda os pixels são "puxados" para dentro (efeito lente)
        float t = clamp(-d / u.bezel, 0.0, 1.0);
        float k = (1.0 - t) * (1.0 - t);
        float2 offset = -n * k * u.strength;

        float2 base = u.viewOrigin + (px + offset) * u.pxScale;
        float2 ca = n * k * 2.5 * u.pxScale; // leve aberração cromática na borda
        float3 col;
        col.r = tex.sample(s, (base - ca) / u.texSize).r;
        col.g = tex.sample(s, base / u.texSize).g;
        col.b = tex.sample(s, (base + ca) / u.texSize).b;

        // saturate(190%) brightness(1.05)
        float l = dot(col, float3(0.2126, 0.7152, 0.0722));
        col = mix(float3(l), col, u.saturation) * u.brightness;
        // background: rgba(255,255,255,0.08)
        col = mix(col, float3(1.0), u.whiteTint);
        // brilho especular na faixa da borda
        col += k * 0.08;
        // escurecer (legibilidade)
        col = mix(col, float3(0.0), u.dim);
        col = clamp(col, 0.0, 1.0);
        return float4(col * alpha, alpha);
    }
    """
}
