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

    /// Capture the current problem prefix through a target so source edits invalidate answers while later working stays independent.
    static func manifest(page:Page,groupID:UUID,through target:Step?=nil)->[ComputationSourceReference] {
        page.steps.filter{$0.isActive && $0.problemGroupID==groupID && (target == nil || $0.sortIndex<=target!.sortIndex)}.sorted{$0.sortIndex<$1.sortIndex}.map { row in
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
        let resultSources:[ComputationResultReference]
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
        var derived:[String:ComputationResultReference]=[:]
        for row in page.steps.filter({$0.isActive && $0.problemGroupID==groupID && $0.sortIndex<target.sortIndex}) {
            guard let result=row.computationResults.filter({!$0.isRemoved && $0.operationRaw==MathOperation.solveEquation.rawValue && $0.isCurrent}).sorted(by:{$0.createdAt>$1.createdAt}).first,
                  let notation=try? WorksheetMathNotation.read(result.outputLatex),notation.kind == .definition,notation.arguments.isEmpty,let name=notation.name,
                  let ast=try? PolynomialIntegrationService().expressionAST(notation.body),ast.variables.isEmpty,
                  (try? ast.polynomial()) != nil else { continue }
            guard definitions[name]==nil else { throw PolynomialError.invalid("This problem has more than one binding for \(name). Review its definitions and solved results.") }
            definitions[name]=(notation,row)
            derived[name]=ComputationResultReference(stableID:result.stableID,sourceID:row.stableID,outputLatex:result.outputLatex,requestJSON:result.requestJSON)
        }
        var usedResults:[ComputationResultReference]=[]
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
            for name in definitions.keys.sorted(by:{ lhs,rhs in
                let leftCall = !definitions[lhs]!.0.arguments.isEmpty,rightCall = !definitions[rhs]!.0.arguments.isEmpty
                return leftCall == rightCall ? lhs<rhs:leftCall
            }) {
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
                    if let result=derived[name],!usedResults.contains(result) {
                        usedResults.append(result);summaries.append("Solved Row \(row.sortIndex+1): \(result.outputLatex)")
                    } else if used.insert(row.stableID).inserted { summaries.append("Row \(row.sortIndex+1): \(row.acceptedLatex)") }
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
        if request.operation == .solveEquation,let variable=AlgebraComputationService().suggestedVariable(request.inputA) {
            request.variable=variable
        }
        if request.operation.needsB { request.inputB=try expand(request.inputB,protected:protected) }
        if request.operation.needsPoint { request.point=try expand(request.point,protected:[]) }
        if request.operation.needsInterval {
            request.lower=try expand(request.lower,protected:[]);request.upper=try expand(request.upper,protected:[])
        }
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
        return Plan(request:request,sources:manifest(page:page,groupID:groupID,through:target),groupID:groupID,summaries:summaries,resultSources:usedResults)
    }

}
