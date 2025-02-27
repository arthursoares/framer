import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var settings = FramerSettings()
    @State private var showingImagePicker = false
    @State private var processedImage: UIImage?
    @State private var isProcessing = false
    @State private var showingSettings = false
    @State private var saveComplete = false
    @State private var saveError: Error?
    
    var body: some View {
        NavigationView {
            VStack {
                if let selectedImage = settings.selectedImage {
                    VStack {
                        ImagePreview(image: selectedImage, processedImage: processedImage, isProcessing: isProcessing)
                            .padding()
                        
                        Button(action: processImage) {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("Preview with Frame")
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        if let processedImage = processedImage {
                            Button(action: saveImage) {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Save to Photos")
                                }
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .padding(.top, 10)
                        }
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .foregroundColor(.gray)
                        
                        Text("Select a photo to frame")
                            .font(.headline)
                        
                        Button(action: { showingImagePicker = true }) {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                Text("Select Photo")
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Framer")
            .navigationBarItems(
                leading: settings.selectedImage != nil ? Button(action: {
                    settings.selectedImage = nil
                    processedImage = nil
                }) {
                    Image(systemName: "arrow.left")
                    Text("Back")
                } : nil,
                trailing: HStack {
                    if settings.selectedImage != nil {
                        Button(action: { showingSettings.toggle() }) {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            )
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $settings.selectedImage)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings)
            }
            .alert(isPresented: Binding<Bool>(
                get: { saveComplete || saveError != nil },
                set: { if !$0 { saveComplete = false; saveError = nil } }
            )) {
                if saveError != nil {
                    return Alert(
                        title: Text("Error"),
                        message: Text("Failed to save image: \(saveError?.localizedDescription ?? "Unknown error")"),
                        dismissButton: .default(Text("OK"))
                    )
                } else {
                    return Alert(
                        title: Text("Success"),
                        message: Text("Image saved to your photo library"),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func processImage() {
        guard let image = settings.selectedImage else { return }
        
        isProcessing = true
        
        // Process on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let processed = ImageProcessor.processImage(image: image, settings: settings)
            
            DispatchQueue.main.async {
                self.processedImage = processed
                self.isProcessing = false
            }
        }
    }
    
    private func saveImage() {
        guard let image = processedImage else { return }
        
        isProcessing = true
        
        ImageProcessor.saveToPhotoLibrary(image: image) { success, error in
            DispatchQueue.main.async {
                self.isProcessing = false
                if success {
                    self.saveComplete = true
                } else if let error = error {
                    self.saveError = error
                }
            }
        }
    }
}