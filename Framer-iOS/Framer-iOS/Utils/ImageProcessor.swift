import UIKit
import Photos

class ImageProcessor {
    
    // Generate caption from date
    static func generateCaptionFromDate(_ date: Date?) -> String {
        guard let date = date else { return " - --- -" }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM"
        let month = dateFormatter.string(from: date).uppercased()
        
        dateFormatter.dateFormat = "yy"
        let year = dateFormatter.string(from: date)
        
        return " - \(month) '\(year) -"
    }
    
    // Extract EXIF date from image
    static func getExifDate(from image: UIImage) -> Date? {
        guard let imageData = image.jpegData(compressionQuality: 1.0) else { return nil }
        
        let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil)
        guard let source = imageSource else { return nil }
        
        guard let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        guard let exif = metadata["{Exif}"] as? [String: Any] else { return nil }
        
        if let dateString = exif["DateTimeOriginal"] as? String {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            return dateFormatter.date(from: dateString)
        }
        
        return nil
    }
    
    // Create solid border
    static func createSolidBorder(image: UIImage, borderThickness: CGFloat, borderColor: UIColor, padding: CGFloat) -> UIImage {
        let imageSize = image.size
        
        // Add border
        let borderedSize = CGSize(
            width: imageSize.width + 2 * borderThickness,
            height: imageSize.height + 2 * borderThickness
        )
        
        UIGraphicsBeginImageContextWithOptions(borderedSize, false, 0)
        
        // Draw border (fill entire context with border color)
        borderColor.setFill()
        UIRectFill(CGRect(origin: .zero, size: borderedSize))
        
        // Draw the image in the center
        let imageRect = CGRect(
            x: borderThickness,
            y: borderThickness,
            width: imageSize.width,
            height: imageSize.height
        )
        image.draw(in: imageRect)
        
        let borderedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Add padding if specified
        if padding > 0 {
            let finalSize = CGSize(
                width: borderedSize.width + 2 * padding,
                height: borderedSize.height + 2 * padding
            )
            
            UIGraphicsBeginImageContextWithOptions(finalSize, false, 0)
            
            // Fill with white for padding
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: finalSize))
            
            // Draw bordered image in center
            let paddedRect = CGRect(
                x: padding,
                y: padding,
                width: borderedSize.width,
                height: borderedSize.height
            )
            borderedImage?.draw(in: paddedRect)
            
            let finalImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return finalImage ?? UIImage()
        }
        
        return borderedImage ?? UIImage()
    }
    
    // Create Instagram frame
    static func createInstagramFrame(image: UIImage, maxSize: CGFloat, borderThickness: CGFloat, borderColor: UIColor, padding: CGFloat) -> (UIImage, CGRect) {
        // Fixed dimensions for Instagram (4:5 ratio)
        let frameWidth: CGFloat = 1080
        let frameHeight: CGFloat = 1350
        
        // Calculate scaling factor
        let originalSize = image.size
        let scaleW = maxSize / originalSize.width
        let scaleH = maxSize / originalSize.height
        let scale = min(scaleW, scaleH)
        
        // Resize image while maintaining aspect ratio
        let newWidth = originalSize.width * scale
        let newHeight = originalSize.height * scale
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: newWidth, height: newHeight), false, 0)
        image.draw(in: CGRect(origin: .zero, size: CGSize(width: newWidth, height: newHeight)))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        var finalResizedImage = resizedImage
        var finalWidth = newWidth
        var finalHeight = newHeight
        
        // Add padding if specified
        if padding > 0 {
            let paddedWidth = newWidth + 2 * padding
            let paddedHeight = newHeight + 2 * padding
            
            UIGraphicsBeginImageContextWithOptions(CGSize(width: paddedWidth, height: paddedHeight), false, 0)
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: CGSize(width: paddedWidth, height: paddedHeight)))
            
            resizedImage?.draw(in: CGRect(x: padding, y: padding, width: newWidth, height: newHeight))
            finalResizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            finalWidth = paddedWidth
            finalHeight = paddedHeight
        }
        
        // Create bordered image
        let borderedWidth = finalWidth + 2 * borderThickness
        let borderedHeight = finalHeight + 2 * borderThickness
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: borderedWidth, height: borderedHeight), false, 0)
        
        // Fill with border color
        borderColor.setFill()
        UIRectFill(CGRect(origin: .zero, size: CGSize(width: borderedWidth, height: borderedHeight)))
        
        // Draw resized image
        finalResizedImage?.draw(in: CGRect(
            x: borderThickness,
            y: borderThickness,
            width: finalWidth,
            height: finalHeight
        ))
        
        let borderedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Create final image with white background
        UIGraphicsBeginImageContextWithOptions(CGSize(width: frameWidth, height: frameHeight), false, 0)
        
        // Fill with white
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: CGSize(width: frameWidth, height: frameHeight)))
        
        // Center the bordered image
        let x = (frameWidth - borderedWidth) / 2
        let y = (frameHeight - borderedHeight) / 2
        
        borderedImage?.draw(in: CGRect(
            x: x,
            y: y,
            width: borderedWidth,
            height: borderedHeight
        ))
        
        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Return the image and the position where the actual image starts for caption positioning
        let imageRect = CGRect(
            x: x + borderThickness + padding,
            y: y + borderThickness + padding,
            width: newWidth,
            height: newHeight
        )
        
        return (finalImage ?? UIImage(), imageRect)
    }
    
    // Add caption to image
    static func addCaption(image: UIImage, captionText: String, fontSize: CGFloat, fontColor: UIColor,
                           imageSize: CGSize, borderThickness: CGFloat, padding: CGFloat,
                           imageRect: CGRect? = nil, fontName: String) -> UIImage {
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, 0)
        image.draw(at: .zero)
        
        // Calculate text attributes
        let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fontColor
        ]
        
        // Calculate text size
        let textSize = captionText.size(withAttributes: textAttributes)
        
        // Calculate position
        var x: CGFloat
        var y: CGFloat
        
        if let rect = imageRect {
            // Instagram style
            x = rect.origin.x + (rect.width - textSize.width) / 2
            y = rect.origin.y + rect.height + borderThickness + textSize.height
        } else {
            // Other styles
            let totalBorder = borderThickness + padding
            x = totalBorder + (imageSize.width - textSize.width) / 2
            y = totalBorder + imageSize.height + (borderThickness + padding - textSize.height) / 2 + textSize.height
        }
        
        // Draw text
        captionText.draw(at: CGPoint(x: x, y: y - textSize.height), withAttributes: textAttributes)
        
        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return finalImage ?? image
    }
    
    // Process image with all settings
    static func processImage(image: UIImage, settings: FramerSettings) -> UIImage {
        // Determine caption text
        var captionText = settings.caption
        if settings.useExifDate && captionText.isEmpty {
            let date = getExifDate(from: image)
            captionText = generateCaptionFromDate(date)
        }
        
        let borderColor = settings.uiBorderColor()
        let fontColor = settings.uiFontColor()
        
        var processedImage: UIImage
        var imageRect: CGRect?
        
        // Process based on border style
        switch settings.borderStyle {
        case .instagram:
            let result = createInstagramFrame(
                image: image,
                maxSize: settings.instagramMaxSize,
                borderThickness: settings.borderThickness,
                borderColor: borderColor,
                padding: settings.padding
            )
            processedImage = result.0
            imageRect = result.1
            
        case .solid:
            processedImage = createSolidBorder(
                image: image,
                borderThickness: settings.borderThickness,
                borderColor: borderColor,
                padding: settings.padding
            )
        }
        
        // Add caption if not empty
        if !captionText.isEmpty {
            let imageSize = CGSize(width: image.size.width, height: image.size.height)
            processedImage = addCaption(
                image: processedImage,
                captionText: captionText,
                fontSize: settings.fontSize,
                fontColor: fontColor,
                imageSize: imageSize,
                borderThickness: settings.borderThickness,
                padding: settings.padding,
                imageRect: imageRect,
                fontName: settings.fontName
            )
        }
        
        return processedImage
    }
    
    // Save image to photo library
    static func saveToPhotoLibrary(image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }, completionHandler: completion)
    }
}