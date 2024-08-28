import Foundation
import Vision
import VisionKit

// MARK: - TextRecognizer

final class TextRecognizer {
    let cameraScan: VNDocumentCameraScan
    
    init(cameraScan: VNDocumentCameraScan) {
        self.cameraScan = cameraScan
    }
    
    private let queue = DispatchQueue(label: "scan-codes", qos: .default, attributes: [], autoreleaseFrequency: .workItem)
    
    func recognizeText(withCompletionHandler completionHandler: @escaping ([String]) -> Void) {
        queue.async {
            let images = (0..<self.cameraScan.pageCount).compactMap({
                self.cameraScan.imageOfPage(at: $0)
            })
            
            var textPerPage: [String] = []
            let group = DispatchGroup()
            
            for (index, image) in images.enumerated() {
                group.enter()
                NetworkManager.shared.sendImageForOCR(image: image) { result in
                    switch result {
                    case .success(let text):
                        textPerPage.append(text)
                    case .failure(let error):
                        print("Sayfa \(index + 1) için hata: \(error.localizedDescription)")
                        textPerPage.append("OCR hatası (Sayfa \(index + 1)): \(error.localizedDescription)")
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                completionHandler(textPerPage)
            }
        }
    }
}
