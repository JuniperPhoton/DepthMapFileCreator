import CoreMedia
import CoreVideo
import Metal
import AVFoundation
import CoreImage

/// The main target should contain the implementation of GrayscaleToDepth+Native.metal
class GrayscaleToDepthConverter {
    let description: String = "Grayscale to Depth Converter"
    
    var isPrepared = false
    
    private let metalDevice = MTLCreateSystemDefaultDevice()!
    
    private var computePipelineState: MTLComputePipelineState?
    
    private lazy var commandQueue: MTLCommandQueue? = {
        return self.metalDevice.makeCommandQueue()
    }()
    
    private var textureCache: CVMetalTextureCache!
    
    required init() {
        let defaultLibrary = metalDevice.makeDefaultLibrary()
        let kernelFunction = defaultLibrary!.makeFunction(name: "grayscaleToDepth")
        do {
            computePipelineState = try metalDevice.makeComputePipelineState(function: kernelFunction!)
        } catch {
            fatalError("Unable to create depth converter pipeline state. (\(error))")
        }
    }
    
    func prepare() {
        if isPrepared {
            return
        }
        
        reset()
        
        var metalTextureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &metalTextureCache) != kCVReturnSuccess {
            print("Unable to allocate depth converter texture cache")
        } else {
            textureCache = metalTextureCache
        }
        
        isPrepared = true
    }
    
    public func reset() {
        textureCache = nil
        isPrepared = false
    }
    
    private func createOutputPixelBuffer(input: CVPixelBuffer, targetCVPixelFormat: OSType) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey as String: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: kCFBooleanTrue!,
            kCVPixelBufferMetalCompatibilityKey as String: kCFBooleanTrue!
        ] as CFDictionary
        
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(width),
            Int(height),
            targetCVPixelFormat,
            attributes,
            &pixelBuffer
        )
        return pixelBuffer
    }
    
    /// Convert the input grayscale BGRA8 ``CVPixelBuffer`` to the target disparity map.
    func render(input: CVPixelBuffer, targetCVPixelFormat: OSType) -> CVPixelBuffer? {
        if !isPrepared {
            print("Invalid state: Not prepared")
            return nil
        }
        
        guard let targetFormat = PixelFormatUtils.shared.getMetalFormatForDepth(cvPixelFormat: targetCVPixelFormat) else {
            print("Invalid state: format not supported")
            return nil
        }
        
        guard let outputPixelBuffer = createOutputPixelBuffer(input: input, targetCVPixelFormat: targetCVPixelFormat) else {
            print("Allocation failure: Could not get pixel buffer from pool (\(self.description))")
            return nil
        }
        
        guard let inputTexture = MetalUtils.shared.makeTextureFromCVPixelBuffer(
            pixelBuffer: input,
            textureFormat: .bgra8Unorm,
            textureCache: textureCache
        ) else {
            print("failed to make inputTexture")
            return nil
        }
        
        guard let outputTexture = MetalUtils.shared.makeTextureFromCVPixelBuffer(
            pixelBuffer: outputPixelBuffer,
            textureFormat: targetFormat,
            textureCache: textureCache
        ) else {
            print("failed to make outputTexture")
            return nil
        }
        
        // Set up command queue, buffer, and encoder
        guard let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create Metal command queue")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return nil
        }
        
        commandEncoder.label = "Grayscale to Depth"
        commandEncoder.setComputePipelineState(computePipelineState!)
        commandEncoder.setTexture(inputTexture, index: 0)
        commandEncoder.setTexture(outputTexture, index: 1)
        
        // Set up the thread groups.
        let width = computePipelineState!.threadExecutionWidth
        let height = computePipelineState!.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadgroup = MTLSizeMake(width, height, 1)
        let threadgroupsPerGrid = MTLSize(width: (inputTexture.width + width - 1) / width,
                                          height: (inputTexture.height + height - 1) / height,
                                          depth: 1)
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputPixelBuffer
    }
}

class PixelFormatUtils {
    public static let shared = PixelFormatUtils()
    
    private init() {
        // empty
    }
    
    public func getMetalFormatForDepth(cvPixelFormat: OSType) -> MTLPixelFormat? {
        if cvPixelFormat == kCVPixelFormatType_DisparityFloat16 || cvPixelFormat == kCVPixelFormatType_DepthFloat16 {
            return .r16Float
        }
        
        if cvPixelFormat == kCVPixelFormatType_DisparityFloat32 || cvPixelFormat == kCVPixelFormatType_DepthFloat32 {
            return .r32Float
        }
        
        return nil
    }
}

class MetalUtils {
    static let shared = MetalUtils()
    
    private init() {
        // empty
    }
    
    func allocateOutputBuffers(
        with formatDescription: CMFormatDescription,
        outputRetainedBufferCountHint: Int
    ) -> CVPixelBufferPool? {
        let inputDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let outputPixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(inputDimensions.width),
            kCVPixelBufferHeightKey as String: Int(inputDimensions.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: outputRetainedBufferCountHint]
        var cvPixelBufferPool: CVPixelBufferPool?
        // Create a pixel buffer pool with the same pixel attributes as the input format description
        CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                poolAttributes as NSDictionary?,
                                outputPixelBufferAttributes as NSDictionary?,
                                &cvPixelBufferPool)
        guard let pixelBufferPool = cvPixelBufferPool else {
            print("Allocation failure: Could not create pixel buffer pool")
            return nil
        }
        return pixelBufferPool
    }
    
    func makeTextureFromCVPixelBuffer(
        pixelBuffer: CVPixelBuffer,
        textureFormat: MTLPixelFormat,
        textureCache: CVMetalTextureCache
    ) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Create a Metal texture from the image buffer
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            textureFormat,
            width,
            height,
            0,
            &cvTextureOut
        )
        
        guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
            print("Depth converter failed to create preview texture of texture format \(textureFormat), size: \(width)x\(height)")
            
            CVMetalTextureCacheFlush(textureCache, 0)
            
            return nil
        }
        
        return texture
    }
}
