/* Finds paired square-bracket matrix bounds and conservative whitespace grids without changing source ink. */
import Foundation
import PencilKit

/// Stroke ownership keeps neighboring expressions out of a matrix recognition crop.
struct MatrixInkLayout {
    let strokeIndices:Set<Int>
    let bounds:CGRect
    let cells:[[Data]]?

    /// Find innermost nonoverlapping bracket pairs. Skip cell archives for live segmentation; bare determinant bars are excluded.
    static func detect(in strokes:[PKStroke],extractCells:Bool=true)->[Self] {
        let brackets=strokes.indices.compactMap { bracket(at:$0,in:strokes) }
        var proposals:[(Bracket,Bracket)]=[]
        for left in brackets where left.opensRight {
            for right in brackets where !right.opensRight {
                let overlap=min(left.bounds.maxY,right.bounds.maxY)-max(left.bounds.minY,right.bounds.minY)
                if right.bounds.minX>left.bounds.maxX+16,
                   overlap>=max(left.bounds.height,right.bounds.height)*0.75,
                   min(left.bounds.height,right.bounds.height)>=max(left.bounds.height,right.bounds.height)*0.7 {
                    proposals.append((left,right))
                }
            }
        }
        proposals.sort { $0.1.bounds.maxX-$0.0.bounds.minX < $1.1.bounds.maxX-$1.0.bounds.minX }
        var used=Set<Int>(),result:[Self]=[]
        for (left,right) in proposals {
            let bounds=left.bounds.union(right.bounds)
            let interior=CGRect(x:left.axis+4,y:bounds.minY-4,
                width:right.axis-left.axis-8,height:bounds.height+8)
            let rails=left.indices.union(right.indices)
            let entries=Set(strokes.indices.filter { index in
                let b=strokes[index].renderBounds
                return !rails.contains(index) && interior.insetBy(dx:3,dy:-4).contains(CGPoint(x:b.midX,y:b.midY))
                    && bounds.insetBy(dx:-4,dy:-4).contains(b)
            })
            guard entries.count>=2 else { continue }
            let indices=rails.union(entries)
            guard used.isDisjoint(with:indices) else { continue }
            // Require entries on at least two vertical levels; avoid ordinary single-line parentheses.
            let entryBounds=entries.map { strokes[$0].renderBounds }
            let height=typicalHeight(entryBounds)
            guard let top=entryBounds.map(\.midY).min(),let bottom=entryBounds.map(\.midY).max(),bottom-top>=height*1.5 else { continue }
            result.append(Self(strokeIndices:indices,bounds:bounds,cells:extractCells ? grid(entries:entries,strokes:strokes):nil))
            used.formUnion(indices)
        }
        return result
    }

    private struct Bracket {
        let indices:Set<Int>
        let bounds:CGRect
        let opensRight:Bool
        let axis:CGFloat
    }

    /// Accept tall rails with inward hooks at BOTH ends, including separately drawn short caps.
    private static func bracket(at index:Int,in strokes:[PKStroke])->Bracket? {
        let stroke=strokes[index],rail=stroke.renderBounds
        guard rail.height>=60,rail.height>=rail.width*2.5 else { return nil }
        var indices:Set<Int>=[index]
        for other in strokes.indices where other != index {
            let b=strokes[other].renderBounds
            if b.height<=max(10,rail.height*0.12),b.width<=rail.height*0.35,
               b.minX<=rail.maxX+5,b.maxX>=rail.minX-5,
               min(abs(b.midY-rail.minY),abs(b.midY-rail.maxY))<=8 {
                indices.insert(other)
            }
        }
        let points=indices.flatMap { i in strokes[i].path.map { $0.location.applying(strokes[i].transform) } }
        let middle=points.filter { $0.y>rail.minY+rail.height*0.3 && $0.y<rail.maxY-rail.height*0.3 }.map(\.x).sorted()
        guard !middle.isEmpty else { return nil }
        let x=middle[middle.count/2]
        let top=points.filter { $0.y<=rail.minY+rail.height*0.18 }.map(\.x)
        let bottom=points.filter { $0.y>=rail.maxY-rail.height*0.18 }.map(\.x)
        guard let topMin=top.min(),let topMax=top.max(),let bottomMin=bottom.min(),let bottomMax=bottom.max() else { return nil }
        let hook=max(5,rail.height*0.025)
        let opensRight=topMax-x>hook && bottomMax-x>hook
        let opensLeft=x-topMin>hook && x-bottomMin>hook
        guard opensRight != opensLeft else { return nil }
        let bounds=indices.reduce(rail) { $0.union(strokes[$1].renderBounds) }
        return Bracket(indices:indices,bounds:bounds,opensRight:opensRight,axis:x)
    }

    /// Find shared columns, then align each column’s rows by order to tolerate sloped handwriting. Never fill empty cells.
    private static func grid(entries:Set<Int>,strokes:[PKStroke])->[[Data]]? {
        let bounds=entries.map { strokes[$0].renderBounds },height=typicalHeight(bounds)
        // Try successively narrower whitespace joins; prefer the finest rectangular grid.
        // Unequal row counts reject a split-off minus sign or digit column.
        let candidates:[[[[Int]]]]=[0.55,0.35,0.2,0.1,0].compactMap { factor in
            grid(entries:entries,strokes:strokes,height:height,columnGap:height*factor)
        }
        guard let best=candidates.max(by: { ($0.first?.count ?? 0)<($1.first?.count ?? 0) }) else { return nil }
        return best.map { row in row.map { indices in PKDrawing(strokes:indices.map { strokes[$0] }).dataRepresentation() } }
    }

    /// Reject inconsistent occupancy and vertical jumps before matching a column to its neighbors.
    private static func grid(entries:Set<Int>,strokes:[PKStroke],height:CGFloat,columnGap:CGFloat)->[[[Int]]]? {
        let bounds=entries.map { strokes[$0].renderBounds }
        let columns=bands(bounds.map { $0.minX...$0.maxX },gap:columnGap)
        guard (1...6).contains(columns.count) else { return nil }
        var columnCells:[[[Int]]]=[]
        var rowCount:Int?
        var previousCenters:[CGFloat]?
        for column in columns {
            let indices=entries.sorted().filter { column.contains(strokes[$0].renderBounds.midX) }
            let rows=bands(indices.map { strokes[$0].renderBounds.minY...strokes[$0].renderBounds.maxY },gap:height*0.35)
            guard (2...6).contains(rows.count),rowCount==nil || rowCount==rows.count else { return nil }
            let centers=rows.map { ($0.lowerBound+$0.upperBound)/2 }
            if let previousCenters,zip(previousCenters,centers).contains(where: { abs($0-$1)>height*1.2 }) { return nil }
            previousCenters=centers
            rowCount=rows.count
            var values:[[Int]]=[]
            for row in rows {
                let selected=indices.filter { row.contains(strokes[$0].renderBounds.midY) }
                guard !selected.isEmpty else { return nil }
                values.append(selected)
            }
            columnCells.append(values)
        }
        guard let rowCount else { return nil }
        // Match vertical order within each column: handwritten rows often slope across the page.
        var cells:[[[Int]]]=[]
        for row in 0..<rowCount { cells.append(columnCells.map { $0[row] }) }
        return cells
    }

    /// Ignore tiny dots/minus marks when choosing a scale for whitespace thresholds.
    private static func typicalHeight(_ bounds:[CGRect])->CGFloat {
        let heights=bounds.map(\.height).filter { $0>=8 }.sorted()
        return heights.isEmpty ? 16:heights[heights.count/2]
    }

    /// Merge projected ink intervals only across gaps smaller than the glyph-scale threshold.
    private static func bands(_ intervals:[ClosedRange<CGFloat>],gap:CGFloat)->[ClosedRange<CGFloat>] {
        var result:[ClosedRange<CGFloat>]=[]
        for interval in intervals.sorted(by: { $0.lowerBound<$1.lowerBound }) {
            if let last=result.last,interval.lowerBound-last.upperBound<=gap {
                result[result.count-1]=last.lowerBound...max(last.upperBound,interval.upperBound)
            } else { result.append(interval) }
        }
        return result
    }
}
