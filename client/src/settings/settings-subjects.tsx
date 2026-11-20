/**
 * Edit custom subject guidance and notation templates with labeled fields. Preserve stable subject ids and reject stale drafts before the shared settings validator saves the library.
 *
 * @file
 */
import { useState } from 'react'
import type { ChangeEvent, FormEvent } from 'react'
import { Button, TextField } from '../component-library'
import type { MathMode, MathNotation } from '../math-help/math-modes'

/** Manage custom subjects without exposing the settings document format. */
export function SettingsSubjects({ modes, onSave }: { modes: MathMode[]; onSave: (modes: MathMode[]) => Promise<boolean> }) {
  const [draft, setDraft] = useState<MathMode>()
  const [base, setBase] = useState('')
  const [error, setError] = useState('')
  /** Start an empty subject with a stable id and one notation entry. */
  function add() {
    setBase(JSON.stringify(modes))
    setError('')
    setDraft({ id: `subject-${crypto.randomUUID()}`, title: '', summary: '', bindings: [{ key: '', label: '', latex: '' }] })
  }
  /** Discard only the unsubmitted subject form. */
  function cancel() {
    setDraft(undefined)
    setError('')
  }
  /** Update a subject's display name while retaining its identity. */
  function title(event: ChangeEvent<HTMLInputElement>) {
    if (draft) setDraft({ ...draft, title: event.target.value })
  }
  /** Update the subject guidance supplied with hint requests. */
  function summary(event: ChangeEvent<HTMLTextAreaElement>) {
    if (draft) setDraft({ ...draft, summary: event.target.value })
  }
  /** Add a blank notation entry up to the validator's limit. */
  function addNotation() {
    if (draft) setDraft({ ...draft, bindings: [...draft.bindings, { key: '', label: '', latex: '' }] })
  }
  /** Submit the entire subject through the existing notation and settings validators. */
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!draft) return
    const edited = draft
    if (base !== JSON.stringify(modes)) {
      setError('Subjects changed while you were editing. Cancel and reopen this subject before saving.')
      return
    }
    /** Replace only the edited subject, leaving the rest of the library intact. */
    function replace(mode: MathMode) {
      return mode.id === edited.id ? edited : mode
    }
    /** Locate an existing subject without matching its editable title. */
    function exists(mode: MathMode) {
      return mode.id === edited.id
    }
    if (await onSave(modes.some(exists) ? modes.map(replace) : [...modes, edited])) cancel()
  }
  /** Render one saved subject with editing and removal actions. */
  function subject(mode: MathMode) {
    /** Open the subject as a local draft rather than mutating saved preferences. */
    function edit() {
      setBase(JSON.stringify(modes))
      setError('')
      setDraft(structuredClone(mode))
    }
    /** Remove this subject only if the resulting settings remain valid. */
    function remove() {
      /** Retain every other custom subject. */
      function keep(item: MathMode) {
        return item.id !== mode.id
      }
      void onSave(modes.filter(keep))
    }
    return (
      <li key={mode.id}>
        <span>
          <strong>{mode.title}</strong>
          <small>{mode.summary}</small>
        </span>
        <Button variant="quiet" onClick={edit} aria-label={`Edit subject ${mode.title}`}>
          Edit
        </Button>
        <Button variant="quiet" onClick={remove} aria-label={`Remove subject ${mode.title}`}>
          Remove
        </Button>
      </li>
    )
  }
  /** Edit one notation without changing the order or identity of the others. */
  function notation(binding: MathNotation, index: number) {
    /** Apply a single notation field to the current draft. */
    function edit(event: ChangeEvent<HTMLInputElement>) {
      if (!draft) return
      const field = event.target.name
      if (field !== 'key' && field !== 'label' && field !== 'latex') return
      /** Replace the addressed entry with a copy containing the changed field. */
      function replace(item: MathNotation, position: number) {
        return position === index ? { ...item, [field]: event.target.value } : item
      }
      setDraft({ ...draft, bindings: draft.bindings.map(replace) })
    }
    /** Remove this entry while retaining at least one template. */
    function remove() {
      if (!draft) return
      /** Keep entries other than the selected row. */
      function keep(_item: MathNotation, position: number) {
        return position !== index
      }
      setDraft({ ...draft, bindings: draft.bindings.filter(keep) })
    }
    return (
      <div className="settings-notation" key={index}>
        <TextField label={`Notation ${index + 1} key`} name="key" maxLength={1} required pattern="[a-z]" value={binding.key} onChange={edit} />
        <TextField label={`Notation ${index + 1} name`} name="label" maxLength={80} required value={binding.label} onChange={edit} />
        <TextField label={`Notation ${index + 1} formula`} name="latex" maxLength={1200} required value={binding.latex} onChange={edit} spellCheck={false} />
        <Button variant="quiet" aria-label={`Remove notation ${index + 1}`} disabled={draft?.bindings.length === 1} onClick={remove}>
          Remove
        </Button>
      </div>
    )
  }
  return (
    <div className="settings-subjects">
      <h3>Custom subjects</h3>
      <p>Add subject guidance and notation for the math you work with.</p>
      {!draft && (
        <>
          <ul>{modes.map(subject)}</ul>
          <Button variant="quiet" disabled={modes.length >= 30} onClick={add}>
            Add subject
          </Button>
        </>
      )}
      {draft && (
        <form onSubmit={submit}>
          <TextField label="Subject name" maxLength={48} required value={draft.title} onChange={title} />
          <label className="settings-guidance">
            Hint guidance
            <textarea aria-label="Hint guidance" maxLength={300} required value={draft.summary} onChange={summary} />
          </label>
          <p>
            Notation uses a lowercase letter key and a LaTeX formula. Put <code>#1</code> where the expression belongs, such as <code>{'\\sqrt{#1}'}</code>.
          </p>
          {draft.bindings.map(notation)}
          <Button variant="quiet" disabled={draft.bindings.length >= 8} onClick={addNotation}>
            Add notation
          </Button>
          {error && <p role="alert">{error}</p>}
          <div className="settings-actions">
            <Button type="submit">Save subject</Button>
            <Button variant="quiet" onClick={cancel}>
              Cancel
            </Button>
          </div>
        </form>
      )}
    </div>
  )
}
