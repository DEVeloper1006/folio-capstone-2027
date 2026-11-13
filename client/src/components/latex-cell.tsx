/**
 * Render one editable LaTeX cell and its expression-command menu. Delegate MathLive lifecycle and local command sessions to their editor hooks.
 *
 * @file
 */

import { useExpressionCommands, useMathLive } from '#/editor/index.ts'
import { ExpressionCommandMenuView } from './expression-command-menu-view'

/** Supply the cell's identity, starting LaTeX, and notebook edit callback to the MathLive lifecycle hook. */
interface LatexCellProps {
  cellId: number
  initialLatex: string
  onLatexChange: (cellId: number, latex: string) => void
}

/** Connect the editor to notebook edits and render a local command menu only while its slash session is open. */
export function LatexCell({ cellId, initialLatex, onLatexChange }: LatexCellProps) {
  const commands = useExpressionCommands()
  const editorHostRef = useMathLive({
    cellId,
    initialLatex,
    onLatexChange,
    onEditorKeyDown: commands.handleEditorKeyDown,
  })

  return (
    <div className="cell-editor">
      <div className="cell-input" ref={editorHostRef} />
      {commands.isOpen && <ExpressionCommandMenuView menu={commands} />}
    </div>
  )
}
