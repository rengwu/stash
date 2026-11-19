// Renders an SVG to a square PNG of an exact pixel size with WebKit, keeping transparency.
// WebKit draws every SVG filter the icon uses; NSImage's SVG renderer drops the shadows.
// Usage: swiftc -o render-icon render-icon.swift && ./render-icon IN.svg OUT.png PIXELS
import AppKit
import WebKit

let args = CommandLine.arguments
let pixels = args.count == 4 ? Int(args[3]) ?? 0 : 0
guard pixels > 0, let svg = FileManager.default.contents(atPath: args[1]) else {
    FileHandle.standardError.write("usage: render-icon IN.svg OUT.png PIXELS\n".data(using: .utf8)!)
    exit(64)
}
let out = URL(fileURLWithPath: args[2])

let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                      styleMask: [.borderless], backing: .buffered, defer: false)
// Lay out in points so the snapshot comes out at `pixels` on this screen's scale.
let scale = window.backingScaleFactor
let points = CGFloat(pixels) / scale
window.setContentSize(NSSize(width: points, height: points))

let view = WKWebView(frame: NSRect(x: 0, y: 0, width: points, height: points))
view.setValue(false, forKey: "drawsBackground")
window.contentView = view

final class Loader: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give the image a moment to decode before capturing it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(x: 0, y: 0, width: points, height: points)
            webView.takeSnapshot(with: config) { image, error in
                guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    FileHandle.standardError.write("snapshot failed: \(String(describing: error))\n".data(using: .utf8)!)
                    exit(1)
                }
                // Redraw into an exact-size bitmap in case the screen scale didn't divide evenly.
                let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.interpolationQuality = .high
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
                let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
                do {
                    try rep.representation(using: .png, properties: [:])!.write(to: out)
                    exit(0)
                } catch {
                    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
                    exit(1)
                }
            }
        }
    }
}

let loader = Loader()
view.navigationDelegate = loader
let src = "data:image/svg+xml;base64," + svg.base64EncodedString()
view.loadHTMLString("""
<!doctype html><html><body style="margin:0;background:transparent">
<img src="\(src)" style="display:block;width:\(points)px;height:\(points)px">
</body></html>
""", baseURL: nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    FileHandle.standardError.write("timed out\n".data(using: .utf8)!)
    exit(2)
}
app.run()
