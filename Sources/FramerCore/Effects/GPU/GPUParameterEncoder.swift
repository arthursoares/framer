import Foundation
import simd

public enum GPUParameterEncoder {
    public static func common(_ parameters: GPUEffectCommonParameters) -> SIMD4<Float> {
        SIMD4(
            Float(parameters.brightness),
            Float(parameters.contrast),
            Float(parameters.saturation),
            Float(parameters.gamma)
        )
    }

    public static func geometry(_ parameters: GPUEffectGeometryParameters) -> SIMD4<Float> {
        SIMD4(
            Float(parameters.scale),
            Float(parameters.spacing),
            Float(parameters.outputWidth),
            0
        )
    }
}
