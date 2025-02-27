import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else { return }
            
            // First try to load the original file data to preserve EXIF information
            if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                    if let error = error {
                        print("Error loading file representation: \(error.localizedDescription)")
                        self.fallbackToUIImage(result.itemProvider)
                        return
                    }
                    
                    guard let fileURL = url else {
                        print("No URL returned from loadFileRepresentation")
                        self.fallbackToUIImage(result.itemProvider)
                        return
                    }
                    
                    // Create a temporary URL to copy the file to (since the original URL is temporary)
                    let documentsDirectory = FileManager.default.temporaryDirectory
                    let tempURL = documentsDirectory.appendingPathComponent(fileURL.lastPathComponent)
                    
                    do {
                        // Remove any existing file
                        if FileManager.default.fileExists(atPath: tempURL.path) {
                            try FileManager.default.removeItem(at: tempURL)
                        }
                        
                        // Copy the file to our temporary location
                        try FileManager.default.copyItem(at: fileURL, to: tempURL)
                        
                        // Create UIImage from the file data to preserve EXIF
                        if let imageData = try? Data(contentsOf: tempURL),
                           let image = UIImage(data: imageData) {
                            DispatchQueue.main.async {
                                self.parent.image = image
                            }
                            return
                        }
                    } catch {
                        print("Error handling image file: \(error.localizedDescription)")
                    }
                    
                    // If we reach here, fall back to loading as UIImage
                    self.fallbackToUIImage(result.itemProvider)
                }
            } else {
                // Fallback to the original implementation
                fallbackToUIImage(result.itemProvider)
            }
        }
        
        private func fallbackToUIImage(_ provider: NSItemProvider) {
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}