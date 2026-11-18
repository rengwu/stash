import SwiftUI
import ImageIO

actor ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSString, CGImage>()
    init() {
        cache.countLimit = 400
        cache.totalCostLimit = 300 * 1024 * 1024
    }
    func image(_ url: URL, size: Int) -> CGImage? {
        let key = "\(size):\(url.path)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: size]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}

struct Thumbnail: View {
    let url: URL?
    var mode: ContentMode = .fill
    @ViewState private var image: CGImage?
    var body: some View {
        GeometryReader { geo in
            let size = max(1, Int(ceil(geo.size.width * 2)))
            ZStack {
                Color.clear
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: mode)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height).clipped()
            .task(id: "\(url?.path ?? ""):\(size)") {
                guard let url else { image = nil; return }
                let result = await ImageLoader.shared.image(url, size: size)
                if !Task.isCancelled { image = result }
            }
        }
    }
}
