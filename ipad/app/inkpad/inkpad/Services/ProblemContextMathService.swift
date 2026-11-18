/* Infers nearby problem scopes from stored equation ASTs, records row semantics, and delegates verified contextual equations to the native solver. */
import Foundation
import CoreGraphics

struct ProblemContextCalculation {
    let answer:MathComputationAnswer
    let sources:[ComputationSourceReference]
    let groupID:UUID
    let substitutions:[String]
}

@MainActor
enum ProblemContextMathService {
    private struct Statement: Codable {
        let input:String
        let left:PolynomialAST
        let right:PolynomialAST
    }

    /// Reuse an exact-input AST cache or parse and store the current transcription; unsupported syntax is a scope boundary.
    private static func statement(_ row:Step)throws->Statement {
        let input=row.isAccepted ? row.acceptedLatex:row.ghostLaTeX
        if let json=row.problemASTJSON,let cached=try? JSONDecoder().decode(Statement.self,from:Data(json.utf8)),cached.input==input { return cached }
        let (left,right)=try equationParts(input)
        let parser=PolynomialIntegrationService()
        let parsed=Statement(input:input,left:try parser.expressionAST(left),right:try parser.expressionAST(right))
        row.problemASTJSON=String(decoding:try JSONEncoder().encode(parsed),as:UTF8.self)
        return parsed
    }

    /// Infer scopes in page order from nearby equation ASTs. Text, unread ink, large gaps, new definitions after a target, repeated symbols and user boundaries start fresh scopes.
    static func refresh(page:Page) {
        var members:[Step]=[],names=Set<String>(),previous:Step?,hasTarget=false
        for row in page.steps.filter({$0.isActive}).sorted(by:{$0.sortIndex<$1.sortIndex}) {
            guard ![.collecting,.recognizing,.failed].contains(row.recognitionState),let ast=try? statement(row) else {
                row.problemGroupID=nil;row.problemIntent = .automatic;row.problemASTJSON=nil
                members=[];names=[];previous=nil;hasTarget=false;continue
            }
            let name=ast.left.singleSymbol
            let isDefinition=name.map{!ast.right.variables.contains($0)} ?? false
            var separated=row.problemStartsNewScope == true
            if let previous {
                let a=previous.bounds,b=row.bounds
                let gap=b.minY-a.maxY
                let sameColumn=max(a.minX,b.minX)<=min(a.maxX,b.maxX)+80
                separated = separated || gap>max(96,2*max(a.height,b.height)) || !sameColumn
            }
            if isDefinition && (hasTarget || name.map(names.contains)==true) { separated=true }
            if separated { members=[];names=[];hasTarget=false }
            row.problemIntent = isDefinition ? .definition:.constraint
            // Stable first-row identity keeps unchanged scopes and their source manifests stable across refreshes.
            let groupID=members.first?.stableID ?? row.stableID
            row.problemGroupID=groupID
            members.append(row)
            if isDefinition,let name { names.insert(name) } else { hasTarget=true }
            previous=row
        }
        for row in page.steps where !row.isActive { row.problemGroupID=nil;row.problemIntent = .automatic }
    }

    private struct Definition {
        let expression:PolynomialAST
        let row:Step
        let name:String
    }

    /// Capture every active row in the problem so later additions, role changes, edits, moves or ungrouping invalidate dependent results.
    static func manifest(page:Page,groupID:UUID)->[ComputationSourceReference] {
        page.steps.filter{$0.isActive && $0.problemGroupID==groupID}.sorted{$0.sortIndex<$1.sortIndex}.map { row in
            ComputationSourceReference(stableID:row.stableID,acceptedRevisionNumber:row.latestAcceptedRevisionNumber,
                acceptedFingerprint:row.acceptedFingerprint,acceptedLatex:row.acceptedLatex,problemGroupID:groupID,
                rowIndex:row.sortIndex,intentRaw:row.problemIntent.rawValue,isAccepted:row.isAccepted,strokeFingerprint:row.strokeFingerprint)
        }
    }

    /// Resolve the detected earlier definitions and solve the reviewed target when its substituted AST fits the native polynomial solver.
    static func calculate(page:Page,target:Step)throws->ProblemContextCalculation {
        guard let groupID=target.problemGroupID,target.isAccepted,target.problemIntent != .automatic else {
            throw PolynomialError.invalid("Review the recognized equation first.")
        }
        let parser=PolynomialIntegrationService()
        var definitions:[String:Definition]=[:]
        let preceding=page.steps.filter { $0.isActive && $0.problemGroupID==groupID && $0.sortIndex<target.sortIndex }
            .sorted{$0.sortIndex<$1.sortIndex}
        for row in preceding where row.problemIntent == .definition {
            let ast=try statement(row)
            guard let name=ast.left.singleSymbol else {
                throw PolynomialError.invalid("Mark a definition only when its left side is one variable, such as y = 2x + 11.")
            }
            guard definitions[name]==nil else { throw PolynomialError.invalid("The problem group defines \(name) more than once. Keep one definition or separate the rows.") }
            definitions[name]=Definition(expression:ast.right,row:row,name:name)
        }
        guard !definitions.isEmpty else { throw PolynomialError.invalid("No earlier definitions were detected in this problem.") }
        let (targetLeft,targetRight)=try equationParts(target.acceptedLatex)
        let left=try parser.expressionAST(targetLeft),right=try parser.expressionAST(targetRight)
        var pending=left.variables.union(right.variables),visited=Set<String>(),used=Set<String>()
        while let name=pending.subtracting(visited).first {
            visited.insert(name)
            if let definition=definitions[name] {
                used.insert(name);pending.formUnion(definition.expression.variables)
            }
        }
        guard !used.isEmpty else { throw PolynomialError.invalid("This equation does not use any earlier grouped definitions.") }
        let needed=definitions.filter{used.contains($0.key)}
        guard needed.values.allSatisfy({$0.row.isAccepted}) else { throw PolynomialError.invalid("Verify the transcription of the earlier definitions before solving.") }
        let substitutedLeft=try left.replacingSymbols(needed.mapValues(\.expression))
        let substitutedRight=try right.replacingSymbols(needed.mapValues(\.expression))
        let remainingVariables=substitutedLeft.variables.union(substitutedRight.variables)
        guard remainingVariables.count<=1 else {
            throw PolynomialError.invalid("After substitution, this solver supports one unresolved variable. Keep other symbols as explicit definitions or choose a supported equation.")
        }
        let variable=remainingVariables.first ?? "x"
        let difference=try substitutedLeft.polynomial().adding(substitutedRight.polynomial().negated())
        guard difference.degree<=2 else { throw PolynomialError.invalid("Substitution produced an equation above degree two, outside the native equation solver's supported range.") }
        let equation=difference.latex(variable:variable)+"=0"
        let request=MathComputationRequest(operation:.solveEquation,inputA:equation,variable:variable)
        let solved=try MathComputationService().compute(request)
        let orderedDefinitions=needed.values.sorted{$0.row.sortIndex<$1.row.sortIndex}
        let substitutionSteps=orderedDefinitions.map { "Substitute Row \($0.row.sortIndex+1): \($0.name) = \($0.row.acceptedLatex.components(separatedBy:"=").dropFirst().joined(separator:"="))" }
        let answer=MathComputationAnswer(request:solved.request,inputLatex:target.acceptedLatex,outputLatex:solved.outputLatex,
            steps:["Use the detected definitions shown in this problem review."]+substitutionSteps+solved.steps,engineVersion:solved.engineVersion)
        let sources=manifest(page:page,groupID:groupID)
        return ProblemContextCalculation(answer:answer,sources:sources,groupID:groupID,substitutions:substitutionSteps)
    }

    /// Split one simple equality while rejecting missing sides or chained equations.
    private static func equationParts(_ latex:String)throws->(String,String) {
        let parts=latex.components(separatedBy:"=")
        guard parts.count==2,parts.allSatisfy({!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}) else {
            throw PolynomialError.invalid("Contextual solve needs one equation with exactly one equals sign.")
        }
        return (parts[0],parts[1])
    }
}
