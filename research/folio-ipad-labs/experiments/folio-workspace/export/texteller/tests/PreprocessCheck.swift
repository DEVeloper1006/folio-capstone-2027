import Foundation
import ImageIO

@main
struct PreprocessCheck {
    static func main() {
        do { try run() }
        catch { fputs(error.localizedDescription + "\n", stderr); exit(2) }
    }

    static func run() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: preprocess-check input.png output.f32") }
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let result = try ImagePreprocessor.prepare(image)
        try result.values.withUnsafeBytes { try Data($0).write(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
        print(String(data: try JSONEncoder().encode(result.info), encoding: .utf8)!)
    }
}
