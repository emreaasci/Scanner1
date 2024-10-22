import SwiftUI
import VisionKit

struct ContentView: View {
    @State private var showScannerSheet = false
    @State private var texts: [ScanData] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var isPlayingAudio = false
    @State private var selectedText: ScanData?
    @State private var audioProgress: Float = 0.0
    @State private var customText: String = ""
    @State private var showTextInput = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Segment kontrolü
                Picker("Mode", selection: $showTextInput) {
                    Text("Tarama").tag(false)
                    Text("Metin Girişi").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if showTextInput {
                    // Metin girişi görünümü
                    VStack {
                        TextEditor(text: $customText)
                            .frame(minHeight: 100)
                            .border(Color.gray, width: 1)
                            .padding()
                        
                        HStack {
                            Button(action: {
                                guard !isPlayingAudio else { return }
                                readText(customText)
                            }) {
                                Label("Seslendir", systemImage: "play.circle")
                            }
                            .disabled(isPlayingAudio || customText.isEmpty)
                            .buttonStyle(BorderedButtonStyle())
                            
                            Button(action: {
                                saveAudio(customText)
                            }) {
                                Label("Kaydet", systemImage: "square.and.arrow.down")
                            }
                            .disabled(customText.isEmpty)
                            .buttonStyle(BorderedButtonStyle())
                        }
                        .padding()
                        
                        if isPlayingAudio {
                            ProgressView(value: audioProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                                .padding()
                        }
                    }
                } else {
                    // Orijinal tarama görünümü
                    if isProcessing {
                        ProgressView("OCR İşlemi Devam Ediyor")
                            .padding()
                    }
                    
                    if let error = errorMessage {
                        Text("Hata: \(error)")
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    if texts.isEmpty {
                        Text("Henüz tarama yok").font(.title)
                    } else {
                        List(texts) { text in
                            VStack(alignment: .leading) {
                                Text(text.content)
                                    .lineLimit(2)
                                    .onTapGesture {
                                        selectedText = text
                                    }
                                HStack {
                                    Button(action: {
                                        guard !isPlayingAudio else { return }
                                        readText(text.content)
                                    }) {
                                        Label("Oku", systemImage: "play.circle")
                                    }
                                    .disabled(isPlayingAudio)
                                    .buttonStyle(BorderedButtonStyle())
                                    
                                    Button(action: {
                                        saveAudio(text.content)
                                    }) {
                                        Label("Kaydet", systemImage: "square.and.arrow.down")
                                    }
                                    .buttonStyle(BorderedButtonStyle())
                                }
                                if isPlayingAudio {
                                    ProgressView(value: audioProgress)
                                        .progressViewStyle(LinearProgressViewStyle())
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("OCR ve TTS")
            .navigationBarItems(
                trailing: Group {
                    if !showTextInput {
                        Button(action: {
                            self.showScannerSheet = true
                        }) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.title)
                        }
                    }
                }
            )
            .sheet(isPresented: $showScannerSheet, content: {
                self.makeScannerView()
            })
            .sheet(item: $selectedText) { text in
                TextDetailView(text: text.content)
            }
        }
    }
    
    private func makeScannerView() -> ScannerView {
        ScannerView(completionHandler: { result in
            switch result {
            case .success(let scannedImages):
                self.processScannedImages(scannedImages)
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
            self.showScannerSheet = false
        })
    }
    
    private func processScannedImages(_ images: [UIImage]) {
        guard !images.isEmpty else {
            self.errorMessage = "Taranmış görüntü bulunamadı"
            return
        }
        
        self.isProcessing = true
        self.errorMessage = nil
        
        for (index, image) in images.enumerated() {
            NetworkManager.shared.sendImageForOCR(image: image) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text):
                        let newScanData = ScanData(content: text)
                        self.texts.append(newScanData)
                    case .failure(let error):
                        self.errorMessage = "Sayfa \(index + 1) hatası: \(error.localizedDescription)"
                    }
                    
                    if index == images.count - 1 {
                        self.isProcessing = false
                    }
                }
            }
        }
    }
    
    private func readText(_ text: String) {
        isPlayingAudio = true
        audioProgress = 0.0
        NetworkManager.shared.sendTextToTTS(text: text, progress: { progress in
            DispatchQueue.main.async {
                self.audioProgress = progress
            }
        }) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let audioData):
                    NetworkManager.shared.playAudio(data: audioData)
                case .failure(let error):
                    self.errorMessage = "TTS hatası: \(error.localizedDescription)"
                }
                self.isPlayingAudio = false
            }
        }
    }
    
    private func saveAudio(_ text: String) {
        NetworkManager.shared.sendTextToTTS(text: text, progress: { _ in }) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let audioData):
                    if let savedUrl = NetworkManager.shared.saveAudioToFile(data: audioData) {
                        self.errorMessage = "Ses dosyası kaydedildi: \(savedUrl.lastPathComponent)"
                    } else {
                        self.errorMessage = "Ses dosyası kaydedilemedi"
                    }
                case .failure(let error):
                    self.errorMessage = "TTS hatası: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct TextDetailView: View {
    let text: String
    
    var body: some View {
        ScrollView {
            Text(text)
                .padding()
        }
        .navigationBarTitle("Metin Detayı", displayMode: .inline)
    }
}
