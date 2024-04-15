//
//  ContentView.swift
//  DepthMapFileCreator
//
//  Created by Photon Juniper on 2024/4/15.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    
    var body: some View {
        VStack {
            if viewModel.inputCGImage == nil && viewModel.inputDepthCGImage == nil {
                Image(.depthSamplePreview)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 500)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Text("AppDesc")
                    .frame(maxWidth: 500)
                    .padding()
            }
            
            HStack {
                VStack {
                    Button("Pick image file") {
                        viewModel.pickInputFile.toggle()
                    }.fileImporter(
                        isPresented: $viewModel.pickInputFile,
                        allowedContentTypes: [.jpeg, .png, .heic, .heif]
                    ) { result in
                        guard let url = try? result.get() else {
                            return
                        }
                        
                        Task {
                            await viewModel.onInputFilePicked(url)
                        }
                    }
                    
                    if let image = viewModel.inputCGImage {
                        Image(image, scale: 1.0, label: Text(""))
                            .resizable()
                            .scaledToFit()
                    }
                }
                
                VStack {
                    Button("Pick depth map file") {
                        viewModel.pickInputDepthFile.toggle()
                    }.fileImporter(
                        isPresented: $viewModel.pickInputDepthFile,
                        allowedContentTypes: [.jpeg, .png, .heic, .heif]
                    ) { result in
                        guard let url = try? result.get() else {
                            return
                        }
                        
                        Task {
                            await viewModel.onInputDepthFilePicked(url)
                        }
                    }
                    
                    if let image = viewModel.inputDepthCGImage {
                        Image(image, scale: 1.0, label: Text(""))
                            .resizable()
                            .scaledToFit()
                    }
                }
            }
        }
        .padding()
        .controlSize(.large)
        .alert("Success", isPresented: $viewModel.showSuccess) {
            // ignored
        }
        .alert("Error", isPresented: $viewModel.showError) {
            // ignored
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Remove all") {
                    viewModel.removeAll()
                }.disabled(viewModel.inputFile == nil && viewModel.inputDepthFile == nil )
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    viewModel.pickOutputFile.toggle()
                }.fileImporter(
                    isPresented: $viewModel.pickOutputFile,
                    allowedContentTypes: [.folder]
                ) { result in
                    guard let url = try? result.get() else {
                        return
                    }
                    
                    Task {
                        await viewModel.onOutputFilePicked(url)
                    }
                }.disabled(viewModel.inputFile == nil || viewModel.inputDepthFile == nil)
            }
        }
    }
}

#Preview {
    ContentView()
}
