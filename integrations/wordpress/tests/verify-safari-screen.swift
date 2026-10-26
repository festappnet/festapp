// Decode the ticket QR from a real native Mobile Safari PDF preview screenshot.
import Foundation
import Vision
let args = CommandLine.arguments
let symbols = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:args[1]))) as! [String]
let request=VNDetectBarcodesRequest();request.symbologies=[.qr]
try VNImageRequestHandler(url:URL(fileURLWithPath:args[2]),options:[:]).perform([request])
let decoded=(request.results ?? []).compactMap(\.payloadStringValue)
guard symbols.contains(where:{s in decoded.contains(where:{$0.contains(s)})}) else {fatalError("No canonical issued ticket QR decoded from native Safari PDF preview")}
print("PASS: native Safari PDF preview QR matches the canonical issued ticket")
