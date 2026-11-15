import { memo, useEffect, useRef } from 'react';
import { MathfieldElement } from 'mathlive';
import katex from 'katex';

MathfieldElement.fontsDirectory = '/mathlive/fonts';
MathfieldElement.soundsDirectory = null;
let enginePromise: Promise<import('@cortex-js/compute-engine').ComputeEngine> | undefined;
export async function mathJSON(latex: string): Promise<unknown> {
  if (!latex.trim()) throw new Error('Enter an expression first.');
  if (latex.length > 5000) throw new Error('This expression is too large for a command.');
  enginePromise ??= import('@cortex-js/compute-engine').then(
    ({ ComputeEngine }) => new ComputeEngine(),
  );
  const expression = (await enginePromise).parse(latex);
  if (!expression.isValid) throw new Error('Complete the expression before running a command.');
  return expression.json;
}
export const MathPreview = memo(function MathPreview({
  latex,
  display = true,
}: {
  latex: string;
  display?: boolean;
}) {
  let html;
  try {
    html = katex.renderToString(latex || '\\phantom{x}', {
      displayMode: display,
      throwOnError: true,
      trust: false,
      strict: 'ignore',
      maxExpand: 300,
      maxSize: 20,
    });
  } catch {
    return (
      <span className="math-invalid">
        {latex || 'Empty expression'}
        <small>Unfinished expression</small>
      </span>
    );
  }
  return <span className="math-preview" dangerouslySetInnerHTML={{ __html: html }} />;
});
export default function MathEditor({
  value,
  onChange,
  onFocus,
  onNext,
  onCommands,
  label,
}: {
  value: string;
  onChange: (v: string) => void;
  onFocus?: () => void;
  onNext?: () => void;
  onCommands?: () => void;
  label?: string;
}) {
  const host = useRef<HTMLDivElement>(null);
  const field = useRef<MathfieldElement | null>(null);
  const latestValue = useRef(value);
  latestValue.current = value;
  const handlers = useRef({ onChange, onFocus, onNext, onCommands });
  handlers.current = { onChange, onFocus, onNext, onCommands };
  useEffect(() => {
    const mf = new MathfieldElement();
    mf.mathVirtualKeyboardPolicy = 'manual';
    mf.smartFence = true;
    mf.smartMode = false;
    mf.defaultMode = 'math';
    mf.setAttribute('aria-label', label || 'Mathematical expression');
    mf.setAttribute('placeholder', 'Write an expression...');
    mf.value = value;
    const input = () => {
      if (mf.value.length > 20000) {
        mf.setValue(latestValue.current, { silenceNotifications: true });
        return;
      }
      handlers.current.onChange(mf.value);
    };
    const focus = () => handlers.current.onFocus?.();
    const keydown = (e: KeyboardEvent) => {
      if (e.key === 'Enter' && !e.shiftKey && !e.altKey && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        e.stopPropagation();
        handlers.current.onNext?.();
      }
      if (e.key === '/' && !mf.value.trim() && handlers.current.onCommands) {
        e.preventDefault();
        e.stopPropagation();
        handlers.current.onCommands();
      }
    };
    mf.addEventListener('input', input);
    mf.addEventListener('focus', focus);
    mf.addEventListener('keydown', keydown, true);
    host.current?.appendChild(mf);
    field.current = mf;
    return () => {
      mf.removeEventListener('input', input);
      mf.removeEventListener('focus', focus);
      mf.removeEventListener('keydown', keydown, true);
      mf.remove();
      field.current = null;
    };
  }, []);
  useEffect(() => {
    if (field.current && field.current.value !== value)
      field.current.setValue(value, { silenceNotifications: true });
  }, [value]);
  useEffect(() => {
    field.current?.setAttribute('aria-label', label || 'Mathematical expression');
  }, [label]);
  return <div className="math-editor" ref={host} />;
}
