/* Resolves explicit row meanings and earlier definitions in one problem group, then delegates bounded equations to the native algebra solver. */
import Foundation

struct ProblemContextCalculation {
    let answer:MathComputationAnswer
    let sources:[ComputationSourceReference]
    let groupID:UUID
    let substitutions:[String]
}

@MainActor
enum ProblemContextMathService {
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

    /// Resolve earlier rows explicitly marked as definitions and solve the selected constraint when the result fits the native polynomial solver.
    static func calculate(page:Page,target:Step)throws->ProblemContextCalculation {
        guard let groupID=target.problemGroupID,target.isAccepted,target.problemIntent == .constraint else {
            throw PolynomialError.invalid("Group this row with its definitions and mark it as an equation to solve first.")
        }
        let parser=PolynomialIntegrationService()
        var definitions:[String:Definition]=[:]
        let preceding=page.steps.filter { $0.isActive && $0.isAccepted && $0.problemGroupID==groupID && $0.sortIndex<target.sortIndex }
            .sorted{$0.sortIndex<$1.sortIndex}
        for row in preceding where row.problemIntent == .definition {
            let (left,right)=try equationParts(row.acceptedLatex)
            guard let name=try parser.expressionAST(left).singleSymbol else {
                throw PolynomialError.invalid("Mark a definition only when its left side is one variable, such as y = 2x + 11.")
            }
            guard definitions[name]==nil else { throw PolynomialError.invalid("The problem group defines \(name) more than once. Keep one definition or separate the rows.") }
            definitions[name]=Definition(expression:try parser.expressionAST(right),row:row,name:name)
        }
        guard !definitions.isEmpty else { throw PolynomialError.invalid("Mark at least one earlier grouped row as a definition.") }
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
            steps:["Resolve only definitions explicitly marked in this problem group."]+substitutionSteps+solved.steps,engineVersion:solved.engineVersion)
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
