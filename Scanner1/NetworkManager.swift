import Foundation
import UIKit
import AVFoundation

class NetworkManager {
    static let shared = NetworkManager()
    private init() {}
    
    private let ocrServerUrl = "http://95.70.137.98:8000" // OCR sunucu adresi
    private let ttsServerUrl = "http://35.198.44.239:7001" // TTS sunucu adesiiiii
    
    private var audioPlayer: AVAudioPlayer?
    
    func sendImageForOCR(image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        let resizedImage = resizeImage(image, targetSize: CGSize(width: 1000, height: 1000))
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.5) else {
            completion(.failure(NSError(domain: "com.yourapp", code: 0, userInfo: [NSLocalizedDescriptionKey: "Görüntü veriye dönüştürülemedi"])))
            return
        }
        
        let base64String = imageData.base64EncodedString()
        
        let url = URL(string: "\(ocrServerUrl)/ocr/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["image": base64String]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let data = data else {
                print("No data received from server")
                completion(.failure(NSError(domain: "com.yourapp", code: 3, userInfo: [NSLocalizedDescriptionKey: "Sunucudan veri alınamadı"])))
                return
            }

            if let rawResponse = String(data: data, encoding: .utf8) {
                print("Raw server response: \(rawResponse)")
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    if let taskId = json["task_id"] as? String {
                        self.pollForResults(taskId: taskId, completion: completion)
                    } else {
                        print("No task ID found in response")
                        completion(.failure(NSError(domain: "com.yourapp", code: 4, userInfo: [NSLocalizedDescriptionKey: "Yanıtta task ID bulunamadı"])))
                    }
                } else {
                    print("Invalid JSON structure")
                    completion(.failure(NSError(domain: "com.yourapp", code: 5, userInfo: [NSLocalizedDescriptionKey: "Geçersiz JSON yapısı"])))
                }
            } catch {
                print("JSON parsing error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }

        task.resume()
    }
    
    private func pollForResults(taskId: String, retryCount: Int = 0, completion: @escaping (Result<String, Error>) -> Void) {
        checkOCRStatus(taskId: taskId) { result in
            switch result {
            case .success(let ocrResult):
                completion(.success(ocrResult))
            case .failure(let error):
                if let nsError = error as NSError?, nsError.code == 8 { // Processing status
                    if retryCount < 30 { // Retry for up to 30 times (30 seconds)
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                            self.pollForResults(taskId: taskId, retryCount: retryCount + 1, completion: completion)
                        }
                    } else {
                        completion(.failure(NSError(domain: "com.yourapp", code: 10, userInfo: [NSLocalizedDescriptionKey: "İşlem zaman aşımına uğradı"])))
                    }
                } else {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func checkOCRStatus(taskId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(ocrServerUrl)/ocr/status/\(taskId)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 60 // 60 saniye timeout
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Status check error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                print("No data received from status check")
                completion(.failure(NSError(domain: "com.yourapp", code: 5, userInfo: [NSLocalizedDescriptionKey: "Durum kontrolünde veri alınamadı"])))
                return
            }
            
            do {
                let statusResponse = try JSONDecoder().decode(OCRStatusResponse.self, from: data)
                print("OCR status: \(statusResponse.status)")
                
                switch statusResponse.status {
                case "completed":
                    if let result = statusResponse.result {
                        let formattedResult = """
                        \(result)
                        
                        
                        
                        
                        
                        """
                        completion(.success(formattedResult))
                    } else {
                        completion(.failure(NSError(domain: "com.yourapp", code: 6, userInfo: [NSLocalizedDescriptionKey: "Sonuç bulunamadı"])))
                    }
                case "error":
                    let errorMessage = statusResponse.message ?? "Bilinmeyen hata"
                    completion(.failure(NSError(domain: "com.yourapp", code: 7, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                case "processing":
                    completion(.failure(NSError(domain: "com.yourapp", code: 8, userInfo: [NSLocalizedDescriptionKey: "İşlem devam ediyor"])))
                case "expired":
                    completion(.failure(NSError(domain: "com.yourapp", code: 11, userInfo: [NSLocalizedDescriptionKey: "İşlem süresi doldu"])))
                default:
                    completion(.failure(NSError(domain: "com.yourapp", code: 9, userInfo: [NSLocalizedDescriptionKey: "Beklenmeyen durum: \(statusResponse.status)"])))
                }
            } catch {
                print("JSON parsing error in status check: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }

    
    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let newSize = widthRatio > heightRatio ?  CGSize(width: size.width * heightRatio, height: size.height * heightRatio) : CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? image
    }
    

    func sendTextToTTS(text: String, language: String = "tr", maxRetries: Int = 3, progress: @escaping (Float) -> Void, completion: @escaping (Result<Data, Error>) -> Void) {
            let url = URL(string: "\(ttsServerUrl)/tts")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 600 // 2 dakika zaman aşımı süresi
            
            let body = TTSRequest(text: text, language: language)
            request.httpBody = try? JSONEncoder().encode(body)
            
            sendTTSRequest(request: request, currentRetry: 0, maxRetries: maxRetries, progress: progress, completion: completion)
        }
        
        private func sendTTSRequest(request: URLRequest, currentRetry: Int, maxRetries: Int, progress: @escaping (Float) -> Void, completion: @escaping (Result<Data, Error>) -> Void) {
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    if (error as NSError).code == NSURLErrorTimedOut && currentRetry < maxRetries {
                        DispatchQueue.main.async {
                            progress(Float(currentRetry + 1) / Float(maxRetries + 1))
                        }
                        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                            self.sendTTSRequest(request: request, currentRetry: currentRetry + 1, maxRetries: maxRetries, progress: progress, completion: completion)
                        }
                    } else {
                        completion(.failure(error))
                    }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(NSError(domain: "NetworkManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    completion(.failure(NSError(domain: "NetworkManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error"])))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NetworkManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                
                DispatchQueue.main.async {
                    progress(1.0)
                }
                
                completion(.success(data))
            }
            
            // İlerleme takibi için bir zamanlayıcı başlat
            var progressValue: Float = 0.0
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                progressValue += 0.01 // Her 0.5 saniyede %1 ilerleme
                if progressValue >= 1.0 {
                    timer.invalidate()
                } else {
                    DispatchQueue.main.async {
                        progress(progressValue)
                    }
                }
            }
            
            task.resume()
        }

    func playAudio(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()
        } catch {
            print("Ses dosyası çalınamadı: \(error.localizedDescription)")
        }
    }

    func saveAudioToFile(data: Data) -> URL? {
            let fileManager = FileManager.default
            do {
                
                let documentsDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                let downloadsDirectory = documentsDirectory.appendingPathComponent("Downloads")
                
                try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true, attributes: nil)
                
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                let dateString = dateFormatter.string(from: Date())
                let fileName = "TTS_\(dateString).wav"
                
                let fileURL = downloadsDirectory.appendingPathComponent(fileName)
                try data.write(to: fileURL)
                
                
                try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
                
                return fileURL
            } catch {
                print("Ses dosyası kaydedilemedi: \(error.localizedDescription)")
                return nil
            }
        }
}

struct OCRStatusResponse: Codable {
    let status: String
    let result: String?
    let message: String?
    let processTime: Double?
    let tutar: String?
    let topkdv: String?
    let tarih: String?
    let saat: String?
    
    enum CodingKeys: String, CodingKey {
        case status, result, message, tutar, topkdv, tarih, saat
        case processTime = "process_time"
    }
}

struct TTSRequest: Codable {
    let text: String
    let language: String
}
