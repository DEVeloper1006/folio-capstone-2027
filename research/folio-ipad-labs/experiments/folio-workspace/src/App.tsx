import { useEffect, useRef, useState, type ReactNode } from 'react';
import {
  ArrowDown,
  ArrowRight,
  ArrowUp,
  BookOpen,
  Check,
  CheckCheck,
  ChevronDown,
  ChevronRight,
  CircleHelp,
  Command,
  Copy,
  Download,
  FilePlus2,
  FileText,
  GitBranch,
  GripVertical,
  Keyboard,
  Loader2,
  Menu,
  PanelLeftClose,
  PenLine,
  Plus,
  Printer,
  Redo2,
  Search,
  Settings2,
  ShieldCheck,
  Sigma,
  Sparkles,
  Trash2,
  Type,
  Undo2,
  Upload,
  X,
} from 'lucide-react';
import type { MathfieldElement } from 'mathlive';
import MathEditor, { mathJSON, MathPreview } from './MathEditor';
import AutoTextarea from './AutoTextarea';
import InkCanvas, { InkView } from './InkCanvas';
import {
  block,
  download,
  fileName,
  latexDocument,
  loadWorkspace,
  newDocument,
  parseImport,
  STORAGE_KEY,
  uid,
  type Block,
  type FolioDocument,
  type Workspace,
} from './model';

type Operation =
  | 'rowop'
  | 'rref'
  | 'matmul'
  | 'derivative'
  | 'integral'
  | 'simplify'
  | 'expand'
  | 'factor'
  | 'substitute'
  | 'check';
const COMMANDS: { id: Operation; name: string; description: string; glyph: string }[] = [
  {
    id: 'rref',
    name: 'Row reduce',
    description: 'Reduced row echelon form of a matrix',
    glyph: '[ ]',
  },
  {
    id: 'matmul',
    name: 'Multiply matrices',
    description: 'Multiply by a second compatible matrix',
    glyph: 'AB',
  },
  {
    id: 'derivative',
    name: 'Differentiate',
    description: 'Find a derivative with respect to a variable',
    glyph: 'd/dx',
  },
  {
    id: 'integral',
    name: 'Integrate',
    description: 'Find an indefinite integral, including C',
    glyph: '∫',
  },
  {
    id: 'simplify',
    name: 'Simplify',
    description: 'Find a simpler symbolic expression',
    glyph: '≡',
  },
  { id: 'expand', name: 'Expand', description: 'Expand products and powers', glyph: '( )' },
  { id: 'factor', name: 'Factor', description: 'Rewrite an expression as a product', glyph: '×' },
  {
    id: 'substitute',
    name: 'Substitute',
    description: 'Replace a variable with another expression',
    glyph: 'x→',
  },
  {
    id: 'check',
    name: 'Check equivalence',
    description: 'Compare two expressions symbolically',
    glyph: '=?',
  },
  {
    id: 'rowop',
    name: 'Matrix row operation',
    description: 'Swap, scale, or add a multiple of a row',
    glyph: 'Rᵢ',
  },
];
type Result = { latex?: string; note: string; equivalent?: boolean };
type ModalName =
  'palette' | 'export' | 'settings' | 'help' | 'command' | 'recognize' | 'assist' | 'delete' | null;
async function api<T>(path: string, data?: unknown): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 60000);
  try {
    const response = await fetch('/api/' + path, {
      method: data ? 'POST' : 'GET',
      headers: data ? { 'Content-Type': 'application/json' } : undefined,
      body: data ? JSON.stringify(data) : undefined,
      signal: controller.signal,
    });
    let body;
    try {
      body = await response.json();
    } catch {
      throw new Error('The local math server is unavailable. Start it with npm run dev.');
    }
    if (!response.ok)
      throw new Error(
        typeof body.detail === 'string'
          ? body.detail
          : 'The request could not be completed. Check your input and retry.',
      );
    return body;
  } catch (e) {
    if (e instanceof TypeError)
      throw new Error('Cannot reach the local server. Your document has not been changed.');
    throw e;
  } finally {
    clearTimeout(timer);
  }
}
function Modal({
  title,
  children,
  onClose,
  wide = false,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
  wide?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current!;
    d.showModal();
    return () => d.close();
  }, []);
  return (
    <dialog
      ref={ref}
      className={`modal ${wide ? 'modal-wide' : ''}`}
      onCancel={onClose}
      onClick={(e) => {
        if (e.target === ref.current) onClose();
      }}
      aria-label={title}
    >
      <div className="modal-heading">
        <h2>{title}</h2>
        <button className="icon-button" onClick={onClose} aria-label="Close dialog">
          <X size={19} />
        </button>
      </div>
      {children}
    </dialog>
  );
}
function DocumentView({ doc }: { doc: FolioDocument }) {
  return (
    <article className="document-output">
      <div className="output-subject">{doc.subject}</div>
      <h1>{doc.title}</h1>
      {doc.blocks
        .filter((b) => b.included)
        .map((b) => (
          <div key={b.id} className={`output-block output-${b.type}`}>
            {b.type === 'heading' ? (
              <h2>{b.content}</h2>
            ) : b.type === 'text' ? (
              <p>{b.content}</p>
            ) : b.type === 'math' ? (
              <>
                <MathPreview latex={b.content} />
                {b.note && <p className="output-note">{b.note}</p>}
              </>
            ) : (
              <InkView strokes={b.strokes || []} />
            )}
          </div>
        ))}
    </article>
  );
}
export default function App() {
  const [loaded] = useState(loadWorkspace);
  const [workspace, setWorkspace] = useState<Workspace>(loaded.workspace);
  const current = useRef(workspace);
  current.current = workspace;
  const [storageWarning, setStorageWarning] = useState(loaded.warning || '');
  const storagePaused = useRef(!!loaded.warning);
  const [saveState, setSaveState] = useState(
    loaded.warning ? 'Saving paused' : 'Saved on this device',
  );
  const [selectedId, setSelectedId] = useState<string | null>(
    () =>
      loaded.workspace.documents[0].blocks.find((b) => b.note === 'Augmented matrix')?.id || null,
  );
  const [modal, setModal] = useState<ModalName>(null);
  const [sidebar, setSidebar] = useState(false);
  const [panelTab, setPanelTab] = useState<'commands' | 'outline'>('commands');
  const [search, setSearch] = useState('');
  const [paletteSearch, setPaletteSearch] = useState('');
  const [toast, setToast] = useState('');
  const [health, setHealth] = useState<{ engine: string; ai: boolean; model: string } | null>(null);
  const [showLatex, setShowLatex] = useState(false);
  const [op, setOp] = useState<Operation>('simplify');
  const [variable, setVariable] = useState('x');
  const [rowAction, setRowAction] = useState('add');
  const [rowFrom, setRowFrom] = useState(1);
  const [rowTo, setRowTo] = useState(2);
  const [other, setOther] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState('');
  const [inkImage, setInkImage] = useState('');
  const [recognized, setRecognized] = useState('');
  const [recognitionNote, setRecognitionNote] = useState('');
  const [question, setQuestion] = useState('Check this step and explain any mistakes.');
  const [feedback, setFeedback] = useState('');
  const [consent, setConsent] = useState(false);
  const requestId = useRef(0);
  const history = useRef<{ past: Workspace[]; future: Workspace[]; group: string; time: number }>({
    past: [],
    future: [],
    group: '',
    time: 0,
  });
  const importInput = useRef<HTMLInputElement>(null);
  const doc =
    workspace.documents.find((d) => d.id === workspace.activeId) || workspace.documents[0];
  const selected = doc.blocks.find((b) => b.id === selectedId);
  const selectedIndex = doc.blocks.findIndex((b) => b.id === selectedId);
  const mathCount = doc.blocks.filter((b) => b.type === 'math').length;
  const command = COMMANDS.find((c) => c.id === op)!;
  const target = useRef<{ docId: string; blockId: string; content: string }>({
    docId: doc.id,
    blockId: '',
    content: '',
  });
  function change(fn: (w: Workspace) => Workspace, group = '') {
    const before = current.current;
    const next = fn(before);
    if (next === before) return;
    const h = history.current;
    if (!group || h.group !== group || Date.now() - h.time > 800) {
      h.past.push(before);
      if (h.past.length > 80) h.past.shift();
    }
    h.future = [];
    h.group = group;
    h.time = Date.now();
    current.current = next;
    setWorkspace(next);
  }
  function updateDoc(fn: (d: FolioDocument) => FolioDocument, group = '', docId = doc.id) {
    change(
      (w) => ({
        ...w,
        documents: w.documents.map((d) =>
          d.id === docId ? { ...fn(d), updatedAt: new Date().toISOString() } : d,
        ),
      }),
      group,
    );
  }
  function updateBlock(id: string, patch: Partial<Block>, group = '') {
    updateDoc(
      (d) => ({ ...d, blocks: d.blocks.map((b) => (b.id === id ? { ...b, ...patch } : b)) }),
      group,
    );
  }
  function undo(redo = false) {
    const h = history.current;
    const source = redo ? h.future : h.past;
    const next = source.pop();
    if (!next) return;
    (redo ? h.past : h.future).push(current.current);
    h.group = '';
    current.current = next;
    setWorkspace(next);
    setToast(redo ? 'Change restored' : 'Change undone');
  }
  function selectDocument(id: string) {
    change((w) => ({ ...w, activeId: id }));
    setSelectedId(null);
    setSidebar(false);
    setShowLatex(false);
  }
  function addDocument() {
    if (current.current.documents.length >= 100) {
      setToast('This workspace has 100 documents. Back up and remove a document first.');
      return;
    }
    const d = newDocument();
    change((w) => ({ ...w, documents: [...w.documents, d], activeId: d.id }));
    setSelectedId(d.blocks[0].id);
    setSidebar(false);
    setModal(null);
    setTimeout(() => document.querySelector<HTMLTextAreaElement>('.document-title')?.select(), 50);
  }
  function addBlock(type: Block['type'], content = '', after = selectedId) {
    if (doc.blocks.length >= 500) {
      setToast('This document has 500 steps. Start another document to continue.');
      return null;
    }
    const b = block(type, content);
    updateDoc((d) => {
      const index = d.blocks.findIndex((x) => x.id === after);
      const blocks = [...d.blocks];
      blocks.splice(index < 0 ? blocks.length : index + 1, 0, b);
      return { ...d, blocks };
    });
    setSelectedId(b.id);
    setTimeout(() => {
      const row = document.querySelector<HTMLElement>(`[data-block-id="${b.id}"]`);
      row?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      row?.querySelector<HTMLElement>('math-field,textarea,input')?.focus();
    }, 50);
    return b.id;
  }
  function duplicateBlock() {
    if (!selected) return;
    if (doc.blocks.length >= 500) {
      setToast('This document has reached its 500-step limit.');
      return;
    }
    const b = { ...structuredClone(selected), id: uid() };
    updateDoc((d) => {
      const blocks = [...d.blocks];
      blocks.splice(selectedIndex + 1, 0, b);
      return { ...d, blocks };
    });
    setSelectedId(b.id);
    setToast('Independent copy added');
  }
  function moveBlock(id: string, direction: number) {
    updateDoc((d) => {
      const index = d.blocks.findIndex((b) => b.id === id);
      if (index + direction < 0 || index + direction >= d.blocks.length) return d;
      const blocks = [...d.blocks];
      [blocks[index], blocks[index + direction]] = [blocks[index + direction], blocks[index]];
      return { ...d, blocks };
    });
  }
  function forkDocument() {
    if (current.current.documents.length >= 100) {
      setToast('This workspace has reached its 100-document limit.');
      return;
    }
    const d = {
      ...structuredClone(doc),
      id: uid(),
      title: doc.title.slice(0, 185) + ' (alternative)',
      blocks: doc.blocks.map((b) => ({ ...structuredClone(b), id: uid() })),
      updatedAt: new Date().toISOString(),
    };
    change((w) => ({ ...w, documents: [...w.documents, d], activeId: d.id }));
    setSelectedId(null);
    setToast('Alternative copy created. The original is unchanged.');
  }
  function closeModal() {
    requestId.current++;
    setModal(null);
    setBusy(false);
    setError('');
    setConsent(false);
  }
  function openModal(name: ModalName) {
    requestId.current++;
    setError('');
    setBusy(false);
    setConsent(false);
    setModal(name);
  }
  function openCommand(id: Operation) {
    if (selected?.type !== 'math') {
      setToast('Select a math expression first');
      setModal(null);
      return;
    }
    target.current = { docId: doc.id, blockId: selected.id, content: selected.content };
    setOp(id);
    setOther(id === 'rowop' ? '1' : '');
    setResult(null);
    setVariable('x');
    setRowAction('add');
    setRowFrom(1);
    setRowTo(2);
    openModal('command');
  }
  function invalidateResult() {
    requestId.current++;
    setResult(null);
    setBusy(false);
  }
  async function runCommand() {
    if (busy) return;
    setBusy(true);
    setError('');
    setResult(null);
    const token = ++requestId.current;
    try {
      const data = await api<Result>('compute', {
        operation: op,
        expression: await mathJSON(target.current.content),
        variable,
        row_action: rowAction,
        row_from: rowFrom,
        row_to: rowTo,
        other:
          ['matmul', 'substitute', 'check'].includes(op) || (op === 'rowop' && rowAction !== 'swap')
            ? await mathJSON(other)
            : null,
      });
      if (token === requestId.current) setResult(data);
    } catch (e) {
      if (token === requestId.current) setError((e as Error).message);
    } finally {
      if (token === requestId.current) setBusy(false);
    }
  }
  function insertTarget(content: string, type: Block['type'] = 'math', note?: string) {
    const t = target.current;
    const b = block(type, content, note);
    const targetDoc = current.current.documents.find((d) => d.id === t.docId);
    if (!targetDoc?.blocks.some((b) => b.id === t.blockId)) {
      setError('The source step no longer exists. Copy the result before closing.');
      return;
    }
    if (targetDoc.blocks.length >= 500) {
      setError('This document has reached its 500-step limit.');
      return;
    }
    updateDoc(
      (d) => {
        const blocks = [...d.blocks];
        blocks.splice(blocks.findIndex((x) => x.id === t.blockId) + 1, 0, b);
        return { ...d, blocks };
      },
      '',
      t.docId,
    );
    setSelectedId(b.id);
    closeModal();
    setToast('Added as a new step. Original preserved.');
  }
  function beginRecognize(image: string, b: Block) {
    target.current = { docId: doc.id, blockId: b.id, content: b.content };
    setInkImage(image);
    setRecognized('');
    setRecognitionNote('');
    openModal('recognize');
  }
  async function recognize() {
    setBusy(true);
    setError('');
    const token = ++requestId.current;
    try {
      const r = await api<{ latex: string; note: string }>('recognize', { image: inkImage });
      if (token === requestId.current) {
        setRecognized(r.latex);
        setRecognitionNote(r.note);
      }
    } catch (e) {
      if (token === requestId.current) setError((e as Error).message);
    } finally {
      if (token === requestId.current) setBusy(false);
    }
  }
  function beginAssist() {
    if (!selected) {
      setToast('Select a step to discuss');
      return;
    }
    if (selected.type === 'ink') {
      setToast('Convert your handwriting before requesting a math check');
      return;
    }
    target.current = { docId: doc.id, blockId: selected.id, content: selected.content };
    setFeedback('');
    openModal('assist');
  }
  async function assist() {
    setBusy(true);
    setError('');
    const token = ++requestId.current;
    try {
      const r = await api<{ text: string }>('assist', {
        context: target.current.content,
        question,
      });
      if (token === requestId.current) setFeedback(r.text);
    } catch (e) {
      if (token === requestId.current) setError((e as Error).message);
    } finally {
      if (token === requestId.current) setBusy(false);
    }
  }
  function insertTemplate(latex: string) {
    const mf = document.querySelector<MathfieldElement>(
      `[data-block-id="${selectedId}"] math-field`,
    );
    if (mf) {
      mf.focus();
      mf.insert(latex);
    } else {
      const id = addBlock('math');
      setTimeout(() => {
        const field = document.querySelector<MathfieldElement>(
          `[data-block-id="${id}"] math-field`,
        );
        field?.focus();
        field?.insert(latex);
      }, 80);
    }
  }
  async function importFile(file?: File) {
    if (!file) return;
    try {
      if (current.current.documents.length >= 100)
        throw new Error('This workspace has reached its 100-document limit.');
      if (file.size > 5_000_000) throw new Error('Documents must be smaller than 5 MB.');
      const d = parseImport(await file.text());
      change((w) => ({ ...w, documents: [...w.documents, d], activeId: d.id }));
      setSelectedId(null);
      setToast('Document imported as a new copy');
    } catch (e) {
      setToast((e as Error).message);
    }
    if (importInput.current) importInput.current.value = '';
  }
  function saveFile() {
    download(
      JSON.stringify({ version: 1, document: doc }, null, 2),
      fileName(doc.title) + '.folio',
      'application/json',
    );
  }
  useEffect(() => {
    document.title = doc.title + ' | Folio';
  }, [doc.title]);
  useEffect(() => {
    api<typeof health>('health')
      .then(setHealth)
      .catch(() => setHealth(null));
  }, []);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(''), 5000);
    return () => clearTimeout(t);
  }, [toast]);
  useEffect(() => {
    if (storagePaused.current) return;
    setSaveState('Saving...');
    const save = () => {
      if (storagePaused.current) return;
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(current.current));
        setSaveState('Saved on this device');
      } catch {
        setSaveState('Not saved');
        setStorageWarning(
          'Browser storage is full or unavailable. Download your .folio file to keep this work.',
        );
      }
    };
    const timer = setTimeout(save, 350);
    window.addEventListener('beforeunload', save);
    return () => {
      clearTimeout(timer);
      window.removeEventListener('beforeunload', save);
    };
  }, [workspace]);
  useEffect(() => {
    const listener = (e: StorageEvent) => {
      if (e.key === STORAGE_KEY) {
        storagePaused.current = true;
        setSaveState('Saving paused');
        setStorageWarning(
          'Folio changed in another tab. Download this copy, then reload to use the other tab’s version.',
        );
      }
    };
    window.addEventListener('storage', listener);
    return () => window.removeEventListener('storage', listener);
  }, []);
  useEffect(() => {
    const listener = (e: KeyboardEvent) => {
      const cmd = e.metaKey || e.ctrlKey;
      if (cmd && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        if (modal) closeModal();
        else {
          setPaletteSearch('');
          openModal('palette');
        }
      }
      if (modal) return;
      if (cmd && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        e.stopPropagation();
        undo(e.shiftKey);
      }
      if (cmd && e.key.toLowerCase() === 'd' && e.shiftKey) {
        e.preventDefault();
        duplicateBlock();
      }
      if (cmd && e.key.toLowerCase() === 's') {
        e.preventDefault();
        saveFile();
      }
      if (cmd && e.key.toLowerCase() === 'p') {
        e.preventDefault();
        openModal('export');
      }
    };
    window.addEventListener('keydown', listener, true);
    return () => window.removeEventListener('keydown', listener, true);
  });
  const excluded = doc.blocks.filter((b) => !b.included).length;
  return (
    <>
      <div className="app-shell">
        {sidebar && (
          <button
            className="sidebar-scrim"
            aria-label="Close navigation"
            onClick={() => setSidebar(false)}
          />
        )}
        <aside className={`sidebar ${sidebar ? 'sidebar-open' : ''}`}>
          <div className="brand">
            <span className="brand-mark">f</span>
            <span>folio</span>
            <button
              className="icon-button mobile-only"
              aria-label="Close sidebar"
              onClick={() => setSidebar(false)}
            >
              <PanelLeftClose size={18} />
            </button>
          </div>
          <button className="workspace-switch" onClick={() => openModal('settings')}>
            <span className="workspace-avatar">M</span>
            <span>
              My workspace<small>Personal, on this device</small>
            </span>
            <ChevronDown size={14} />
          </button>
          <button
            className="sidebar-command"
            onClick={() => {
              setPaletteSearch('');
              openModal('palette');
            }}
          >
            <Search size={16} />
            <span>Find a command</span>
            <kbd>⌘ K</kbd>
          </button>
          <div className="sidebar-section-heading">
            <span>My documents</span>
            <button
              className="icon-button"
              aria-label="New document"
              title="New document"
              onClick={addDocument}
            >
              <Plus size={16} />
            </button>
          </div>
          <div className="document-search">
            <Search size={13} />
            <input
              aria-label="Search documents"
              placeholder="Filter documents..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          <nav className="document-list" aria-label="Documents">
            {workspace.documents
              .filter((d) =>
                (d.title + ' ' + d.subject).toLowerCase().includes(search.toLowerCase()),
              )
              .map((d) => (
                <button
                  key={d.id}
                  className={`document-link ${d.id === doc.id ? 'is-active' : ''}`}
                  onClick={() => selectDocument(d.id)}
                  title={d.title}
                >
                  <FileText size={17} />
                  <span>{d.title}</span>
                  {d.id === doc.id && <span className="active-dot" />}
                </button>
              ))}
            {!workspace.documents.some((d) =>
              (d.title + ' ' + d.subject).toLowerCase().includes(search.toLowerCase()),
            ) && <p className="sidebar-empty">No matching documents.</p>}
          </nav>
          <button className="sidebar-action" onClick={addDocument}>
            <FilePlus2 size={16} /> New document
          </button>
          <button className="sidebar-action" onClick={() => importInput.current?.click()}>
            <Upload size={16} /> Open .folio file
          </button>
          <input
            ref={importInput}
            hidden
            type="file"
            accept=".folio,.json"
            onChange={(e) => importFile(e.target.files?.[0])}
          />
          <div className="sidebar-bottom">
            <div className="local-note">
              <ShieldCheck size={18} />
              <div>
                Your work stays yours.
                <p>
                  Saved in this browser.
                  <br />
                  No account required.
                </p>
              </div>
            </div>
            <button className="sidebar-action" onClick={() => openModal('help')}>
              <CircleHelp size={16} /> A quick introduction <span className="spacer" />
              <kbd>?</kbd>
            </button>
            <button className="sidebar-action" onClick={() => openModal('settings')}>
              <Settings2 size={16} /> Settings & connections
            </button>
          </div>
        </aside>
        <div className="workspace-main">
          <header className="topbar">
            <button
              className="icon-button mobile-only"
              onClick={() => setSidebar(true)}
              aria-label="Open navigation"
            >
              <Menu size={20} />
            </button>
            <div className="breadcrumbs">
              <span>My documents</span>
              <ChevronRight size={14} />
              <strong>{doc.title}</strong>
            </div>
            <div className="spacer" />
            <span className={`save-status ${saveState === 'Not saved' ? 'save-error' : ''}`}>
              <CheckCheck size={15} />
              {saveState}
            </span>
            <button className="button export-button" onClick={() => openModal('export')}>
              <Download size={15} />
              <span>Export</span>
              <ChevronDown size={13} />
            </button>
          </header>
          <div className="editor-toolbar">
            <div className="toolbar-group">
              <button
                className="icon-button"
                aria-label="Undo"
                title="Undo (Cmd Z)"
                disabled={!history.current.past.length}
                onClick={() => undo()}
              >
                <Undo2 size={17} />
              </button>
              <button
                className="icon-button"
                aria-label="Redo"
                title="Redo (Cmd Shift Z)"
                disabled={!history.current.future.length}
                onClick={() => undo(true)}
              >
                <Redo2 size={17} />
              </button>
            </div>
            <span className="toolbar-divider" />
            <button className="toolbar-button" onClick={() => addBlock('math')}>
              <Sigma size={17} />
              <span>Math</span>
            </button>
            <button className="toolbar-button" onClick={() => addBlock('text')}>
              <Type size={17} />
              <span>Text</span>
            </button>
            <button className="toolbar-button" onClick={() => addBlock('ink')}>
              <PenLine size={17} />
              <span>Ink</span>
            </button>
            <span className="toolbar-divider" />
            <div className="math-shortcuts">
              <button
                title="Insert fraction"
                aria-label="Insert fraction"
                onClick={() => insertTemplate('\\frac{#0}{#?}')}
              >
                <span>ᵃ⁄ᵦ</span>
              </button>
              <button
                title="Insert exponent"
                aria-label="Insert exponent"
                onClick={() => insertTemplate('#0^{#?}')}
              >
                <span>x²</span>
              </button>
              <button
                title="Insert square root"
                aria-label="Insert square root"
                onClick={() => insertTemplate('\\sqrt{#0}')}
              >
                <span>√</span>
              </button>
              <button
                title="Insert 2 by 2 matrix"
                aria-label="Insert matrix"
                onClick={() => insertTemplate('\\begin{bmatrix}1 & 0 \\\\ 0 & 1\\end{bmatrix}')}
              >
                <span>[▦]</span>
              </button>
            </div>
            <div className="spacer" />
            <button
              className="toolbar-button command-trigger"
              aria-label="Commands"
              title="Math commands"
              onClick={() => {
                setPaletteSearch('');
                openModal('palette');
              }}
            >
              <Command size={15} />
              <span>Commands</span>
              <kbd>⌘ K</kbd>
            </button>
          </div>
          {storageWarning && (
            <div className="storage-warning" role="alert">
              <span>{storageWarning}</span>
              <button onClick={saveFile}>Download this document</button>
              {loaded.warning && (
                <button
                  onClick={() =>
                    download(
                      localStorage.getItem(STORAGE_KEY) || '',
                      'folio-storage-backup.json',
                      'application/json',
                    )
                  }
                >
                  Back up saved data
                </button>
              )}
            </div>
          )}
          <div className="editor-layout">
            <main className="editor-scroll" id="editor-scroll">
              <div className="page-context">
                <BookOpen size={14} />
                <span>A space to work things out</span>
                <button
                  className="icon-button"
                  title="Create alternative document"
                  aria-label="Create alternative document"
                  onClick={forkDocument}
                >
                  <GitBranch size={15} />
                </button>
              </div>
              <article className="document-paper">
                <div className="document-heading">
                  <input
                    className="document-subject"
                    aria-label="Document subject"
                    value={doc.subject}
                    maxLength={100}
                    onChange={(e) =>
                      updateDoc((d) => ({ ...d, subject: e.target.value }), 'subject')
                    }
                  />
                  <AutoTextarea
                    className="document-title"
                    rows={1}
                    aria-label="Document title"
                    value={doc.title}
                    maxLength={200}
                    onChange={(e) =>
                      updateDoc(
                        (d) => ({ ...d, title: e.target.value.replace(/\n/g, ' ') }),
                        'title',
                      )
                    }
                  />
                  <div className="document-meta">
                    <span>{doc.blocks.length} steps</span>
                    <span>{mathCount} expressions</span>
                    <span>Private document</span>
                  </div>
                </div>
                <div className="document-blocks">
                  {doc.blocks.map((b, index) => (
                    <section
                      key={b.id}
                      data-block-id={b.id}
                      className={`editor-block block-${b.type} ${selectedId === b.id ? 'is-selected' : ''} ${!b.included ? 'is-excluded' : ''}`}
                      onClick={() => setSelectedId(b.id)}
                    >
                      <button
                        className="block-handle"
                        aria-label={`Select step ${index + 1}`}
                        title={`Step ${index + 1}`}
                        onClick={() => setSelectedId(b.id)}
                      >
                        <span>{String(index + 1).padStart(2, '0')}</span>
                        <GripVertical size={15} />
                      </button>
                      <div className="block-body">
                        {b.type === 'math' ? (
                          <>
                            <MathEditor
                              value={b.content}
                              label={`Math step ${index + 1}`}
                              onChange={(v) =>
                                updateBlock(b.id, { content: v, note: undefined }, b.id)
                              }
                              onFocus={() => setSelectedId(b.id)}
                              onNext={() => addBlock('math', '', b.id)}
                              onCommands={() => {
                                setPaletteSearch('');
                                openModal('palette');
                              }}
                            />
                            {b.note && <div className="block-note">{b.note}</div>}
                            {showLatex && selectedId === b.id && (
                              <div className="latex-source">
                                <label>
                                  LaTeX source
                                  <textarea
                                    value={b.content}
                                    spellCheck={false}
                                    onChange={(e) =>
                                      updateBlock(
                                        b.id,
                                        { content: e.target.value, note: undefined },
                                        b.id,
                                      )
                                    }
                                  />
                                </label>
                              </div>
                            )}
                          </>
                        ) : b.type === 'ink' ? (
                          <InkCanvas
                            strokes={b.strokes || []}
                            onChange={(strokes) => {
                              if (
                                strokes.length > 2000 ||
                                strokes.some((s) => s.points.length > 20000) ||
                                strokes.reduce((n, s) => n + s.points.length, 0) > 100000
                              ) {
                                setToast('This canvas is full. Add another ink step to continue.');
                                return;
                              }
                              updateBlock(b.id, { strokes });
                            }}
                            onRecognize={(image) => beginRecognize(image, b)}
                          />
                        ) : (
                          <AutoTextarea
                            className={`text-editor ${b.type === 'heading' ? 'is-heading' : ''}`}
                            aria-label={`${b.type === 'heading' ? 'Heading' : 'Text'} step ${index + 1}`}
                            placeholder={
                              b.type === 'heading'
                                ? 'A new idea'
                                : 'Add an explanation, a question, a little context...'
                            }
                            rows={1}
                            maxLength={20000}
                            value={b.content}
                            onFocus={() => setSelectedId(b.id)}
                            onChange={(e) => {
                              updateBlock(b.id, { content: e.target.value }, b.id);
                            }}
                          />
                        )}
                      </div>
                      <button
                        className={`include-toggle ${b.included ? 'is-included' : ''}`}
                        aria-label={`${b.included ? 'Exclude' : 'Include'} step ${index + 1} ${b.included ? 'from' : 'in'} export`}
                        title={b.included ? 'Included in export' : 'Excluded from export'}
                        onClick={(e) => {
                          e.stopPropagation();
                          updateBlock(b.id, { included: !b.included });
                        }}
                      >
                        {b.included ? <Check size={12} /> : <span />}
                      </button>
                      {selectedId === b.id && (
                        <div className="block-actions">
                          <button
                            title="Move step up"
                            aria-label="Move step up"
                            disabled={index === 0}
                            onClick={() => moveBlock(b.id, -1)}
                          >
                            <ArrowUp size={13} />
                          </button>
                          <button
                            title="Move step down"
                            aria-label="Move step down"
                            disabled={index === doc.blocks.length - 1}
                            onClick={() => moveBlock(b.id, 1)}
                          >
                            <ArrowDown size={13} />
                          </button>
                          <span />
                          <button
                            title="Duplicate step"
                            aria-label="Duplicate step"
                            onClick={duplicateBlock}
                          >
                            <Copy size={13} />
                          </button>
                          <button
                            title="Delete step"
                            aria-label="Delete step"
                            onClick={() => {
                              updateDoc((d) => ({
                                ...d,
                                blocks: d.blocks.filter((x) => x.id !== b.id),
                              }));
                              setSelectedId(null);
                              setToast('Step removed. Undo to restore it.');
                            }}
                          >
                            <Trash2 size={13} />
                          </button>
                        </div>
                      )}
                    </section>
                  ))}
                </div>
                <div className="add-step">
                  <button onClick={() => addBlock('math', '', doc.blocks.at(-1)?.id || null)}>
                    <Plus size={16} />
                    <span>Continue your thinking</span>
                  </button>
                  <span>Math, words, or a little of both.</span>
                </div>
              </article>
              <div className="page-footer">
                <span>Nothing is final. Keep exploring.</span>
                <button onClick={() => openModal('help')}>
                  <Keyboard size={14} /> Keyboard shortcuts
                </button>
              </div>
            </main>
            <aside className="inspector">
              <div className="inspector-tabs">
                <button
                  className={panelTab === 'commands' ? 'is-active' : ''}
                  onClick={() => setPanelTab('commands')}
                >
                  Math tools
                </button>
                <button
                  className={panelTab === 'outline' ? 'is-active' : ''}
                  onClick={() => setPanelTab('outline')}
                >
                  Outline
                </button>
              </div>
              {panelTab === 'commands' ? (
                <>
                  <div className="inspector-section">
                    <div className="inspector-label">
                      {selected
                        ? `Selected step ${String(selectedIndex + 1).padStart(2, '0')}`
                        : 'Your next step'}
                    </div>
                    {selected?.type === 'math' ? (
                      <>
                        <div className="selection-preview">
                          <MathPreview latex={selected.content} />
                        </div>
                        <div className="selection-controls">
                          <span>
                            <span className="status-dot" /> Editable math
                          </span>
                          <button onClick={() => setShowLatex((v) => !v)}>
                            {showLatex ? 'Hide' : 'View'} LaTeX
                          </button>
                        </div>
                      </>
                    ) : (
                      <p className="inspector-description">
                        {selected?.type === 'ink'
                          ? 'Write an expression, then select a region to convert it into editable math.'
                          : 'Select an expression to transform it. Your original work always stays intact.'}
                      </p>
                    )}
                  </div>
                  <div className="inspector-section command-section">
                    <div className="inspector-label">Transform</div>
                    <div className="command-list">
                      {COMMANDS.slice(0, 7).map((c) => (
                        <button
                          key={c.id}
                          disabled={selected?.type !== 'math'}
                          onClick={() => openCommand(c.id)}
                        >
                          <span className="command-glyph">{c.glyph}</span>
                          <span>
                            {c.name}
                            <small>/{c.id}</small>
                          </span>
                          <ChevronRight size={13} />
                        </button>
                      ))}
                    </div>
                    <button
                      className="all-commands"
                      onClick={() => {
                        setPaletteSearch('');
                        openModal('palette');
                      }}
                    >
                      All commands <ArrowRight size={13} />
                    </button>
                  </div>
                  <div className="inspector-section">
                    <button className="ai-action" onClick={beginAssist}>
                      <Sparkles size={17} />
                      <span>
                        A second pair of eyes<small>Check a step or ask for a hint</small>
                      </span>
                      <ChevronRight size={14} />
                    </button>
                  </div>
                  <div className="inspector-bottom">
                    <ShieldCheck size={15} />
                    <p>
                      Computed, not guessed.
                      <br />
                      <span>Symbolic operations run locally with SymPy.</span>
                    </p>
                  </div>
                </>
              ) : (
                <div className="outline-list">
                  <p className="inspector-description">
                    Your steps, in order. Checkmarks control what appears in the exported document.
                  </p>
                  {doc.blocks.map((b, i) => (
                    <button
                      key={b.id}
                      className={selectedId === b.id ? 'is-active' : ''}
                      onClick={() => {
                        setSelectedId(b.id);
                        document
                          .querySelector(`[data-block-id="${b.id}"]`)
                          ?.scrollIntoView({ block: 'center', behavior: 'smooth' });
                      }}
                    >
                      <span>{String(i + 1).padStart(2, '0')}</span>
                      <span>
                        {b.type === 'math' ? (
                          <MathPreview latex={b.content} display={false} />
                        ) : b.type === 'ink' ? (
                          'Handwritten work'
                        ) : (
                          b.content || 'Empty step'
                        )}
                      </span>
                      {b.included && <Check size={12} />}
                    </button>
                  ))}
                </div>
              )}
            </aside>
          </div>
          <footer className="statusbar">
            <span>
              <span className="status-dot" />
              {health ? 'Local math engine ready' : 'Editor ready; math server offline'}
            </span>
            <span className="statusbar-hint">Select. Transform. Keep going.</span>
            <span>
              {excluded ? `${excluded} steps excluded from export` : 'All steps included in export'}
            </span>
          </footer>
        </div>
      </div>
      <div className="print-document">
        <DocumentView doc={doc} />
      </div>
      {toast && (
        <div className="toast" role="status">
          <Check size={16} />
          {toast}
          <button aria-label="Dismiss notification" onClick={() => setToast('')}>
            <X size={14} />
          </button>
        </div>
      )}
      {modal === 'palette' && (
        <Modal title="What would you like to do?" onClose={closeModal}>
          <div className="palette-search">
            <Search size={18} />
            <input
              autoFocus
              aria-label="Search commands"
              placeholder="Search commands, or type /derivative..."
              value={paletteSearch}
              onChange={(e) => setPaletteSearch(e.target.value)}
            />
            <kbd>esc</kbd>
          </div>
          <div className="palette-list">
            {COMMANDS.filter((c) =>
              (c.id + ' ' + c.name + ' ' + c.description)
                .toLowerCase()
                .includes(paletteSearch.toLowerCase().replace(/^\//, '')),
            ).map((c) => (
              <button
                key={c.id}
                onClick={() => openCommand(c.id)}
                disabled={selected?.type !== 'math'}
              >
                <span className="command-glyph">{c.glyph}</span>
                <span>
                  <strong>{c.name}</strong>
                  <small>{c.description}</small>
                </span>
                <code>/{c.id}</code>
              </button>
            ))}
            {!paletteSearch && (
              <>
                <div className="palette-divider">Create</div>
                <button
                  onClick={() => {
                    closeModal();
                    addBlock('math');
                  }}
                >
                  <Sigma size={18} />
                  <span>Math expression</span>
                  <Plus size={15} />
                </button>
                <button
                  onClick={() => {
                    closeModal();
                    addBlock('text');
                  }}
                >
                  <Type size={18} />
                  <span>Explanatory text</span>
                  <Plus size={15} />
                </button>
                <button
                  onClick={() => {
                    closeModal();
                    addBlock('heading');
                  }}
                >
                  <Type size={18} />
                  <span>Section heading</span>
                  <Plus size={15} />
                </button>
                <button
                  onClick={() => {
                    closeModal();
                    addBlock('ink');
                  }}
                >
                  <PenLine size={18} />
                  <span>Handwriting canvas</span>
                  <Plus size={15} />
                </button>
              </>
            )}
          </div>
          <div className="modal-footnote">
            {selected?.type === 'math'
              ? 'Commands act on the selected expression.'
              : 'Select a math expression to enable symbolic commands.'}
          </div>
        </Modal>
      )}
      {modal === 'command' && (
        <Modal title={command.name} onClose={closeModal}>
          <div className="modal-body">
            <div className="field-label">Original expression</div>
            <div className="command-source">
              <MathPreview latex={target.current.content} />
            </div>
            <p className="small-muted">{command.description}. The original step will not change.</p>
            {op === 'rowop' && (
              <div className="row-operation-form">
                <label className="form-label">
                  Operation
                  <select
                    className="text-input"
                    value={rowAction}
                    onChange={(e) => {
                      setRowAction(e.target.value);
                      invalidateResult();
                    }}
                  >
                    <option value="add">Add a multiple of one row to another</option>
                    <option value="swap">Swap two rows</option>
                    <option value="scale">Scale a row</option>
                  </select>
                </label>
                <div className="row-inputs">
                  {rowAction !== 'scale' && (
                    <label className="form-label">
                      Source row
                      <input
                        aria-label="Source row"
                        className="text-input"
                        type="number"
                        min={1}
                        max={8}
                        value={rowFrom}
                        onChange={(e) => {
                          setRowFrom(Number(e.target.value));
                          invalidateResult();
                        }}
                      />
                    </label>
                  )}
                  <label className="form-label">
                    Target row
                    <input
                      aria-label="Target row"
                      className="text-input"
                      type="number"
                      min={1}
                      max={8}
                      value={rowTo}
                      onChange={(e) => {
                        setRowTo(Number(e.target.value));
                        invalidateResult();
                      }}
                    />
                  </label>
                </div>
                {rowAction !== 'swap' && (
                  <label className="form-label">
                    Factor
                    <div className="form-math">
                      <MathEditor
                        value={other}
                        onChange={(v) => {
                          setOther(v);
                          invalidateResult();
                        }}
                        label="Row factor"
                      />
                    </div>
                  </label>
                )}
              </div>
            )}
            {['derivative', 'integral', 'substitute'].includes(op) && (
              <label className="form-label">
                {op === 'substitute' ? 'Variable to replace' : 'With respect to'}
                <input
                  className="text-input variable-input"
                  value={variable}
                  maxLength={24}
                  onChange={(e) => {
                    setVariable(e.target.value);
                    invalidateResult();
                  }}
                />
              </label>
            )}
            {['matmul', 'substitute', 'check'].includes(op) && (
              <label className="form-label">
                {op === 'matmul'
                  ? 'Multiply by this matrix'
                  : op === 'substitute'
                    ? 'Replace with'
                    : 'Compare with'}
                <div className="form-math">
                  <MathEditor
                    value={other}
                    onChange={(v) => {
                      setOther(v);
                      invalidateResult();
                    }}
                    onNext={runCommand}
                    label="Second expression"
                  />
                </div>
                {op === 'matmul' && (
                  <button
                    className="text-link"
                    onClick={() => setOther('\\begin{bmatrix}1 & 0 \\\\ 0 & 1\\end{bmatrix}')}
                  >
                    Start with a 2 × 2 matrix
                  </button>
                )}
              </label>
            )}
            {error && (
              <p className="error-message" role="alert">
                {error}
              </p>
            )}
            {result && (
              <div className="result-panel">
                <div className="result-label">
                  <Check size={15} />
                  {result.equivalent === undefined
                    ? 'Result'
                    : result.equivalent
                      ? 'Equivalent'
                      : 'Not established'}
                </div>
                {result.latex && <MathPreview latex={result.latex} />}
                <p>{result.note}</p>
              </div>
            )}
            <div className="modal-actions">
              <span className="small-muted">
                <ShieldCheck size={13} /> Local computation
              </span>
              <div className="spacer" />
              {result?.latex ? (
                <button
                  className="button primary"
                  onClick={() =>
                    insertTarget(
                      result.latex!,
                      'math',
                      op === 'rowop'
                        ? result.note
                        : `/${op}${['derivative', 'integral'].includes(op) ? ` with respect to ${variable}` : ''}`,
                    )
                  }
                >
                  Insert as next step <ArrowRight size={16} />
                </button>
              ) : (
                <button className="button primary" disabled={busy} onClick={runCommand}>
                  {busy ? <Loader2 className="spin" size={16} /> : <Sigma size={16} />}{' '}
                  {busy ? 'Calculating...' : 'Calculate'}
                </button>
              )}
            </div>
          </div>
        </Modal>
      )}
      {modal === 'export' && (
        <Modal title="Ready to hand in." wide onClose={closeModal}>
          <div className="export-layout">
            <div className="export-preview">
              <DocumentView doc={doc} />
            </div>
            <div className="export-options">
              <h3>Your work, well presented.</h3>
              <p>
                Only included steps appear in your PDF. Original ink and scratch work stay in your
                Folio file.
              </p>
              <div className="export-summary">
                <Check size={15} />
                {doc.blocks.length - excluded} of {doc.blocks.length} steps included
              </div>
              <button
                className="button primary"
                onClick={() => {
                  document.title = doc.title + ' | Folio';
                  window.print();
                }}
              >
                <Printer size={16} /> Print / save PDF
              </button>
              <p className="export-caption">
                Choose “Save as PDF” in the print dialog. Turn off browser headers and footers.
              </p>
              <div className="export-separator" />
              <button className="button" onClick={saveFile}>
                <Download size={16} /> Download .folio
              </button>
              <p className="export-caption">
                An editable backup, including every step and original pen stroke.
              </p>
              <button
                className="button"
                onClick={() => {
                  download(latexDocument(doc), fileName(doc.title) + '.tex', 'application/x-tex');
                  setToast('LaTeX downloaded. Handwriting is preserved in PDF and .folio only.');
                }}
              >
                <FileText size={16} /> Download LaTeX
              </button>
              <p className="export-caption">
                Typeset math and text. Handwriting is not included in .tex files.
              </p>
            </div>
          </div>
        </Modal>
      )}
      {modal === 'recognize' && (
        <Modal title="From handwriting to math" onClose={closeModal}>
          <div className="modal-body">
            <img
              src={inkImage}
              alt="Selected handwriting for recognition"
              className="recognition-image"
            />
            {!recognized ? (
              <>
                <p>
                  Gemini will transcribe this ink, not solve it. Review and correct the result
                  before adding it to your document.
                </p>
                {!health?.ai && (
                  <div className="connection-note">
                    Recognition needs a Gemini connection. Add <code>GEMINI_API_KEY</code> to{' '}
                    <code>.env</code> and restart the server. You can still write, edit, and save
                    ink without it.
                  </div>
                )}
                <label className="consent">
                  <input
                    type="checkbox"
                    checked={consent}
                    onChange={(e) => setConsent(e.target.checked)}
                  />
                  Send only this image to Google Gemini for recognition.
                </label>
                <button
                  className="button primary"
                  disabled={busy || !consent || !health?.ai}
                  onClick={recognize}
                >
                  {busy ? <Loader2 className="spin" size={16} /> : <ScanIcon />}
                  {busy ? 'Reading handwriting...' : 'Recognize selected ink'}
                </button>
                <div className="manual-divider">or transcribe it yourself</div>
                <button
                  className="button"
                  onClick={() => {
                    setRecognized(' ');
                    setRecognitionNote('Manual transcription. Your original ink will be kept.');
                  }}
                >
                  Enter the expression manually
                </button>
              </>
            ) : (
              <>
                <label className="form-label">
                  Review and correct
                  <div className="form-math">
                    <MathEditor
                      value={recognized}
                      onChange={setRecognized}
                      label="Recognized expression"
                    />
                  </div>
                </label>
                <p className="small-muted">
                  {recognitionNote || 'Check every symbol before accepting. AI can make mistakes.'}
                </p>
                <div className="modal-actions">
                  <span className="small-muted">Original ink is preserved.</span>
                  <div className="spacer" />
                  <button
                    className="button primary"
                    disabled={!recognized.trim()}
                    onClick={() =>
                      insertTarget(
                        recognized,
                        'math',
                        'Transcribed from handwriting; reviewed by user',
                      )
                    }
                  >
                    Accept & insert <ArrowRight size={15} />
                  </button>
                </div>
              </>
            )}
            {error && (
              <p className="error-message" role="alert">
                {error}
              </p>
            )}
          </div>
        </Modal>
      )}
      {modal === 'assist' && (
        <Modal title="A second pair of eyes" onClose={closeModal}>
          <div className="modal-body">
            <p>Ask about the selected step. Feedback is a suggestion, not a verified proof.</p>
            <label className="form-label">
              Your question
              <textarea
                className="text-input"
                rows={3}
                value={question}
                maxLength={1000}
                onChange={(e) => setQuestion(e.target.value)}
              />
            </label>
            {!health?.ai && (
              <div className="connection-note">
                Add <code>GEMINI_API_KEY</code> to <code>.env</code> and restart to connect Gemini.
                For a deterministic check, use <strong>Check equivalence</strong> in the command
                menu.
              </div>
            )}
            <label className="consent">
              <input
                type="checkbox"
                checked={consent}
                onChange={(e) => setConsent(e.target.checked)}
              />
              Send this selected step and my question to Google Gemini.
            </label>
            <button
              className="button primary"
              disabled={busy || !consent || !health?.ai || !question.trim()}
              onClick={assist}
            >
              {busy ? <Loader2 className="spin" size={16} /> : <Sparkles size={16} />}{' '}
              {busy ? 'Checking your work...' : 'Ask Gemini'}
            </button>
            {feedback && (
              <div className="ai-feedback">
                <p>{feedback}</p>
                <button className="button" onClick={() => insertTarget(feedback, 'text')}>
                  Add feedback as a note
                </button>
              </div>
            )}
            {error && (
              <p className="error-message" role="alert">
                {error}
              </p>
            )}
          </div>
        </Modal>
      )}
      {modal === 'settings' && (
        <Modal title="Your workspace" onClose={closeModal}>
          <div className="modal-body settings-body">
            {storageWarning && (
              <div className="connection-note">
                <p>{storageWarning}</p>
                <button
                  className="button small"
                  onClick={() =>
                    download(
                      localStorage.getItem(STORAGE_KEY) || '',
                      'folio-storage-backup.json',
                      'application/json',
                    )
                  }
                >
                  Back up stored data
                </button>
                <button
                  className="button small"
                  onClick={() => {
                    if (
                      !window.confirm(
                        'Replace the browser’s saved workspace with this open workspace? Download a backup first.',
                      )
                    )
                      return;
                    storagePaused.current = false;
                    setStorageWarning('');
                    setWorkspace({ ...current.current });
                  }}
                >
                  Resume saving this workspace
                </button>
              </div>
            )}
            <div className="settings-row">
              <ShieldCheck size={22} />
              <div>
                <h3>Local by default</h3>
                <p>
                  Documents are saved in this browser, not an account or cloud drive. Download
                  .folio backups before clearing browser data.
                </p>
              </div>
            </div>
            <div className="settings-row">
              <Sigma size={22} />
              <div>
                <h3>
                  Symbolic math{' '}
                  <span className="connection-status">{health ? 'Connected' : 'Offline'}</span>
                </h3>
                <p>
                  SymPy runs on your local server. No expressions are sent to an AI provider for
                  mathematical commands.
                </p>
              </div>
            </div>
            <div className="settings-row">
              <Sparkles size={22} />
              <div>
                <h3>
                  Gemini{' '}
                  <span className="connection-status">
                    {health?.ai ? 'Connected' : 'Not connected'}
                  </span>
                </h3>
                <p>
                  Optional handwriting recognition and feedback. Each request requires your consent.
                  Your API key stays on the server.
                </p>
                <code className="config-code">
                  GEMINI_API_KEY=your_key
                  <br />
                  GEMINI_MODEL=gemini-2.5-flash
                </code>
                <p>
                  Add these to <code>.env</code> in the project folder, then restart the server.
                </p>
                <button
                  className="button small"
                  onClick={() =>
                    api<typeof health>('health')
                      .then((h) => {
                        setHealth(h);
                        setToast('Connection status refreshed');
                      })
                      .catch((e) => setToast(e.message))
                  }
                >
                  Refresh connection
                </button>
              </div>
            </div>
            <div className="settings-row">
              <GitBranch size={22} />
              <div>
                <h3>Try a different path</h3>
                <p>Create an independent copy of this document to explore another solution.</p>
                <button
                  className="button small"
                  onClick={() => {
                    forkDocument();
                    closeModal();
                  }}
                >
                  Create alternative document
                </button>
              </div>
            </div>
            <button className="text-link danger" onClick={() => openModal('delete')}>
              Delete this document
            </button>
          </div>
        </Modal>
      )}
      {modal === 'delete' && (
        <Modal title="Delete this document?" onClose={closeModal}>
          <div className="modal-body">
            <p>“{doc.title}” will be removed from this browser. You can undo this action.</p>
            <div className="modal-actions">
              <button className="button" onClick={closeModal}>
                Keep document
              </button>
              <button
                className="button danger-button"
                onClick={() => {
                  change((w) => {
                    let documents = w.documents.filter((d) => d.id !== doc.id);
                    if (!documents.length) documents = [newDocument()];
                    return { ...w, documents, activeId: documents[0].id };
                  });
                  setSelectedId(null);
                  closeModal();
                }}
              >
                Delete document
              </button>
            </div>
          </div>
        </Modal>
      )}
      {modal === 'help' && (
        <Modal title="Make room for the working." onClose={closeModal}>
          <div className="modal-body help-body">
            <p>
              Folio keeps expressions, explanations, and handwriting in one document. Start with an
              example or create a fresh page.
            </p>
            <ol>
              <li>
                <strong>Write naturally.</strong> Type math with familiar shortcuts: <code>/</code>{' '}
                for fractions, <code>^</code> for powers, <code>sqrt</code> for roots. Arrow keys
                move between parts. Press Enter for another expression.
              </li>
              <li>
                <strong>Keep the reasoning.</strong> Add text or headings, duplicate a step, and
                edit the copy. Use pen input for scratch work and rectangle selection to move or
                convert strokes.
              </li>
              <li>
                <strong>Transform, then review.</strong> Select an expression and choose a command.
                Review the result, then insert it as a new step. Use the variable field for
                calculus.
              </li>
              <li>
                <strong>Choose what you hand in.</strong> Uncheck a step to leave it out of the
                export. It stays saved in your document. Export a PDF or take the editable .folio
                file with you.
              </li>
            </ol>
            <div className="shortcut-table">
              <div>
                <span>Command menu</span>
                <kbd>⌘ / Ctrl K</kbd>
              </div>
              <div>
                <span>Duplicate selected step</span>
                <kbd>⌘ / Ctrl Shift D</kbd>
              </div>
              <div>
                <span>Undo / redo document edit</span>
                <kbd>⌘ / Ctrl Z / Shift Z</kbd>
              </div>
              <div>
                <span>Download editable backup</span>
                <kbd>⌘ / Ctrl S</kbd>
              </div>
              <div>
                <span>Export preview</span>
                <kbd>⌘ / Ctrl P</kbd>
              </div>
            </div>
            <p className="small-muted">
              This is a browser prototype, not a native iPad or macOS app. AI recognition needs a
              configured Gemini key. Exact symbolic equivalence does not guarantee identical
              domains.
            </p>
            <button className="button primary" onClick={closeModal}>
              Back to thinking <ArrowRight size={16} />
            </button>
          </div>
        </Modal>
      )}
    </>
  );
}
function ScanIcon() {
  return <PenLine size={16} />;
}
