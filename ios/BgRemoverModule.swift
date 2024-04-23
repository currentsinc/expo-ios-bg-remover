import ExpoModulesCore
import Vision
import CoreGraphics
import Photos
import UIKit

public class BgRemoverModule: Module {
  typealias LoadImageCallback = (Result<UIImage, Error>) -> Void
  typealias SaveImageResult = (url: URL, data: Data)

  // Each module class must implement the definition function. The definition consists of components
  // that describes the module's functionality and behavior.
  // See https://docs.expo.dev/modules/module-api for more details about available components.
  public func definition() -> ModuleDefinition {
    // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
    // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
    // The module will be accessible from `requireNativeModule('BgRemover')` in JavaScript.
    Name("BgRemover")

    // Defines event names that the module can send to JavaScript.
    Events("onChange")

    // Defines a JavaScript function that always returns a Promise and whose native code
    // is by default dispatched on the different thread than the JavaScript runtime runs on.
    AsyncFunction("getSubjectAsync", getSubject)
  }

  internal func getSubject(url: URL, pointX: Double, pointY: Double, cropToExtent: Bool, promise: Promise) throws {
    // if ios version is not 17.0 or higher, return nothing
    if #available(iOS 17.0, *) {
      loadImage(atUrl: url) { result in
        switch result {
        case .failure(let error):
          promise.reject(error)
        case .success(let image):
          DispatchQueue.main.async {
            do {
              guard let cgImage = image.cgImage else {
                throw ImageNotFoundException()
              }
              let cgPoint = CGPoint(x: pointX, y: pointY)
              let subject = try self.getSubjectFromImage(image: cgImage, atPoint: cgPoint, cropToExtent: cropToExtent)
              // if subject is nil, reject with an error
              let saveResult = try self.saveImage(subject!)

              promise.resolve([
                "uri": saveResult.url.absoluteString
              ])
            } catch {
              promise.reject(error)
            }
          }
        }
      }
    } else {
      throw IOSVersionNotSupported()
    }
  }

  @available(iOS 17.0, *) 
  internal func getSubjectFromImage(image: CGImage, atPoint point: CGPoint, cropToExtent: Bool) throws -> UIImage? {
    // create CIImage from CGImage
    let ciImage = CIImage(cgImage: image)

    // Create a request.
    let request = VNGenerateForegroundInstanceMaskRequest()

    // Create a request handler.
    let handler = VNImageRequestHandler(ciImage: ciImage)

    // Perform the request.
    do {
        try handler.perform([request])
    } catch {
        throw BackgroundRemoveFailedException("Failed to perform Vision request.")
    }

    // Acquire the instance mask observation.
    guard let result = request.results?.first else {
        throw BackgroundRemoveFailedException("No subject observations found.")
        print("No subject observations found.")
        return nil
    }
    
    // get image for first instance
    let instances = instances(atPoint: point, inObservation: result)

    // Create a matted image with the subject isolated from the background.
    do {
        // let mask = try result.generateScaledMaskForImage(forInstances: instances, from: handler)
        let mask = try result.generateMaskedImage(ofInstances: instances, from: handler, croppedToInstancesExtent: cropToExtent)
        let newCiImage = CIImage(cvPixelBuffer: mask)
        let newUiImage = UIImage(ciImage: newCiImage)
        
        return newUiImage
    } catch {
        throw BackgroundRemoveFailedException("Failed to generate subject mask.")
        print("Failed to generate subject mask.")
        return nil
    }
  }

  /// Returns the indices of the instances at the given point.
  ///
  /// - parameter atPoint: A point with a top-left origin, normalized within the range [0, 1].
  /// - parameter inObservation: The observation instance to extract subject indices from.
  @available(iOS 17.0, *)
  internal func instances(
      atPoint maybePoint: CGPoint?,
      inObservation observation: VNInstanceMaskObservation
  ) -> IndexSet {
      guard let point = maybePoint else {
          return observation.allInstances
      }

      // Transform the normalized UI point to an instance map pixel coordinate.
      let instanceMap = observation.instanceMask
      let coords = VNImagePointForNormalizedPoint(
          point,
          CVPixelBufferGetWidth(instanceMap) - 1,
          CVPixelBufferGetHeight(instanceMap) - 1)

      // Look up the instance label at the computed pixel coordinate.
      CVPixelBufferLockBaseAddress(instanceMap, .readOnly)
      guard let pixels = CVPixelBufferGetBaseAddress(instanceMap) else {
          fatalError("Failed to access instance map data.")
      }
      let bytesPerRow = CVPixelBufferGetBytesPerRow(instanceMap)
      let instanceLabel = pixels.load(
          fromByteOffset: Int(coords.y) * bytesPerRow + Int(coords.x),
          as: UInt8.self)
      CVPixelBufferUnlockBaseAddress(instanceMap, .readOnly)

      // If the point lies on the background, select all instances.
      // Otherwise, restrict this to just the selected instance.
      return instanceLabel == 0 ? observation.allInstances : [Int(instanceLabel)]
  }

  /**
  Loads the image from given URL.
  */
  internal func loadImage(atUrl url: URL, callback: @escaping LoadImageCallback) {
    if url.scheme == "data" {
      guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
        return callback(.failure(CorruptedImageDataException()))
      }
      return callback(.success(image))
    }
    if url.scheme == "assets-library" {
      // TODO: ALAsset URLs are deprecated as of iOS 11, we should migrate to `ph://` soon.
      return loadImageFromPhotoLibrary(url: url, callback: callback)
    }

    guard let imageLoader = self.appContext?.imageLoader else {
      return callback(.failure(ImageLoaderNotFoundException()))
    }
    guard FileSystemUtilities.permissions(appContext, for: url).contains(.read) else {
      return callback(.failure(FileSystemReadPermissionException(url.absoluteString)))
    }

    imageLoader.loadImage(for: url) { error, image in
      guard let image = image, error == nil else {
        return callback(.failure(ImageLoadingFailedException(error.debugDescription)))
      }
      callback(.success(image))
    }
  }

  /**
  Loads the image from user's photo library.
  */
  internal func loadImageFromPhotoLibrary(url: URL, callback: @escaping LoadImageCallback) {
    guard let asset = PHAsset.fetchAssets(withALAssetURLs: [url], options: nil).firstObject else {
      return callback(.failure(ImageNotFoundException()))
    }
    let size = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
    let options = PHImageRequestOptions()

    options.resizeMode = .exact
    options.isNetworkAccessAllowed = true
    options.isSynchronous = true
    options.deliveryMode = .highQualityFormat

    PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
      guard let image = image else {
        return callback(.failure(ImageNotFoundException()))
      }
      return callback(.success(image))
    }
  }

  /**
   Saves the image as a file.
   */
  internal func saveImage(_ image: UIImage) throws -> SaveImageResult {
    guard let cachesDirectory = self.appContext?.config.cacheDirectory else {
      throw FileSystemNotFoundException()
    }

    let directory = URL(fileURLWithPath: cachesDirectory.path).appendingPathComponent("ImageManipulator")
    let filename = UUID().uuidString.appending(".png")
    let fileUrl = directory.appendingPathComponent(filename)

    FileSystemUtilities.ensureDirExists(at: directory)

    guard let data = imageData(from: image) else {
      throw CorruptedImageDataException()
    }
    do {
      try data.write(to: fileUrl, options: .atomic)
    } catch let error {
      throw ImageWriteFailedException(error.localizedDescription)
    }
    return (url: fileUrl, data: data)
  }
}

/**
 Returns pixel data representation of the image.
 */
func imageData(from image: UIImage) -> Data? {
  return image.pngData()
}