/* Infers nearby problem scopes from stored equation ASTs, records row semantics, and delegates verified contextual equations to the native solver. */
import Foundation
import CoreGraphics

@MainActor
enum ProblemContextMathService {
    /// Store semantic statements and infer page-local scopes independently of solver support, keeping separate columns in separate lanes.
    static func refresh(page:Page) {
        struct Lane { var rows:[Step]=[];var names=Set<String>();var hasTarget=false }
        var lanes:[Lane]=[]
        for row in page.steps.filter({$0.isActive && $0.source != .manual}).sorted(by:{$0.sortIndex<$1.sortIndex}) {
            let laneIndex=lanes.indices.filter { index in
                guard let last=lanes[index].rows.last else { return false }
                return abs(last.bounds.minX-row.bounds.minX)<140
            }.min { abs(lanes[$0].rows.last!.bounds.minX-row.bounds.minX)<abs(lanes[$1].rows.last!.bounds.minX-row.bounds.minX) }
            let index=laneIndex ?? lanes.count
            if index==lanes.count { lanes.append(Lane()) }
            guard ![.collecting,.recognizing,.failed].contains(row.recognitionState),let notation=try? WorksheetMathNotation.read(row.isAccepted ? row.acceptedLatex:row.ghostLaTeX) else {
                row.problemGroupID=nil;row.problemIntent = .automatic;row.problemASTJSON=nil
                lanes[index]=Lane();continue
            }
            var lane=lanes[index]
            var separated=row.problemStartsNewScope == true || notation.numbered
            if let last=lane.rows.last {
                let gap=row.bounds.minY-last.bounds.maxY
                separated = separated || gap>max(96,2*max(last.bounds.height,row.bounds.height))
            }
            let name=notation.name
            let definition=notation.kind == .definition
            if definition && (lane.hasTarget || name.map(lane.names.contains)==true) { separated=true }
            if separated { lane=Lane() }
            row.problemIntent = definition ? .definition:.constraint
            row.problemGroupID=lane.rows.first?.stableID ?? row.stableID
            row.problemASTJSON=String(decoding:(try? JSONEncoder().encode(notation)) ?? Data(),as:UTF8.self)
            lane.rows.append(row)
            if definition,let name { lane.names.insert(name) } else { lane.hasTarget=true }
            lanes[index]=lane
        }
        for row in page.steps where !row.isActive { row.problemGroupID=nil;row.problemIntent = .automatic }
    }

    /// Capture every active row in the problem so later additions, role changes, edits, moves or ungrouping invalidate dependent results.
    static func manifest(page:Page,groupID:UUID)->[ComputationSourceReference] {
        page.steps.filter{$0.isActive && $0.problemGroupID==groupID}.sorted{$0.sortIndex<$1.sortIndex}.map { row in
            ComputationSourceReference(stableID:row.stableID,acceptedRevisionNumber:row.latestAcceptedRevisionNumber,
                acceptedFingerprint:row.acceptedFingerprint,acceptedLatex:row.acceptedLatex,problemGroupID:groupID,
                rowIndex:row.sortIndex,intentRaw:row.problemIntent.rawValue,isAccepted:row.isAccepted,strokeFingerprint:row.strokeFingerprint)
        }
    }

    struct Plan {
        let request:MathComputationRequest
        let sources:[ComputationSourceReference]
        let groupID:UUID
        let summaries:[String]
    }

    /// Expand only earlier definitions in this stored problem scope; preserve the calculus variable as a bound parameter.
    static func plan(_ original:MathComputationRequest,page:Page,target:Step)throws->Plan {
        guard let groupID=target.problemGroupID,target.isAccepted else { throw PolynomialError.invalid("Review this row's transcription first.") }
        let targetNotation=try WorksheetMathNotation.read(original.inputA)
        let rows=page.steps.filter{$0.isActive && $0.problemGroupID==groupID && $0.sortIndex<target.sortIndex && $0.problemIntent == .definition}.sorted{$0.sortIndex<$1.sortIndex}
        var definitions:[String:(WorksheetMathNotation,Step)]=[:]
        for row in rows {
            let notation=try WorksheetMathNotation.read(row.isAccepted ? row.acceptedLatex:row.ghostLaTeX)
            if let name=notation.name { definitions[name]=(notation,row) }
        }
        var request=original
        var summaries:[String]=[],used=Set<UUID>(),stack=Set<String>(),budget=400
        let boundVariable=targetNotation.variable ?? original.variable
        if request.operation.isCalculus { request.variable=boundVariable }

        /// Replace symbol tokens without touching LaTeX command names or longer identifiers.
        func replaceSymbol(_ expression:String,_ symbol:String,_ replacement:String)->String {
            let pattern="(?<![A-Za-z\\\\])"+NSRegularExpression.escapedPattern(for:symbol)+"(?![A-Za-z])"
            guard let regex=try? NSRegularExpression(pattern:pattern) else { return expression }
            return regex.stringByReplacingMatches(in:expression,range:NSRange(expression.startIndex...,in:expression),withTemplate:NSRegularExpression.escapedTemplate(for:replacement))
        }

        /// Expand supported calls and scalar bindings with a bounded dependency stack, rejecting unreviewed sources and cycles.
        func expand(_ expression:String,protected:Set<String>)throws->String {
            budget-=1
            guard budget>0,expression.count<=10000,stack.count<24 else { throw PolynomialError.invalid("The problem's definitions are too deeply nested.") }
            var output=expression
            for name in definitions.keys.sorted() {
                let (definition,row)=definitions[name]!
                if definition.arguments.isEmpty && protected.contains(name) { continue }
                let pattern=definition.arguments.isEmpty ? "(?<![A-Za-z\\\\])"+name+"(?![A-Za-z])":"(?<![A-Za-z\\\\])"+name+"\\(([^()]*)\\)"
                guard let regex=try? NSRegularExpression(pattern:pattern) else { continue }
                let matches=regex.matches(in:output,range:NSRange(output.startIndex...,in:output))
                for match in matches.reversed() {
                    guard let range=Range(match.range,in:output) else { continue }
                    guard row.isAccepted else { throw PolynomialError.invalid("Verify Row \(row.sortIndex+1)'s definition before computing.") }
                    guard !stack.contains(name) else { throw PolynomialError.invalid("Circular definition involving \(name).") }
                    var body=definition.body
                    if !definition.arguments.isEmpty {
                        guard let argumentRange=Range(match.range(at:1),in:output) else { continue }
                        let actual=output[argumentRange].split(separator:",",omittingEmptySubsequences:false).map(String.init)
                        guard actual.count==definition.arguments.count else { throw PolynomialError.invalid("Review the arguments of \(name).") }
                        // Formal parameters are protected while resolving external definitions; substitute actual arguments afterward.
                        stack.insert(name)
                        body=try expand(body,protected:protected.union(definition.arguments))
                        stack.remove(name)
                        let placeholders=definition.arguments.indices.map{"__FOLIOARG\($0)__"}
                        for (parameter,placeholder) in zip(definition.arguments,placeholders) { body=replaceSymbol(body,parameter,placeholder) }
                        for (placeholder,value) in zip(placeholders,actual) { body=body.replacingOccurrences(of:placeholder,with:"("+value+")") }
                    } else {
                        stack.insert(name);body=try expand(body,protected:protected);stack.remove(name)
                    }
                    if used.insert(row.stableID).inserted { summaries.append("Row \(row.sortIndex+1): \(row.acceptedLatex)") }
                    output.replaceSubrange(range,with:"("+body+")")
                }
            }
            guard output.count<=10000 else { throw PolynomialError.invalid("Expanded expression is too long.") }
            return output
        }

        if targetNotation.kind == .derivative || targetNotation.kind == .partial {
            request.operation=targetNotation.kind == .partial ? .partialDerivative:(targetNotation.order==2 ? .secondDerivative:.derivative)
            request.variable=boundVariable
            if let name=targetNotation.name {
                guard let (definition,_)=definitions[name] else { throw PolynomialError.invalid("No definition of \(name) was found in this problem. Other problems are kept separate.") }
                if targetNotation.variable==nil,let variable=definition.arguments.first { request.variable=variable }
                let actual=definition.arguments.count==1 ? [request.variable]:definition.arguments
                request.inputA=definition.arguments.isEmpty ? name:name+"("+actual.joined(separator:",")+")"
            } else { request.inputA=targetNotation.body }
        } else if targetNotation.kind == .definition {
            request.inputA=targetNotation.body
            if let variable=targetNotation.variable { request.variable=variable }
        } else { request.inputA=targetNotation.text }
        var protected:Set<String>=request.operation.isCalculus ? [request.variable]:[]
        if request.operation == .partialDerivative,let name=targetNotation.name,let (definition,_)=definitions[name] {
            protected.formUnion(definition.arguments)
        }
        request.inputA=try expand(request.inputA,protected:protected)
        if request.operation.needsB { request.inputB=try expand(request.inputB,protected:protected) }
        // Names of declared functions may be recognized elsewhere, but their values never enter this scope.
        var functionNames=Set(["f","g","h"])
        for row in page.steps where row.isActive {
            if let notation=try? WorksheetMathNotation.read(row.isAccepted ? row.acceptedLatex:row.ghostLaTeX),!notation.arguments.isEmpty,let name=notation.name { functionNames.insert(name) }
        }
        for name in functionNames {
            if request.inputA.range(of:"(?<![A-Za-z\\\\])"+name+"\\s*\\(",options:.regularExpression) != nil {
                throw PolynomialError.invalid("Function \(name) has no supported definition in this problem. Other problems are kept separate.")
            }
        }
        return Plan(request:request,sources:manifest(page:page,groupID:groupID),groupID:groupID,summaries:summaries)
    }

}
