import SwiftUI

struct ImagePreview: View {
    let image: UIImage
    var processedImage: UIImage?
    var isProcessing: Bool
    
    @State private var isShowingOriginal = false
    
    var body: some View {
        VStack {
            if isProcessing {
                ProgressView("Processing image...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
            } else {
                ZStack {
                    if let processedImage = processedImage, !isShowingOriginal {
                        Image(uiImage: processedImage)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                            .shadow(radius: 5)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                    }
                    
                    if processedImage != nil {
                        VStack {
                            Spacer()
                            
                            Button(action: { isShowingOriginal.toggle() }) {
                                HStack {
                                    Image(systemName: isShowingOriginal ? "eye.slash" : "eye")
                                    Text(isShowingOriginal ? "Show Framed" : "Show Original")
                                }
                                .padding(10)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                            }
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
    }
}