import Foundation

@main
struct PolynomialOracleCLI {
    struct Request: Decodable { let latex: String; let variable: String? }
    static func main() {
        while let line = readLine() {
            do {
                let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
                let service = PolynomialIntegrationService(), prepared = try service.prepare(request.latex)
                let answer = try service.integrate(prepared, variable: request.variable ?? prepared.suggestedVariable)
                print(String(data: try JSONEncoder().encode(answer), encoding: .utf8)!)
            } catch {
                let data = try! JSONEncoder().encode(["error": error.localizedDescription])
                print(String(data: data, encoding: .utf8)!)
            }
        }
    }
}
