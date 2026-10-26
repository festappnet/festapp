// Real PDF rasterization and QR decoding using macOS CoreGraphics/Vision.
import Foundation
import CoreGraphics
import Vision
let args = CommandLine.arguments
let symbols = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String]
var matches = Set<String>()
var pages = 0
for name in args.dropFirst(2) {
    guard let pdf = CGPDFDocument(URL(fileURLWithPath: name) as CFURL) else { fatalError("Invalid PDF") }
    for index in 1...pdf.numberOfPages {
        let page = pdf.page(at: index)!
        let rect = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 3
        let ctx = CGContext(data: nil, width: Int(rect.width * scale), height: Int(rect.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale))
        ctx.scaleBy(x: scale, y: scale); ctx.drawPDFPage(page)
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: ctx.makeImage()!, options: [:]).perform([request])
        for qr in request.results ?? [] {
            if let value = qr.payloadStringValue {
                for symbol in symbols where value.contains(symbol) { matches.insert(symbol) }
            }
        }
        pages += 1
    }
}
guard matches.count == symbols.count else { fatalError("QR mismatch: decoded \(matches.count) expected \(symbols.count)") }
print("PASS: \(pages) PDF pages rasterized; \(matches.count) real ticket QR codes match canonical issued symbols")
