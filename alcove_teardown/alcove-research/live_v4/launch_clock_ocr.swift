import AppKit
import Foundation
import Vision

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    do {
        try VNImageRequestHandler(url: url, options: [:]).perform([request])
        print("FILE \(path)")
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first else { continue }
            print(String(format: "%.3f %@",
                         observation.boundingBox.origin.y,
                         text.string))
        }
    } catch {
        fputs("OCR error for \(path): \(error)\n", stderr)
    }
}
