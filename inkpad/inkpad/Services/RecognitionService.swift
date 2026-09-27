import Foundation

protocol RecognitionService {
    func recognize(strokeData: Data) -> String
}

final class MockRecognitionService: RecognitionService {
    func recognize(strokeData: Data) -> String {
        "2x + y - z = 8"
    }
}
