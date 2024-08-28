import SwiftUI
import VisionKit
import Vision


struct ScannerView: UIViewControllerRepresentable {
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let completionHandler: (Result<[UIImage], Error>) -> Void
        
        init(completion: @escaping (Result<[UIImage], Error>) -> Void) {
            self.completionHandler = completion
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0) }
            completionHandler(.success(images))
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            completionHandler(.failure(error))
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            completionHandler(.failure(NSError(domain: "ScannerView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Scanning cancelled"])))
        }
    }
    
    let completionHandler: (Result<[UIImage], Error>) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completionHandler)
    }
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let viewController = VNDocumentCameraViewController()
        viewController.delegate = context.coordinator
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
}
