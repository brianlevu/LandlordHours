// ocr_lines.swift - Vision text lines for frame_check.py `breaks`.
//   swift scripts/qa/ocr_lines.swift FRAME.png [FRAME2.png ...]   -> JSON on stdout
// {"<path>": [{"text": "...", "x": px, "y": px, "w": px, "h": px}]}, origin top-left, pixels.
import Foundation
import Vision
import CoreGraphics
import ImageIO

var out: [String: [[String: Any]]] = [:]
for path in CommandLine.arguments.dropFirst() {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { out[path] = []; continue }
    let w = Double(img.width), h = Double(img.height)
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
    var lines: [[String: Any]] = []
    for obs in req.results ?? [] {
        guard let top = obs.topCandidates(1).first else { continue }
        let b = obs.boundingBox
        lines.append(["text": top.string, "x": b.minX * w, "y": (1 - b.maxY) * h, "w": b.width * w, "h": b.height * h])
    }
    out[path] = lines
}
let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
