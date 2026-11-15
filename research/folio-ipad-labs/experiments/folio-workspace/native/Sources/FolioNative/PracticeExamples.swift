import SwiftUI

struct PracticeExample: Identifiable {
    let title: String
    let latex: String
    let symbols: String
    let mode: String
    var id: String { title }
    init(_ title: String, _ latex: String, _ symbols: String, mode: String = "math") {
        self.title = title; self.latex = latex; self.symbols = symbols; self.mode = mode
    }
}

struct PracticeTopic: Identifiable {
    let title: String
    let level: String
    let note: String
    let examples: [PracticeExample]
    var id: String { title }
    static var entries: [(topic: PracticeTopic, example: PracticeExample)] {
        all.flatMap { group in group.examples.map { (topic: group, example: $0) } }
    }
    static func matching(topic: String, query: String) -> [(topic: PracticeTopic, example: PracticeExample)] {
        entries.filter { row in
            (topic == "All topics" || row.topic.title == topic) &&
            (query.isEmpty || "\(row.topic.title) \(row.topic.level) \(row.example.title) \(row.example.latex) \(row.example.symbols)".localizedCaseInsensitiveContains(query))
        }
    }
    static let all: [PracticeTopic] = [
        .init(title: "Numbers", level: "Elementary", note: "Choose Numbers mode for digits and arithmetic. Keep decimal points and small marks distinct.", examples: [
            .init("Addition and equality", "27+15=42", "+ adds; = means equal.", mode: "numbers"),
            .init("Multiplication and division", #"24\div6=2\times2"#, "÷ divides; × multiplies.", mode: "numbers"),
            .init("Signed decimals", "-3.5+8.25=4.75", "A minus sign and a decimal point change the number.", mode: "numbers"),
            .init("Percentages", #"25\%"#, "% means per hundred. This is notation recognition, not percent calculation.", mode: "numbers"),
            .init("Ratios", "3:4=6:8", "The colon separates the two parts of a ratio.", mode: "numbers"),
            .init("Comparisons", #"-2<0\leq5"#, "< means less than; ≤ means less than or equal to.", mode: "numbers"),
            .init("Approximation", #"3.1416\approx3.14"#, "≈ means approximately equal.", mode: "numbers"),
            .init("Absolute value", "|-7|=7", "Vertical bars denote absolute value.", mode: "numbers")
        ]),
        .init(title: "Fractions and powers", level: "Grades 6-10", note: "Leave vertical space for numerators, denominators, and exponents. Write a fraction bar, not a slash, to test stacked recognition.", examples: [
            .init("Stacked fractions", #"\frac{3}{4}+\frac{1}{8}"#, "The fraction bar separates numerator and denominator.", mode: "numbers"),
            .init("Mixed numbers", #"2\frac{1}{3}"#, "A whole number beside a proper fraction.", mode: "numbers"),
            .init("Square roots", #"\sqrt{49}=7"#, "√ is a radical sign. Extend its bar over the full radicand.", mode: "numbers"),
            .init("Negative exponents", #"2^{-3}=\frac{1}{8}"#, "A raised negative exponent represents a reciprocal power.", mode: "numbers"),
            .init("Fractional exponents", #"x^{\frac{2}{3}}"#, "The entire fraction belongs in the exponent."),
            .init("Scientific notation", #"6.02\times10^{23}"#, "× and a raised power of 10 express scientific notation.", mode: "numbers")
        ]),
        .init(title: "Algebra and geometry", level: "Grades 7-10", note: "Use Algebra mode when letters appear. The app transcribes an equation; it does not solve it or check the answer.", examples: [
            .init("Linear equations", "3x+7=22", "x is a variable, not a multiplication sign."),
            .init("Polynomial terms", "2x^2-5x+3", "A coefficient, variable, and superscript form a term."),
            .init("Factoring", "x^2-9=(x-3)(x+3)", "Parentheses group factors."),
            .init("Quadratic formula", #"x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}"#, "± means plus or minus; the root covers the discriminant."),
            .init("Slope", #"m=\frac{y_2-y_1}{x_2-x_1}"#, "Subscripts distinguish coordinate pairs."),
            .init("Circle area", #"A=\pi r^2"#, "π is pi; r is the radius. Geometry diagrams are not interpreted."),
            .init("Angle measures", #"60^\circ+120^\circ=180^\circ"#, "A small raised circle denotes degrees.", mode: "numbers"),
            .init("Pythagorean notation", "a^2+b^2=c^2", "Raised 2s denote squares, not adjacent digits.")
        ]),
        .init(title: "Functions", level: "Grades 11-12", note: "Function notation, logarithms, and sets are in the training scope. Dense grouping still needs careful review.", examples: [
            .init("Function evaluation", "f(3)=3^2+2", "f(3) is a function evaluated at 3."),
            .init("Rational functions", #"f(x)=\frac{x+2}{x^2-9}"#, "Keep the full numerator above the fraction bar."),
            .init("Exponential functions", "y=3(2)^x", "x is the exponent, not a subscript."),
            .init("Logarithms with a base", #"\log_2(8)=3"#, "log denotes a logarithm; the subscript is its base."),
            .init("Natural logarithms", #"\ln(x+1)=2"#, "ln is a natural logarithm, not the letters i and n."),
            .init("Inverse functions", #"f^{-1}(x)=\frac{x-3}{2}"#, "The raised -1 denotes an inverse function in this notation."),
            .init("Function composition", #"(f\circ g)(x)=(2x+1)^2"#, "The small circle between f and g means composition, not degrees."),
            .init("Domain restrictions", #"D=\{x\in\mathbb{R}\mid x\ne3\}"#, "∈ means belongs to; ℝ denotes real numbers; ≠ means not equal."),
            .init("Intervals and infinity", #"(-\infty,2]\cup[5,\infty)"#, "∞ denotes infinity; ∪ joins sets. Parentheses exclude endpoints; square brackets include them.")
        ]),
        .init(title: "Trigonometry", level: "Grades 10-12", note: "Make theta distinct from zero. Keep fractions and angles separate from function names.", examples: [
            .init("Sine of an angle", #"\sin\theta=\frac{3}{5}"#, "sin is sine; θ is the Greek letter theta."),
            .init("Cosine and tangent", #"\tan\theta=\frac{\sin\theta}{\cos\theta}"#, "cos denotes cosine; tan denotes tangent."),
            .init("Radian measures", #"\theta=\frac{2\pi}{3}"#, "Radians express angles using π rather than a degree mark."),
            .init("Transformed sine", #"y=2\sin(3x-1)+4"#, "The parentheses define the input to sine."),
            .init("Cosine law", #"c^2=a^2+b^2-2ab\cos C"#, "Uppercase C denotes the angle opposite side c.")
        ]),
        .init(title: "Sequences and finance", level: "Grades 11-12", note: "Check subscripts and n-1 exponents especially carefully; these were less reliable in the small test.", examples: [
            .init("Arithmetic sequences", "a_n=3+2(n-1)", "The subscript n identifies the term number."),
            .init("Geometric sequences", "a_n=5(2)^{n-1}", "The entire n-1 belongs in the exponent."),
            .init("Summation", #"\sum_{k=1}^{10}k^2"#, "Σ means sum; the lower and upper limits specify which terms."),
            .init("Compound interest", "A=1000(1+0.05)^{10}", "A principal, growth factor, and exponent form the expression. Folio does not calculate the balance."),
            .init("Annuity notation", #"FV=100\frac{(1+0.05)^{12}-1}{0.05}"#, "A nested exponent and fraction express a future-value formula.")
        ]),
        .init(title: "Probability and data", level: "Grades 11-12", note: "Bars, subscripts, factorials, and large operators all carry meaning. Start with one short expression per row.", examples: [
            .init("Factorials", "5!=120", "! denotes factorial, not punctuation.", mode: "numbers"),
            .init("Combinations", #"\binom{8}{3}"#, "Two stacked numbers inside parentheses mean 8 choose 3."),
            .init("Probability", #"P(A)=\frac{3}{8}"#, "P(A) denotes the probability of event A."),
            .init("Conditional probability", #"P(A\mid B)=\frac{P(A\cap B)}{P(B)}"#, "| means given; ∩ means intersection. This formula assumes P(B) > 0."),
            .init("Union of events", #"P(A\cup B)=P(A)+P(B)-P(A\cap B)"#, "∪ means union; ∩ is the overlap of two events."),
            .init("Sample mean", #"\bar{x}=\frac{2+4+6}{3}"#, "A bar above x denotes the sample mean."),
            .init("Standard score", #"z=\frac{x-\mu}{\sigma}"#, "μ is mu, often the population mean; σ is sigma, often the standard deviation.")
        ]),
        .init(title: "Calculus", level: "Grade 12", note: "Limits can be misread. Check the approach value and fraction grouping. Recognition is not differentiation, limit evaluation, or proof checking.", examples: [
            .init("Limits", #"\lim_{x\to2}\frac{x^2-4}{x-2}"#, "lim denotes a limit; → means approaches."),
            .init("Derivative operator", #"\frac{d}{dx}x^3=3x^2"#, "d/dx denotes differentiation with respect to x."),
            .init("Prime notation", #"f^{\prime}(x)=2x+3"#, "A prime mark after f denotes a derivative."),
            .init("Tangent lines", "y-4=3(x-2)", "Point-slope notation can describe a tangent line.")
        ]),
        .init(title: "Vectors", level: "Grade 12", note: "Arrow marks distinguish vectors from scalar variables. Component lists and formulas are supported notation; drawn 3D diagrams are not interpreted.", examples: [
            .init("Vector components", #"\vec{v}=\langle2,-1,3\rangle"#, "An arrow identifies a vector; angle brackets enclose components."),
            .init("Vector magnitude", #"\|\vec{v}\|=\sqrt{2^2+(-1)^2+3^2}"#, "Double bars denote magnitude or norm."),
            .init("Dot products", #"\vec{u}\cdot\vec{v}=2(3)+1(4)"#, "A centered dot denotes the vector dot product here."),
            .init("Vector line equations", #"\vec{r}=(1,2,3)+t(2,-1,4)"#, "The parameter t moves along the direction vector."),
            .init("Plane equations", "2x+3y-z=7", "Three coordinate variables can describe a plane.")
        ]),
        .init(title: "Extensions", level: "Beyond Ontario core", note: "These were included as extensions for other courses. They are not claims about Ontario Grade 12 core requirements.", examples: [
            .init("Matrices", #"\begin{pmatrix}1&2\\3&4\end{pmatrix}"#, "A matrix arranges entries in rows and columns. Multirow recognition can split the ink."),
            .init("Definite integrals", #"\int_0^2 x^2\,dx"#, "∫ denotes integration; 0 and 2 are bounds. Folio does not evaluate the integral."),
            .init("Complex numbers", "z=3+2i", "i denotes the imaginary unit in this context.")
        ])
    ]
}

struct PracticeGallery: View {
    @Environment(\.dismiss) private var dismiss
    @State private var topic = "Calculus"
    @State private var query = ""
    @State private var selectedID = "Derivative operator"
    private let ink = Color(red: 0.15, green: 0.18, blue: 0.20)
    private let muted = Color(red: 0.35, green: 0.40, blue: 0.42)
    private let accent = Color(red: 0.09, green: 0.42, blue: 0.38)
    private var entries: [(topic: PracticeTopic, example: PracticeExample)] {
        PracticeTopic.entries
    }
    private var filtered: [(topic: PracticeTopic, example: PracticeExample)] {
        PracticeTopic.matching(topic: topic, query: query)
    }
    private var selection: (topic: PracticeTopic, example: PracticeExample)? {
        filtered.first { $0.example.id == selectedID } ?? filtered.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Examples to write").font(.system(size: 28, weight: .medium, design: .serif))
                    Text("\(entries.count) practice examples, from arithmetic to Grade 12 notation.").foregroundStyle(muted)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Copy an expression by hand in your notebook. These are typeset references, not guaranteed recognition results. Folio reads notation; it does not solve the mathematics.")
                .font(.callout).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Find a topic or symbol", text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search practice examples")
                Picker("Topic", selection: $topic) {
                    Text("All topics").tag("All topics")
                    ForEach(PracticeTopic.all) { group in Text(group.title).tag(group.title) }
                }.labelsHidden().frame(maxWidth: 220)
            }
            Divider()
            GeometryReader { geometry in
                if geometry.size.width >= 650 {
                    HStack(alignment: .top, spacing: 24) {
                        catalog.frame(width: 230)
                        Divider()
                        detail
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        catalog.frame(height: 160)
                        Divider()
                        detail
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 900, minHeight: 580, idealHeight: 700)
        .onChange(of: topic) { _, value in
            selectedID = PracticeTopic.matching(topic: value, query: query).first?.example.id ?? ""
        }
        .foregroundStyle(ink).tint(accent)
        .background(Color(red: 0.97, green: 0.98, blue: 0.98))
        .environment(\.colorScheme, .light)
    }
    private var catalog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filtered, id: \.example.id) { row in
                        Button { selectedID = row.example.id } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.example.title).font(.body.weight(.medium))
                                Text(row.topic.title).font(.caption).foregroundStyle(muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(selection?.example.id == row.example.id ? accent.opacity(0.10) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(selection?.example.id == row.example.id ? .isSelected : [])
                            .id(row.example.id)
                    }
                }
            }
            .task(id: topic + "|" + query) {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                proxy.scrollTo(selection?.example.id, anchor: .center)
            }
        }
    }
    @ViewBuilder private var detail: some View {
        if let row = selection {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("\(row.topic.title) · \(row.topic.level)").font(.subheadline).foregroundStyle(muted)
                    Text(row.example.title).font(.system(size: 24, weight: .medium, design: .serif))
                    MathPreview(latex: row.example.latex).frame(height: 150)
                        .accessibilityLabel(row.example.title + ": " + row.example.symbols)
                    Label(row.example.mode == "numbers" ? "Use Numbers mode" : "Use Algebra mode", systemImage: "pencil.tip")
                        .font(.subheadline.weight(.medium)).foregroundStyle(accent)
                    Text(row.example.symbols).fixedSize(horizontal: false, vertical: true)
                    Text(row.topic.note).font(.callout).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("LaTeX transcription") {
                        Text(row.example.latex).font(.system(.body, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    Text("Close this gallery to write. Opening examples does not change your ink or accepted text.")
                        .font(.caption).foregroundStyle(muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}
