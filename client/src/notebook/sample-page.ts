/**
 * Build the opening notebook page. Contains its title, the default display metadata, and one Markdown note followed by the sample math cells.
 *
 * @file
 */

import { sampleExpressions } from '#/editor/index.ts'
import type { MathNotebookCell, NotebookCell } from './notebook-cells.ts'
import { defaultPageMetadata } from './page.ts'
import type { Page } from './page.ts'

const openingNote = `## Make room for the reasoning

A notebook needs the **why** as well as the working. Use a text cell to state the problem, explain a step, or leave a question for later.

- Define your assumptions, such as $x \\in \\mathbb{R}$.
- Work through the calculation in a math cell below.
- Come back here to explain what the result means.`

/** Build a fixed UUID for a sample cell. The same index always returns the same identifier. */
function sampleCellId(cellIndex: number) {
  return `00000000-0000-4000-8000-${cellIndex.toString(16).padStart(12, '0')}`
}

/** Assign each sample expression a math cell after the opening note. */
function createSampleCell(sampleExpression: { latex: string }, cellIndex: number): MathNotebookCell {
  return { cellId: sampleCellId(cellIndex + 1), kind: 'math', latex: sampleExpression.latex }
}

/** Return the in-memory page shown on first load, with both cell kinds and the default display metadata. */
export function createSamplePage(): Page {
  const cells: NotebookCell[] = [{ cellId: sampleCellId(0), kind: 'markdown', markdown: openingNote }, ...sampleExpressions.map(createSampleCell)]
  return { pageId: 'playground', title: 'Notebook playground', cells, pageMetadata: defaultPageMetadata }
}

/** Starter practice pages with stable identities and an empty working cell after each question. */
export function createPracticePages(): Page[] {
  const topics = [
    { id: 'practice-calculus', title: 'Calculus 1 practice', questions: [String.raw`Find $\displaystyle\int 3x^2\,dx$.`, String.raw`Find $\displaystyle\int 2x(x^2+1)\,dx$.`, String.raw`Differentiate $f(x)=x^3-4x+2$.`] },
    {
      id: 'practice-linear-algebra',
      title: 'Linear Algebra 1 practice',
      questions: [String.raw`Solve the system $x+y=5$ and $2x-y=1$.`, String.raw`Compute $\begin{pmatrix}1&2\\0&3\end{pmatrix}\begin{pmatrix}2\\1\end{pmatrix}$.`, String.raw`Find the determinant of $\begin{pmatrix}3&1\\2&4\end{pmatrix}$.`],
    },
    {
      id: 'practice-discrete-math',
      title: 'Discrete Math practice',
      questions: [String.raw`Write the truth table for $p\land\neg q$.`, String.raw`Let $A=\{1,2,3\}$ and $B=\{2,3,4\}$. Find $A\cup B$ and $A\cap B$.`, String.raw`How many length-three binary strings contain exactly two ones? List them.`],
    },
    { id: 'practice-algebra', title: 'Algebra practice', questions: [String.raw`Solve $3x+7=22$.`, String.raw`Factor $x^2+5x+6$, then solve $x^2+5x+6=0$.`, String.raw`Simplify $\dfrac{x^2-9}{x-3}$ and state the restriction on $x$.`] },
  ]
  /** Build one page without solutions, leaving room to work through each problem. */
  function practicePage(topic: (typeof topics)[number], topicIndex: number): Page {
    /** Pair the question with an editable math cell. */
    function problemCells(question: string, index: number): NotebookCell[] {
      const prefix = `00000000-0000-4000-800${topicIndex + 1}-`
      return [
        { cellId: prefix + (2 * index).toString(16).padStart(12, '0'), kind: 'markdown', markdown: `### Problem ${index + 1}\n\n${question}` },
        { cellId: prefix + (2 * index + 1).toString(16).padStart(12, '0'), kind: 'math', latex: '' },
      ]
    }
    return { pageId: topic.id, title: topic.title, cells: topic.questions.flatMap(problemCells), pageMetadata: { ...defaultPageMetadata } }
  }
  return topics.map(practicePage)
}
