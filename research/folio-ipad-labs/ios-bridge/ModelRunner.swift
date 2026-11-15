import CoreML
import UIKit

/// Loads an exported CoreML model and runs handwriting → LaTeX inference.
final class ModelRunner {
    // TODO: hold MLModel instance; load compiled .mlmodelc from the app bundle.

    init(modelName: String) throws {
        // TODO: MLModel(contentsOf: Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")!)
        // TODO: pick MLModelConfiguration.computeUnits (.all vs .cpuAndNeuralEngine).
    }

    /// Run recognition on a preprocessed image from InkCapture.
    func recognize(_ image: UIImage) async throws -> String {
        // TODO: convert UIImage -> CVPixelBuffer in the model's expected size/format.
        // TODO: run encoder, then autoregressive decoder loop (if split export).
        // TODO: detokenize output ids -> LaTeX string.
        return ""
    }
}
