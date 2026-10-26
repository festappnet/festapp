import AppKit
import PDFKit
let root=URL(fileURLWithPath:CommandLine.arguments[1])
for url in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) where url.pathExtension == "pdf" {
 guard let doc=PDFDocument(url:url),let page=doc.page(at:0) else {fatalError("Invalid PDF")}
 let box=page.bounds(for:.mediaBox), scale=1200/max(box.width,box.height)
 let w=Int((box.width*scale).rounded()),h=Int((box.height*scale).rounded())
 let image=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 let context=NSGraphicsContext(bitmapImageRep:image)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
 NSColor.white.setFill();NSRect(x:0,y:0,width:w,height:h).fill()
 context.cgContext.scaleBy(x:scale,y:scale);page.draw(with:.mediaBox,to:context.cgContext)
 NSGraphicsContext.restoreGraphicsState()
 try image.representation(using:.png,properties:[:])!.write(to:url.deletingPathExtension().appendingPathExtension("png"))
 print("\(url.deletingPathExtension().lastPathComponent) \(w)x\(h)")
}
