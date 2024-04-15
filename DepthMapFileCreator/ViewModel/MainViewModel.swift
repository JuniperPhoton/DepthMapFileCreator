//
//  MainViewModel.swift
//  DepthMapFileCreator
//
//  Created by Photon Juniper on 2024/4/15.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

class MainViewModel: ObservableObject {
    @Published var pickInputFile = false
    @Published var pickInputDepthFile = false
    @Published var pickOutputFile = false
    
    @Published var inputCGImage: CGImage? = nil
    @Published var inputDepthCGImage: CGImage? = nil
    
    @Published var inputFile: URL? = nil
    @Published var inputDepthFile: URL? = nil
    
    @Published var showSuccess = false
    @Published var showError = false
    
    @MainActor
    func onInputFilePicked(_ url: URL) async {
        self.inputFile = url
        self.inputCGImage = await loadImage(url)
    }
    
    @MainActor
    func onInputDepthFilePicked(_ url: URL) async {
        self.inputDepthFile = url
        self.inputDepthCGImage = await loadImage(url)
    }
    
    @MainActor
    func onOutputFilePicked(_ url: URL) async {
        let success = await saveImage(folder: url)
        if success {
            showSuccess = true
        } else {
            showError = true
        }
    }
    
    @MainActor
    func removeAll() {
        self.inputCGImage = nil
        self.inputDepthCGImage = nil
        self.inputFile = nil
        self.inputDepthFile = nil
    }
    
    private func saveImage(folder: URL) async -> Bool {
        guard let inputFile = inputFile,
              let inputCGImage = inputCGImage,
              let inputDepthCGImage = inputDepthCGImage else {
            print("error: failed to get input data")
            return false
        }
        
        let _ = folder.startAccessingSecurityScopedResource()
        let _ = inputFile.startAccessingSecurityScopedResource()
        defer {
            folder.stopAccessingSecurityScopedResource()
            inputFile.stopAccessingSecurityScopedResource()
        }
        
        guard let inputData = try? Data(contentsOf: inputFile) else {
            print("error: failed to get data")
            return false
        }
        
        let name = inputFile.deletingPathExtension().lastPathComponent
        let fileExtension = inputFile.pathExtension
        let utType = UTType(filenameExtension: fileExtension) ?? .jpeg
        
        let tempFile = folder.appendingPathComponent(
            "\(name)_with_depth",
            conformingTo: utType
        )
        
        let ciImage = CIImage(cgImage: inputDepthCGImage)
        
        guard let depthData = DepthMapUtils.shared.createAVDepthData(
            ciContext: CIContext(),
            grayscaleImage: ciImage,
            originalDepthData: nil
        ) else {
            print("error: failed to get depth data")
            return false
        }
        
        var auxiliaryData = [AuxiliaryDataType: CFDictionary?]()
        
        var auxDataType: NSString?
        if let depthDic = depthData.dictionaryRepresentation(forAuxiliaryDataType: &auxDataType) {
            if auxDataType == kCGImageAuxiliaryDataTypeDisparity {
                auxiliaryData[.disparity] = depthDic as CFDictionary
            } else if auxDataType == kCGImageAuxiliaryDataTypeDepth {
                auxiliaryData[.depth] = depthDic as CFDictionary
            }
        }
        
        let properties = CGImageUtils.shared.getProperties(data: inputData) ?? [:]
        
        do {
            let _ = try CGImageUtils.shared.saveToFile(
                file: tempFile,
                cgImage: inputCGImage,
                utType: utType,
                properties: properties as CFDictionary,
                auxiliaryData: auxiliaryData
            )
            return true
        } catch {
            print("error on saving to file \(error)")
        }
        
        return false
    }
    
    private func loadImage(_ url: URL) async -> CGImage? {
        let _ = url.startAccessingSecurityScopedResource()
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
