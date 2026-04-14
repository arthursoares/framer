// MetalTextureSupport.swift
// Texture helpers for the Effects GPU path:
//   - CGImage → MTLTexture (source images via MTKTextureLoader)
//   - PNG-on-disk LUT atlases → cached MTLTexture (resolved via
//     TextureFrameProvider.searchPaths so the same `assets/textures/*.png`
//     fall through that the CPU ShaderASCIIRenderer uses)
//   - MTLTexture → CGImage readback via a shared CIContext
//
// LUT loads are cached forever because the atlases are immutable shipped assets.
// Source-image uploads are NOT cached — callers may render different images
// every frame.

import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import Metal
import MetalKit

public enum MetalTextureSupport {

    // MARK: - Shared CIContext (for readback)
    //
    // CIContext is expensive to build and thread-safe to use. One per device is
    // sufficient. Lazily initialised on first readback call.

    private static let contextLock = NSLock()
    nonisolated(unsafe) private static var _ciContext: CIContext?

    private static func ciContext(for device: MTLDevice) -> CIContext {
        contextLock.lock()
        defer { contextLock.unlock() }
        if let ctx = _ciContext { return ctx }
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        ]
        let ctx = CIContext(mtlDevice: device, options: options)
        _ciContext = ctx
        return ctx
    }

    // MARK: - CGImage → MTLTexture

    /// Upload a `CGImage` to a private-storage `MTLTexture` suitable as a
    /// fragment-shader input. Disables sRGB conversion so colour values come
    /// through unchanged (the .metal helpers expect linear/passthrough input).
    ///
    /// Inputs are normalised to `.premultipliedLast` RGBA before upload.
    /// Without this, `MTKTextureLoader` internally attempts
    /// `CGBitmapContextCreate` using the source image's native alpha info —
    /// some images (notably certain PNG/HEIC decodes) produce
    /// `.alphaLast` (non-premultiplied), which `CGBitmapContextCreate`
    /// rejects with "unsupported parameter combination". The loader then
    /// falls back to an incorrect path, producing visibly wrong colours.
    public static func makeTexture(
        from image: CGImage,
        device: MTLDevice
    ) throws -> MTLTexture {
        let normalized = normalizedForTextureUpload(image)
        let loader = MTKTextureLoader(device: device)
        do {
            return try loader.newTexture(cgImage: normalized, options: [
                .SRGB: NSNumber(value: false),
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            ])
        } catch {
            throw MetalEffectError.textureLoadFailed(error.localizedDescription)
        }
    }

    /// If `image` already has a CGBitmapContext-compatible alpha layout,
    /// returns it unchanged. Otherwise redraws into a `.premultipliedLast`
    /// RGBA8 context. The compatible set is the one Core Graphics accepts
    /// for 8-bit-per-component RGB contexts per Apple's supported-pixel-
    /// formats documentation.
    private static func normalizedForTextureUpload(_ image: CGImage) -> CGImage {
        let rawMasked = image.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
        let supported: Set<UInt32> = [
            CGImageAlphaInfo.premultipliedLast.rawValue,
            CGImageAlphaInfo.premultipliedFirst.rawValue,
            CGImageAlphaInfo.noneSkipLast.rawValue,
            CGImageAlphaInfo.noneSkipFirst.rawValue,
            CGImageAlphaInfo.none.rawValue,
        ]
        if supported.contains(rawMasked) {
            return image
        }

        let w = image.width
        let h = image.height
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image  // Best effort: let MTKTextureLoader fail downstream.
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    // MARK: - LUT atlas loader (cached)

    private static let lutLock = NSLock()
    nonisolated(unsafe) private static var lutCache: [String: MTLTexture] = [:]

    /// Load an atlas PNG by name (e.g. "edgesASCII.png") from
    /// `TextureFrameProvider.searchPaths`. Cached by name across calls. The
    /// returned texture is `.r8Unorm`-equivalent — the shader reads `.r` only.
    ///
    /// Returns `nil` if the file isn't found in any search path; callers should
    /// fall back to the CPU procedural path.
    public static func loadLUTTexture(
        named name: String,
        device: MTLDevice
    ) throws -> MTLTexture? {
        // LUT loads are O(once per atlas name) across the app lifetime, so
        // holding the lock through the filesystem read + GPU upload is cheaper
        // than a release/reacquire dance — and it eliminates the check-then-act
        // race where two concurrent first-time callers would each upload.
        lutLock.lock()
        defer { lutLock.unlock() }

        if let cached = lutCache[name] { return cached }

        var foundURL: URL?
        for searchPath in TextureFrameProvider.searchPaths {
            let url = searchPath.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                foundURL = url
                break
            }
        }
        guard let url = foundURL else { return nil }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MetalEffectError.textureLoadFailed(name)
        }

        let texture = try makeTexture(from: cgImage, device: device)
        lutCache[name] = texture
        return texture
    }

    // MARK: - Output texture allocation

    /// Allocate a private-storage render target sized for the requested output.
    public static func makeRenderTarget(
        width: Int,
        height: Int,
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .rgba8Unorm
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let tex = device.makeTexture(descriptor: descriptor) else {
            throw MetalEffectError.textureCreationFailed
        }
        return tex
    }

    // MARK: - MTLTexture → CGImage (readback)

    /// Read a rendered MTLTexture back into a `CGImage` via CoreImage. Uses the
    /// shared CIContext keyed off the texture's device. The shader's clip-space
    /// → texture-space mapping flips Y; `.downMirrored` corrects that on the
    /// way out.
    public static func makeCGImage(
        from texture: MTLTexture
    ) throws -> CGImage {
        let device = texture.device
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let imageOptions: [CIImageOption: Any] = [.colorSpace: sRGB]
        guard let base = CIImage(mtlTexture: texture, options: imageOptions) else {
            throw MetalEffectError.readbackFailed
        }
        let oriented = base.oriented(.downMirrored)

        let ctx = ciContext(for: device)
        guard let cg = ctx.createCGImage(
            oriented,
            from: oriented.extent,
            format: .RGBA8,
            colorSpace: sRGB
        ) else {
            throw MetalEffectError.readbackFailed
        }
        return cg
    }
}
