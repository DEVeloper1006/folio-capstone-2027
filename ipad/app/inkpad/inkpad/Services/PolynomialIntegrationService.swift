import Foundation

nonisolated enum PolynomialError: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { text } else { nil } }
}

nonisolated struct ExactRational: Codable, Equatable, Sendable {
    let numerator: Int64
    let denominator: Int64
    static let zero = try! ExactRational(0)
    static let one = try! ExactRational(1)

    init(_ numerator: Int64, _ denominator: Int64 = 1) throws {
        guard denominator != 0 else { throw PolynomialError.invalid("Division by zero is undefined.") }
        guard numerator != .min, denominator != .min else { throw Self.overflow }
        let sign: Int64 = denominator < 0 ? -1 : 1
        let common = Self.gcd(abs(numerator), abs(denominator))
        self.numerator = numerator / common * sign
        self.denominator = abs(denominator) / common
    }
    private static var overflow: PolynomialError { .invalid("Exact numbers are too large. Use smaller coefficients.") }
    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var a = a, b = b
        while b != 0 { let next = a % b; a = b; b = next }
        return max(a, 1)
    }
    private static func product(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (value, overflow) = a.multipliedReportingOverflow(by: b)
        guard !overflow else { throw Self.overflow }; return value
    }
    func adding(_ other: Self) throws -> Self {
        let g = Self.gcd(denominator, other.denominator)
        let left = try Self.product(numerator, other.denominator / g)
        let right = try Self.product(other.numerator, denominator / g)
        let (sum, overflow) = left.addingReportingOverflow(right)
        guard !overflow else { throw Self.overflow }
        return try Self(sum, Self.product(denominator / g, other.denominator))
    }
    func negated() throws -> Self { try Self(-numerator, denominator) }
    func multiplying(_ other: Self) throws -> Self {
        let a = Self.gcd(abs(numerator), other.denominator), b = Self.gcd(abs(other.numerator), denominator)
        return try Self(Self.product(numerator / a, other.numerator / b), Self.product(denominator / b, other.denominator / a))
    }
    func dividing(_ other: Self) throws -> Self {
        guard other.numerator != 0 else { throw PolynomialError.invalid("Division by zero is undefined.") }
        return try multiplying(Self(other.denominator, other.numerator))
    }
    static func decimal(_ text: String) throws -> Self {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2 else { throw PolynomialError.invalid("Invalid number.") }
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard fraction.count <= 9 else { throw PolynomialError.invalid("Use at most nine decimal places.") }
        let whole = pieces[0].isEmpty ? "0" : String(pieces[0])
        guard let n = Int64(whole + fraction), n != .min else { throw overflow }
        var d: Int64 = 1
        for _ in fraction { d *= 10 }
        return try Self(n, d)
    }
}

nonisolated struct PolynomialValue: Codable, Equatable, Sendable {
    let coefficients: [Int: ExactRational]
    init(_ coefficients: [Int: ExactRational]) { self.coefficients = coefficients.filter { $0.value.numerator != 0 } }
    static let zero = Self([:])
    static let variable = Self([1: .one])
    var degree: Int { coefficients.keys.max() ?? 0 }
    var isConstant: Bool { degree == 0 }
    var constant: ExactRational { coefficients[0] ?? .zero }
    func adding(_ other: Self) throws -> Self {
        var values = coefficients
        for (degree, value) in other.coefficients { values[degree] = try (values[degree] ?? .zero).adding(value) }
        return Self(values)
    }
    func negated() throws -> Self { Self(try coefficients.mapValues { try $0.negated() }) }
    func multiplying(_ other: Self) throws -> Self {
        guard degree + other.degree <= 20 else { throw PolynomialError.invalid("The supported polynomial degree is at most 20.") }
        var values: [Int: ExactRational] = [:]
        for (a, x) in coefficients { for (b, y) in other.coefficients {
            values[a+b] = try (values[a+b] ?? .zero).adding(x.multiplying(y))
        } }
        return Self(values)
    }
    func divided(by constant: ExactRational) throws -> Self {
        guard constant.numerator != 0 else { throw PolynomialError.invalid("Division by zero is undefined.") }
        return Self(try coefficients.mapValues { try $0.dividing(constant) })
    }
    func power(_ exponent: Int) throws -> Self {
        guard exponent >= 0, exponent <= 20, degree * exponent <= 20 else {
            throw PolynomialError.invalid("Use nonnegative integer powers and total degree at most 20.")
        }
        if coefficients.isEmpty && exponent == 0 { throw PolynomialError.invalid("Zero to the zeroth power is unsupported.") }
        var result = Self([0: .one])
        for _ in 0..<exponent { result = try result.multiplying(self) }
        return result
    }
    func antiderivative() throws -> Self {
        var values: [Int: ExactRational] = [:]
        for (degree, value) in coefficients { values[degree+1] = try value.dividing(ExactRational(Int64(degree+1))) }
        return Self(values)
    }
    func derivative() throws -> Self {
        var values: [Int: ExactRational] = [:]
        for (degree, value) in coefficients where degree > 0 { values[degree-1] = try value.multiplying(ExactRational(Int64(degree))) }
        return Self(values)
    }
    func latex(variable: String) -> String {
        var output = ""
        for degree in coefficients.keys.sorted(by: >) {
            let value = coefficients[degree]!, magnitude = abs(value.numerator)
            let symbol = degree == 0 ? "" : degree == 1 ? variable : variable + "^{\(degree)}"
            let top = (magnitude == 1 && degree > 0 ? "" : String(magnitude)) + symbol
            let term = value.denominator == 1 ? top : "\\frac{\(top)}{\(value.denominator)}"
            if output.isEmpty { output = (value.numerator < 0 ? "-" : "") + term }
            else { output += (value.numerator < 0 ? " - " : " + ") + term }
        }
        return output.isEmpty ? "0" : output
    }
}

private nonisolated enum PolynomialToken: Equatable, Sendable {
    case number(String), variable(String), open(Character), close(Character)
    case plus, minus, times, divide, power, fraction, integral, differential
}

private nonisolated enum PolynomialLexer {
    static func tokens(_ input: String) throws -> [PolynomialToken] {
        guard !input.isEmpty, input.count <= 5000 else { throw PolynomialError.invalid("Use an expression of 1–5,000 characters.") }
        let characters = Array(input); var index = 0, result: [PolynomialToken] = []
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace { index += 1; continue }
            if character.isASCII && character.isNumber || character == "." {
                let start = index; var dots = 0, digits = 0
                while index < characters.count && (characters[index].isASCII && characters[index].isNumber || characters[index] == ".") {
                    if characters[index] == "." { dots += 1 } else { digits += 1 }; index += 1
                }
                guard dots <= 1, digits > 0 else { throw PolynomialError.invalid("Invalid decimal number.") }
                result.append(.number(String(characters[start..<index])))
            } else if character.isASCII && character.isLetter {
                result.append(.variable(String(character))); index += 1
            } else if character == "\\" {
                index += 1; let start = index
                while index < characters.count && characters[index].isASCII && characters[index].isLetter { index += 1 }
                if index == start {
                    guard index < characters.count, [",", ";", ":", "!", " "].contains(characters[index]) else {
                        throw PolynomialError.invalid("Unsupported LaTeX command.")
                    }
                    index += 1; continue
                }
                let command = String(characters[start..<index])
                switch command {
                case "int": result.append(.integral)
                case "frac", "dfrac", "tfrac": result.append(.fraction)
                case "cdot", "times": result.append(.times)
                case "left", "right":
                    var next = index
                    while next < characters.count && characters[next].isWhitespace { next += 1 }
                    let allowed: [Character] = command == "left" ? ["(", "{"] : [")", "}"]
                    guard next < characters.count, allowed.contains(characters[next]) else { throw PolynomialError.invalid("A delimiter modifier must accompany parentheses or braces.") }
                case "quad", "qquad", "space": break
                case "mathrm":
                    while index < characters.count && characters[index].isWhitespace { index += 1 }
                    guard index < characters.count, characters[index] == "{" else { throw PolynomialError.invalid("Only \\mathrm{d} is supported here.") }
                    index += 1
                    while index < characters.count && characters[index].isWhitespace { index += 1 }
                    guard index < characters.count, characters[index] == "d" else { throw PolynomialError.invalid("Only \\mathrm{d} is supported here.") }
                    index += 1
                    while index < characters.count && characters[index].isWhitespace { index += 1 }
                    guard index < characters.count, characters[index] == "}" else { throw PolynomialError.invalid("Only \\mathrm{d} is supported here.") }
                    index += 1; result.append(.differential)
                default: throw PolynomialError.invalid("\\\(command) is unsupported. This version integrates polynomials only.")
                }
            } else {
                switch character {
                case "+": result.append(.plus)
                case "-", "−": result.append(.minus)
                case "*", "·", "×": result.append(.times)
                case "/": result.append(.divide)
                case "^": result.append(.power)
                case "(", "{": result.append(.open(character))
                case ")", "}": result.append(.close(character))
                case "∫": result.append(.integral)
                default: throw PolynomialError.invalid("Unsupported notation: \(character). Use an indefinite polynomial integral.")
                }
                index += 1
            }
            guard result.count <= 2048 else { throw PolynomialError.invalid("Expression has too many tokens.") }
        }
        return result
    }
}

private nonisolated indirect enum PolynomialAST {
    case number(ExactRational), variable(String), add(Self, Self), multiply(Self, Self), divide(Self, Self), negate(Self), power(Self, Int)
    var variables: Set<String> {
        switch self {
        case .number: []
        case .variable(let value): [value]
        case .add(let a, let b), .multiply(let a, let b), .divide(let a, let b): a.variables.union(b.variables)
        case .negate(let a), .power(let a, _): a.variables
        }
    }
    func polynomial() throws -> PolynomialValue {
        switch self {
        case .number(let n): return PolynomialValue([0: n])
        case .variable: return .variable
        case .add(let a, let b): return try a.polynomial().adding(b.polynomial())
        case .multiply(let a, let b): return try a.polynomial().multiplying(b.polynomial())
        case .negate(let a): return try a.polynomial().negated()
        case .power(let a, let n): return try a.polynomial().power(n)
        case .divide(let a, let b):
            let denominator = try b.polynomial()
            guard denominator.isConstant else { throw PolynomialError.invalid("Division by a variable is unsupported. Use a polynomial.") }
            return try a.polynomial().divided(by: denominator.constant)
        }
    }
}

private nonisolated struct PolynomialParser {
    let tokens: [PolynomialToken]
    var position = 0, nodes = 0
    var current: PolynomialToken? { position < tokens.count ? tokens[position] : nil }
    mutating func node(_ value: PolynomialAST) throws -> PolynomialAST {
        nodes += 1
        guard nodes <= 512 else { throw PolynomialError.invalid("Expression exceeds 512 syntax nodes.") }
        return value
    }
    mutating func expression(_ depth: Int = 0) throws -> PolynomialAST {
        guard depth <= 64 else { throw PolynomialError.invalid("Expression is too deeply nested.") }
        var result = try term(depth)
        while current == .plus || current == .minus {
            let negative = current == .minus; position += 1
            var next = try term(depth)
            if negative { next = try node(.negate(next)) }
            result = try node(.add(result, next))
        }
        return result
    }
    mutating func term(_ depth: Int) throws -> PolynomialAST {
        var result = try unary(depth)
        while let token = current {
            if token == .times || token == .divide {
                position += 1; let next = try unary(depth)
                result = try node(token == .divide ? .divide(result, next) : .multiply(result, next))
            } else if startsAtom(token) {
                result = try node(.multiply(result, unary(depth)))
            } else { break }
        }
        return result
    }
    private func startsAtom(_ token: PolynomialToken) -> Bool {
        switch token { case .number, .variable, .open, .fraction: true; default: false }
    }
    mutating func unary(_ depth: Int) throws -> PolynomialAST {
        guard depth <= 64 else { throw PolynomialError.invalid("Expression is too deeply nested.") }
        if current == .minus { position += 1; return try node(.negate(unary(depth+1))) }
        if current == .plus { position += 1; return try unary(depth+1) }
        var result = try atom(depth)
        if current == .power {
            position += 1; var grouped = false
            if current == .open("{") { position += 1; grouped = true }
            guard case .number(let text) = current, !text.contains("."), let exponent = Int(text), (0...20).contains(exponent) else {
                throw PolynomialError.invalid("Use integer powers from 0 to 20.")
            }
            position += 1
            if grouped { guard current == .close("}") else { throw PolynomialError.invalid("Incomplete exponent.") }; position += 1 }
            result = try node(.power(result, exponent))
        }
        return result
    }
    mutating func group(_ depth: Int, bracesOnly: Bool = false) throws -> PolynomialAST {
        guard case .open(let opening) = current, !bracesOnly || opening == "{" else { throw PolynomialError.invalid("Expected a grouped expression.") }
        position += 1; let result = try expression(depth+1)
        guard current == .close(opening == "{" ? "}" : ")") else { throw PolynomialError.invalid("Unbalanced parentheses or braces.") }
        position += 1; return result
    }
    mutating func atom(_ depth: Int) throws -> PolynomialAST {
        switch current {
        case .number(let text): position += 1; return try node(.number(ExactRational.decimal(text)))
        case .variable(let name): position += 1; return try node(.variable(name))
        case .open: return try group(depth)
        case .fraction:
            position += 1; let top = try group(depth, bracesOnly: true), bottom = try group(depth, bracesOnly: true)
            return try node(.divide(top, bottom))
        default: throw PolynomialError.invalid("Incomplete polynomial expression.")
        }
    }
}

nonisolated struct PreparedPolynomialIntegral: Sendable {
    let inputLatex: String
    let integrand: PolynomialValue
    let inferredVariable: String?
    var suggestedVariable: String { inferredVariable ?? "x" }
    var integrandLatex: String { integrand.latex(variable: suggestedVariable) }
}

nonisolated struct PolynomialIntegrationAnswer: Codable, Sendable {
    let inputLatex: String
    let variable: String
    let integrand: PolynomialValue
    let antiderivative: PolynomialValue
    let latex: String
    let engineVersion: String
}

nonisolated struct PolynomialIntegrationService {
    static let version = "native-polynomial-v1"
    func prepare(_ latex: String) throws -> PreparedPolynomialIntegral {
        var tokens = try PolynomialLexer.tokens(latex.trimmingCharacters(in: .whitespacesAndNewlines))
        var differential: String?
        if tokens.first == .integral {
            tokens.removeFirst()
            guard tokens.count >= 3, case .variable(let name) = tokens.last,
                  tokens[tokens.count-2] == .variable("d") || tokens[tokens.count-2] == .differential else {
                throw PolynomialError.invalid("A full indefinite integral must end with a differential such as dx or dt. Bounds are unsupported.")
            }
            differential = name; tokens.removeLast(2)
        }
        guard !tokens.isEmpty else { throw PolynomialError.invalid("Enter the integrand.") }
        var parser = PolynomialParser(tokens: tokens)
        let ast = try parser.expression()
        guard parser.position == tokens.count else { throw PolynomialError.invalid("Unfinished or unsupported notation. Use one indefinite polynomial integral.") }
        let variables = ast.variables.union(differential.map { [$0] } ?? [])
        guard variables.count <= 1 else { throw PolynomialError.invalid("Use one variable only; symbolic parameters are unsupported.") }
        return PreparedPolynomialIntegral(inputLatex: latex, integrand: try ast.polynomial(), inferredVariable: variables.first)
    }
    func integrate(_ prepared: PreparedPolynomialIntegral, variable: String) throws -> PolynomialIntegrationAnswer {
        try Task.checkCancellation()
        guard variable.count == 1, let letter = variable.first, letter.isASCII, letter.isLetter else {
            throw PolynomialError.invalid("Choose one Latin-letter variable, such as x, t or y.")
        }
        guard prepared.inferredVariable == nil || prepared.inferredVariable == variable else {
            throw PolynomialError.invalid("This expression uses \(prepared.suggestedVariable). Integrate with respect to that variable.")
        }
        let answer = try prepared.integrand.antiderivative()
        guard try answer.derivative() == prepared.integrand else { throw PolynomialError.invalid("The computed antiderivative could not be checked.") }
        let constant = variable == "C" ? "C_{1}" : "C"
        let latex = answer.coefficients.isEmpty ? constant : answer.latex(variable: variable) + " + " + constant
        return PolynomialIntegrationAnswer(inputLatex: prepared.inputLatex, variable: variable, integrand: prepared.integrand,
            antiderivative: answer, latex: latex, engineVersion: Self.version)
    }
}

actor PolynomialComputationWorker {
    static let shared = PolynomialComputationWorker()
    func integrate(_ prepared: PreparedPolynomialIntegral, variable: String) throws -> PolynomialIntegrationAnswer {
        try PolynomialIntegrationService().integrate(prepared, variable: variable)
    }
}

/// Gaussian rationals reuse the bounded mathematical AST, never a script evaluator.
nonisolated struct ExactComplexValue:Equatable,Sendable {
    var real:ExactRational = .zero
    var imaginary:ExactRational = .zero
    var isZero:Bool {real == .zero && imaginary == .zero}
    func adding(_ b:Self)throws->Self {try Self(real:real.adding(b.real),imaginary:imaginary.adding(b.imaginary))}
    func negated()throws->Self {try Self(real:real.negated(),imaginary:imaginary.negated())}
    func multiplying(_ b:Self)throws->Self {
        try Self(real:real.multiplying(b.real).adding(imaginary.multiplying(b.imaginary).negated()),imaginary:real.multiplying(b.imaginary).adding(imaginary.multiplying(b.real)))
    }
    func conjugated()throws->Self {try Self(real:real,imaginary:imaginary.negated())}
    var normSquared:ExactRational {get throws {try real.multiplying(real).adding(imaginary.multiplying(imaginary))}}
    func dividing(_ b:Self)throws->Self {
        let n=try b.normSquared,p=try multiplying(b.conjugated())
        return try Self(real:p.real.dividing(n),imaginary:p.imaginary.dividing(n))
    }
    func power(_ n:Int)throws->Self {
        guard (0...20).contains(n) else {throw PolynomialError.invalid("Use complex integer powers from 0 to 20.")}
        guard !(isZero && n==0) else {throw PolynomialError.invalid("0^0 is undefined in complex calculations.")}
        var p=Self(real:.one)
        for _ in 0..<n {try Task.checkCancellation();p=try p.multiplying(self)}
        return p
    }
    var latex:String {
        if imaginary == .zero {return real.latex}
        let magnitude=try! (imaginary.numerator<0 ? imaginary.negated():imaginary)
        let term=(magnitude == .one ? "":magnitude.latex+"\\,")+"i"
        if real == .zero {return (imaginary.numerator<0 ? "-":"")+term}
        return real.latex+(imaginary.numerator<0 ? " - ":" + ")+term
    }
    static func parse(_ input:String)throws->Self {
        let normalized=input.replacingOccurrences(of:"\\mathrm{i}",with:"i")
        let tokens=try PolynomialLexer.tokens(normalized.trimmingCharacters(in:.whitespacesAndNewlines))
        var parser=PolynomialParser(tokens:tokens);let tree=try parser.expression()
        guard parser.position==tokens.count,tree.variables.isSubset(of:["i"]) else {throw PolynomialError.invalid("Use rational numbers and i, such as (1+i)/(1-i). Other variables and complex radicals are not supported here.")}
        return try tree.complex()
    }
}
private extension PolynomialAST {
    nonisolated func complex()throws->ExactComplexValue {
        try Task.checkCancellation()
        switch self {
        case .number(let n):return ExactComplexValue(real:n)
        case .variable(let v):guard v=="i" else {throw PolynomialError.invalid("Only i is supported in a complex-number expression.")};return ExactComplexValue(imaginary:.one)
        case .add(let a,let b):return try a.complex().adding(b.complex())
        case .multiply(let a,let b):return try a.complex().multiplying(b.complex())
        case .divide(let a,let b):return try a.complex().dividing(b.complex())
        case .negate(let a):return try a.complex().negated()
        case .power(let a,let n):return try a.complex().power(n)
        }
    }
}
