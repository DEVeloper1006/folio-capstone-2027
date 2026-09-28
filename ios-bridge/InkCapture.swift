import PencilKit
import UIKit

/// Converts PencilKit drawings into model-ready input.
/// Must mirror shared/utils/rasterize.py (crop to ink, pad, downscale, grayscale).
final class InkCapture {
    // TODO: configurable padding / max size matching rasterize.preprocess defaults (8px, 256x1024).

    /// Rasterize a drawing to a grayscale image cropped to the ink bounds.
    func rasterize(_ drawing: PKDrawing, scale: CGFloat = 2.0) -> UIImage? {
        // TODO: drawing.image(from: drawing.bounds.insetBy(dx: -pad, dy: -pad), scale:)
        // TODO: flatten onto white background, convert to grayscale.
        // TODO: downscale (never upscale) to fit max size, preserving aspect ratio.
        return nil
    }

    /// Extract raw stroke points for stroke-based (online) models.
    func strokes(from drawing: PKDrawing) -> [[(x: CGFloat, y: CGFloat, t: TimeInterval)]] {
        // TODO: iterate drawing.strokes -> stroke.path, sample points with timeOffset.
        return []
    }
}
