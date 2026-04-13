import Foundation
import Metal
import CoreImage

public final class GPUCommandContext: @unchecked Sendable {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let ciContext: CIContext

    private init(device: MTLDevice, commandQueue: MTLCommandQueue, ciContext: CIContext) {
        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = ciContext
    }

    public static func makeDefault() throws -> GPUCommandContext {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw GPUEffectsPlatformError.metalUnavailable
        }

        let ciContext = CIContext(mtlDevice: device)
        return GPUCommandContext(device: device, commandQueue: commandQueue, ciContext: ciContext)
    }
}
