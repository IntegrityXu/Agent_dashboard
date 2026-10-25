import AppKit
import SwiftUI
import MetalKit
import CoreVideo
@preconcurrency import ScreenCaptureKit

// Desktop capture / Metal texture architecture adapted from Liquid-TUI (MIT).
// See Archive/DesktopLens/Liquid-TUI/LICENSE. This experiment is explicitly opt-in.
struct DesktopLens: NSViewRepresentable {
    let dark: Bool
    func makeNSView(context: Context) -> DesktopLensView { DesktopLensView(dark: dark) }
    func updateNSView(_ view: DesktopLensView, context: Context) { view.dark = dark }
    static func dismantleNSView(_ view: DesktopLensView, coordinator: ()) { view.shutdown() }
}

private final class LensFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
}

@MainActor
final class DesktopLensView: MTKView, MTKViewDelegate, SCStreamOutput, SCStreamDelegate {
    var dark: Bool { didSet { if dark != oldValue { draw() } } }
    private var capture: SCStream?
    private var pipeline: MTLRenderPipelineState?
    private var commands: MTLCommandQueue?
    private var cache: CVMetalTextureCache?
    private var latest: LensFrame?
    private var geometryTask: Task<Void, Never>?
    private var configuring = false
    private var geometryPending = false
    private var disposed = false
    private var displayID: CGDirectDisplayID?
    private var content: SCShareableContent?
    private var captureRect = CGRect.zero
    private var frames = 0
    private var renderedFrames = 0
    private var snapshotScheduled = false
    private let margin: CGFloat = 12

    init(dark: Bool) {
        self.dark = dark
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        isPaused = true; enableSetNeedsDisplay = false
        framebufferOnly = true; colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        wantsLayer = true; layer?.isOpaque = false; isHidden = true
        delegate = self
        do {
            guard let device else { throw LensError.noMetal }
            commands = device.makeCommandQueue()
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
            let source = try Self.argument("--glass-shader").map { try String(contentsOfFile: $0, encoding: .utf8) } ?? Self.shader
            let library = try device.makeLibrary(source: source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "lensVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "lensFragment")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            Self.log("metal-ready device=\(device.name)")
        } catch { Self.log("metal-failed \(error.localizedDescription)") }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(geometryChanged), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(waking), name: NSWorkspace.didWakeNotification, object: nil)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleGeometry() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); scheduleGeometry() }
    @objc private func geometryChanged(_ note: Notification) {
        if let changed = note.object as? NSWindow, changed === window { scheduleGeometry() }
    }
    @objc private func sleeping() { geometryTask?.cancel(); stopCapture() }
    @objc private func waking() { scheduleGeometry() }
    private func scheduleGeometry() {
        guard !disposed, window != nil, bounds.width > 1, bounds.height > 1 else { return }
        geometryTask?.cancel()
        geometryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled, let self, !self.disposed else { return }
            await self.configure()
        }
    }
    private func configure() async {
        guard !disposed, pipeline != nil, let window, let screen = window.screen else { return }
        if configuring { geometryPending = true; return }
        configuring = true
        defer {
            configuring = false
            if geometryPending { geometryPending = false; scheduleGeometry() }
        }
        do {
            if content == nil {
                // User explicitly accepted screen-recording access for this preview.
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            }
            guard !disposed, !Task.isCancelled, let content,
                  let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  let display = content.displays.first(where: { $0.displayID == id }),
                  let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier })
            else { return }
            // View-local AppKit -> display-local top-left coordinates. Using the
            // actual screen frame handles displays above/left of the primary.
            let rect = window.convertToScreen(convert(bounds, to: nil))
            let local = CGRect(x: rect.minX - screen.frame.minX - margin,
                               y: screen.frame.maxY - rect.maxY - margin,
                               width: rect.width + 2 * margin, height: rect.height + 2 * margin)
            let region = local.intersection(CGRect(origin: .zero, size: screen.frame.size))
            guard region.width > 0, region.height > 0 else { return }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = region
            configuration.width = max(1, Int(region.width * window.backingScaleFactor))
            configuration.height = max(1, Int(region.height * window.backingScaleFactor))
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 20)
            configuration.queueDepth = 3
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.colorSpaceName = CGColorSpace.sRGB
            let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
            if let capture {
                if displayID != id { try await capture.updateContentFilter(filter) }
                try await capture.updateConfiguration(configuration)
            } else {
                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                capture = stream
                do { try await stream.startCapture() }
                catch { capture = nil; throw error }
            }
            guard !disposed else { stopCapture(); return }
            displayID = id
            // Actual clipping at display edges is represented in the UV transform.
            captureRect = CGRect(x: rect.minX - screen.frame.minX - region.minX,
                                 y: screen.frame.maxY - rect.maxY - region.minY,
                                 width: region.width, height: region.height)
            Self.log("capturing surface=\(Int(bounds.width))x\(Int(bounds.height)) pixels=\(configuration.width)x\(configuration.height)")
        } catch {
            Self.log("capture-failed \(error.localizedDescription)")
        }
    }
    private func stopCapture() {
        let stream = capture; capture = nil; latest = nil; isHidden = true
        if let stream { Task { try? await stream.stopCapture() } }
    }
    func shutdown() {
        disposed = true; geometryTask?.cancel(); stopCapture()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        Self.log("stopped frames=\(frames) rendered=\(renderedFrames)")
    }
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        let frame = LensFrame(buffer)
        Task { @MainActor [weak self] in
            guard let self, !self.disposed, self.capture === stream else { return }
            self.latest = frame; self.frames += 1; self.isHidden = false; self.draw()
        }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let description = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, self.capture === stream else { return }
            self.capture = nil; self.latest = nil; self.isHidden = true
            Self.log("capture-stopped \(description)")
        }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard !disposed, let latest, let cache, let pipeline, let commands,
              captureRect.width > 0, let drawable = currentDrawable, let pass = currentRenderPassDescriptor else { return }
        let buffer = latest.buffer
        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &cvTexture) == kCVReturnSuccess,
            let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture),
            let command = commands.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        // Four float4s keep the CPU and Metal layout explicit (64 bytes).
        var uniforms: [SIMD4<Float>] = [
            SIMD4(Float(bounds.width), Float(bounds.height), 20, dark ? 1 : 0),
            SIMD4(Float(captureRect.minX / captureRect.width), Float(captureRect.minY / captureRect.height),
                  Float(bounds.width / captureRect.width), Float(bounds.height / captureRect.height)),
            SIMD4(Float(captureRect.width), Float(captureRect.height), 7, 0),
            SIMD4(0, 0, 0, 0)
        ]
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: 64, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        // The command buffer retains its texture resources; retain the source
        // IOSurface pixel buffer too until GPU completion.
        command.addCompletedHandler { _ in withExtendedLifetime(latest) {} }
        command.present(drawable); command.commit()
        renderedFrames += 1
        if renderedFrames == 1 {
            Self.log("first-frame-rendered")
            NotificationCenter.default.post(name: .init("local.statusboard.lensReady"), object: nil)
        }
        if !snapshotScheduled, Self.argument("--glass-preview-output") != nil {
            snapshotScheduled = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                await self?.saveWindowPreview()
            }
        }
    }
    private func saveWindowPreview() async {
        guard !disposed, let window, let output = Self.argument("--glass-preview-output") else { return }
        do {
            let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let target = shareable.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { return }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * window.backingScaleFactor)
            config.height = Int(window.frame.height * window.backingScaleFactor)
            config.showsCursor = false; config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(bounds.width < 100 ? "compact-live.png" : "expanded-live.png")
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
            Self.log("preview-saved \(file.lastPathComponent)")
        } catch { Self.log("preview-failed \(error.localizedDescription)") }
    }
    static func argument(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static func log(_ message: String) {
        NSLog("[DesktopLens] %@", message)
        guard let path = argument("--glass-diagnostics"), let handle = FileHandle(forWritingAtPath: path) else { return }
        do { try handle.seekToEnd(); try handle.write(contentsOf: Data((message + "\n").utf8)); try handle.close() }
        catch { try? handle.close() }
    }
    enum LensError: Error { case noMetal }

    // Rounded slab lens: clear center, refractive bevel, RGB dispersion,
    // Fresnel-like edge highlight. UI foreground is never fed into the shader.
    private static let shader = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct Raster { float4 position [[position]]; float2 uv; };
    struct Uniforms { float4 surface; float4 mapping; float4 source; float4 extra; };
    vertex Raster lensVertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        return {float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p};
    }
    float sdf(float2 p, float2 halfSize, float radius) {
        float2 q = abs(p) - halfSize + radius;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    }
    fragment half4 lensFragment(Raster in [[stage_in]], texture2d<half> backdrop [[texture(0)]], constant Uniforms &u [[buffer(0)]]) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
        float2 size = u.surface.xy;
        float2 p = in.uv * size - size * 0.5;
        float d = sdf(p, size * 0.5 - 0.5, min(u.surface.z, min(size.x, size.y) * 0.5));
        float alpha = 1 - smoothstep(-0.6, 0.6, d);
        if (alpha <= 0) return half4(0);
        float2 normal = normalize(float2(
            sdf(p + float2(0.2,0), size * 0.5 - 0.5, u.surface.z) - sdf(p - float2(0.2,0), size * 0.5 - 0.5, u.surface.z),
            sdf(p + float2(0,0.2), size * 0.5 - 0.5, u.surface.z) - sdf(p - float2(0,0.2), size * 0.5 - 0.5, u.surface.z)) + 1e-6);
        float depth = max(0.0, -d);
        float bevel = min(u.source.z, min(size.x, size.y) * 0.15);
        float t = clamp(depth / bevel, 0.0, 1.0);
        float lens = sin(t * M_PI_F) * (1 - t) * 7.5;
        float2 uv = u.mapping.xy + in.uv * u.mapping.zw;
        float2 bend = normal * lens / u.source.xy;
        float2 dispersion = normal * (1 - t) * 0.40 / u.source.xy;
        half3 color;
        color.r = backdrop.sample(s, uv - bend - dispersion).r;
        color.g = backdrop.sample(s, uv - bend).g;
        color.b = backdrop.sample(s, uv - bend + dispersion).b;
        // A small neutral veil preserves the actual background's colors.
        color = mix(color, u.surface.w > 0.5 ? half3(0.02) : half3(0.98), u.surface.w > 0.5 ? 0.10h : 0.14h);
        // Preserve existing light/dark foreground colors even when a bright
        // foreign window passes behind a dark-mode panel.
        float luminance = dot(float3(color), float3(0.2126, 0.7152, 0.0722));
        if (u.surface.w > 0.5) color *= half(min(1.0, 0.26 / max(luminance, 0.001)));
        float light = pow(abs(dot(normal, normalize(float2(-0.65, -0.76)))), 5.0);
        float outer = exp(-pow((depth - 0.65) / 0.48, 2.0));
        float inner = exp(-pow((depth - 2.5) / 0.7, 2.0));
        float soft = exp(-depth / 3.8);
        float shine = outer * (0.35 + 0.55 * light) + inner * (0.12 + 0.30 * light) + soft * 0.12 * light;
        color = mix(color, half3(1), half(clamp(shine, 0.0, 0.9)));
        return half4(color * half(alpha), half(alpha));
    }
    """#
}
