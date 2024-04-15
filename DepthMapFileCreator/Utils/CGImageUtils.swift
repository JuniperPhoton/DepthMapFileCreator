//
//  CGImageUtils.swift
//  DepthMapFileCreator
//
//  Created by Photon Juniper on 2024/4/15.
//

import Foundation
import AVFoundation

class CGImageUtils {
    static let shared = CGImageUtils()
    
    func getProperties(data: Data) -> Dictionary<String, Any>? {
        let options: [String: Any] = [
            kCGImageSourceShouldCacheImmediately as String: false,
        ]
        
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        
        guard let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else {
            return nil
        }
        
        guard let map = metadata as? Dictionary<String, Any> else {
            return nil
        }
        return map
    }
    
    /// Save the ``CGImage`` to a specified file, as a ``UTType``.
    /// - parameter file: file URL  to be saved into
    /// - parameter cgImage: the image to be saved
    /// - parameter utType: a ``UTType`` to identify the image format
    func saveToFile(
        file: URL,
        cgImage: CGImage,
        utType: UTType,
        properties: CFDictionary? = nil,
        auxiliaryData: Dictionary<AuxiliaryDataType, CFDictionary?> = [:]
    ) throws -> URL {
        guard let dest = CGImageDestinationCreateWithURL(
            file as CFURL,
            utType.identifier as CFString,
            1,
            nil
        ) else {
            throw IOError("Failed to create image destination")
        }
        
        CGImageDestinationAddImage(dest, cgImage, properties)
        
        for (k, v) in auxiliaryData {
            if let dic = v {
                CGImageDestinationAddAuxiliaryDataInfo(dest, k.cgImageKey, dic)
            }
        }
        
        if CGImageDestinationFinalize(dest) {
            return file
        }
        
        throw IOError("Failed to finalize")
    }

    private init() {
        // empty
    }
}

enum AuxiliaryDataType: CaseIterable {
    case hdrGainMap
    case depth
    case disparity
    case portraitEffectsMatte
    
    var cgImageKey: CFString {
        switch self {
        case .hdrGainMap:
            kCGImageAuxiliaryDataTypeHDRGainMap
        case .depth:
            kCGImageAuxiliaryDataTypeDepth
        case .disparity:
            kCGImageAuxiliaryDataTypeDisparity
        case .portraitEffectsMatte:
            kCGImageAuxiliaryDataTypePortraitEffectsMatte
        }
    }
}

struct IOError: Error {
    let message: String
    
    init(_ message: String = "") {
        self.message = message
    }
}
