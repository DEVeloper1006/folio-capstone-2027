/**
 * Render one editable LaTeX cell and its expression-command menu. Delegate MathLive lifecycle and local command sessions to their editor hooks.
 *
 * @file
 */

import { useMathLive } from '#/editor/use-mathlive'
import { useExpressionCommands } from '#/editor/use-expression-commands'
import { ExpressionCommandMenu } from './expression-command-menu'

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
      {commands.isOpen && <ExpressionCommandMenu menu={commands} />}
    </div>
  )
}
