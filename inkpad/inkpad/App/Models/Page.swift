import SwiftData
import Foundation

@Model
final class Page {
    var sortIndex: Int
    var drawingData: Data?
    var backgroundStyle: String
    var notebook: Notebook?

    init(sortIndex: Int, backgroundStyle: PageBackgroundStyle = .blank) {
        self.sortIndex = sortIndex
        self.drawingData = nil
        self.backgroundStyle = backgroundStyle.rawValue
    }

    var background: PageBackgroundStyle {
        get { PageBackgroundStyle(rawValue: backgroundStyle) ?? .blank }
        set { backgroundStyle = newValue.rawValue }
    }
}
