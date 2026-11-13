/**
 * Render the host for one editable LaTeX cell. Delegate MathLive initialization, change reporting, and cleanup to the editor hook.
 *
 * @file
 */

import { useMathLive } from '#/editor/use-mathlive'

/** Supply the cell's identity, starting LaTeX, and notebook edit callback to the MathLive lifecycle hook. */
interface LatexCellProps {
  cellId: number
  initialLatex: string
  onLatexChange: (cellId: number, latex: string) => void
}

/** Render a LaTeX cell and connect its editor to notebook change reporting. */
export function LatexCell({ cellId, initialLatex, onLatexChange }: LatexCellProps) {
  const editorHostRef = useMathLive({
    cellId,
    initialLatex,
    onLatexChange,
  })

  return <div className="cell-input" ref={editorHostRef} />
}
