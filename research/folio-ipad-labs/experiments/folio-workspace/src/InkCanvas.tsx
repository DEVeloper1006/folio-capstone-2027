import { useRef, useState } from 'react';
import { PenLine, Eraser, Scan, Trash2, Copy, MousePointer2, Sparkles } from 'lucide-react';
import { uid, type Point, type Stroke } from './model';
export const WIDTH = 800,
  HEIGHT = 280;
const path = (points: Point[]) =>
  points.length === 1
    ? `M${points[0].x},${points[0].y}l0.1,0.1`
    : points.map((p, i) => `${i ? 'L' : 'M'}${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' ');
export function InkView({ strokes }: { strokes: Stroke[] }) {
  return (
    <svg
      viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
      className="ink-view"
      role="img"
      aria-label="Handwritten mathematics"
    >
      {strokes.map((s) => (
        <path
          key={s.id}
          d={path(s.points)}
          stroke={s.color}
          strokeWidth={s.width}
          fill="none"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      ))}
    </svg>
  );
}
export default function InkCanvas({
  strokes,
  onChange,
  onRecognize,
}: {
  strokes: Stroke[];
  onChange: (s: Stroke[]) => void;
  onRecognize: (image: string) => void;
}) {
  const [tool, setTool] = useState<'pen' | 'erase' | 'select'>('pen');
  const [selected, setSelected] = useState<string[]>([]);
  const [draft, setDraft] = useState<Point[]>([]);
  const [selection, setSelection] = useState<{ x: number; y: number; w: number; h: number } | null>(
    null,
  );
  const [moving, setMoving] = useState<{ x: number; y: number } | null>(null);
  const [color, setColor] = useState('#274a73');
  const svg = useRef<SVGSVGElement>(null);
  const gesture = useRef<{
    start: Point;
    points: Point[];
    mode: 'pen' | 'erase' | 'box' | 'move';
    erased: Set<string>;
  } | null>(null);
  const point = (event: React.PointerEvent): Point => {
    const rect = svg.current!.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(WIDTH, ((event.clientX - rect.left) * WIDTH) / rect.width)),
      y: Math.max(0, Math.min(HEIGHT, ((event.clientY - rect.top) * HEIGHT) / rect.height)),
      pressure: event.pressure || 0.5,
    };
  };
  const eraseAt = (p: Point, erased: Set<string>) =>
    strokes.forEach((s) => {
      if (s.points.some((q) => Math.hypot(p.x - q.x, p.y - q.y) < 12)) erased.add(s.id);
    });
  const down = (event: React.PointerEvent<SVGSVGElement>) => {
    if (event.button !== 0 || !event.isPrimary) return;
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    const p = point(event);
    const hit = strokes
      .filter((s) => selected.includes(s.id))
      .some((s) => s.points.some((q) => Math.hypot(p.x - q.x, p.y - q.y) < 20));
    const mode = tool === 'pen' ? 'pen' : tool === 'erase' ? 'erase' : hit ? 'move' : 'box';
    gesture.current = { start: p, points: [p], mode, erased: new Set() };
    if (mode === 'pen') setDraft([p]);
    if (mode === 'box') {
      setSelected([]);
      setSelection({ x: p.x, y: p.y, w: 0, h: 0 });
    }
    if (mode === 'erase') eraseAt(p, gesture.current.erased);
  };
  const move = (event: React.PointerEvent<SVGSVGElement>) => {
    const g = gesture.current;
    if (!g) return;
    const p = point(event);
    if (g.mode === 'pen') {
      g.points.push(p);
      setDraft([...g.points]);
    }
    if (g.mode === 'erase') {
      eraseAt(p, g.erased);
      setDraft([p]);
    }
    if (g.mode === 'move') setMoving({ x: p.x - g.start.x, y: p.y - g.start.y });
    if (g.mode === 'box')
      setSelection({
        x: Math.min(p.x, g.start.x),
        y: Math.min(p.y, g.start.y),
        w: Math.abs(p.x - g.start.x),
        h: Math.abs(p.y - g.start.y),
      });
  };
  const end = (event: React.PointerEvent<SVGSVGElement>) => {
    const g = gesture.current;
    if (!g) return;
    const p = point(event);
    if (g.mode === 'pen' && g.points.length)
      onChange([...strokes, { id: uid(), points: g.points, color, width: 2.6 }]);
    if (g.mode === 'erase') onChange(strokes.filter((s) => !g.erased.has(s.id)));
    if (g.mode === 'move')
      onChange(
        strokes.map((s) =>
          selected.includes(s.id)
            ? {
                ...s,
                points: s.points.map((q) => ({
                  ...q,
                  x: Math.max(0, Math.min(WIDTH, q.x + p.x - g.start.x)),
                  y: Math.max(0, Math.min(HEIGHT, q.y + p.y - g.start.y)),
                })),
              }
            : s,
        ),
      );
    if (g.mode === 'box') {
      const x = Math.min(p.x, g.start.x),
        y = Math.min(p.y, g.start.y),
        w = Math.abs(p.x - g.start.x),
        h = Math.abs(p.y - g.start.y);
      setSelected(
        strokes
          .filter((s) => s.points.some((q) => q.x >= x && q.x <= x + w && q.y >= y && q.y <= y + h))
          .map((s) => s.id),
      );
    }
    gesture.current = null;
    setDraft([]);
    setSelection(null);
    setMoving(null);
    if (event.currentTarget.hasPointerCapture(event.pointerId))
      event.currentTarget.releasePointerCapture(event.pointerId);
  };
  const recognize = () => {
    const ink = selected.length ? strokes.filter((s) => selected.includes(s.id)) : strokes;
    const points = ink.flatMap((s) => s.points);
    if (!points.length) return;
    const bounds = points.reduce(
      (b, p) => ({
        minX: Math.min(b.minX, p.x),
        minY: Math.min(b.minY, p.y),
        maxX: Math.max(b.maxX, p.x),
        maxY: Math.max(b.maxY, p.y),
      }),
      { minX: WIDTH, minY: HEIGHT, maxX: 0, maxY: 0 },
    );
    const minX = Math.max(0, bounds.minX - 20),
      minY = Math.max(0, bounds.minY - 20);
    const w = Math.min(WIDTH - minX, bounds.maxX - minX + 20),
      h = Math.min(HEIGHT - minY, bounds.maxY - minY + 20);
    const canvas = document.createElement('canvas');
    canvas.width = Math.ceil(w * 2);
    canvas.height = Math.ceil(h * 2);
    const ctx = canvas.getContext('2d')!;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.scale(2, 2);
    ctx.translate(-minX, -minY);
    ink.forEach((s) => {
      ctx.beginPath();
      s.points.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      if (s.points.length === 1) ctx.lineTo(s.points[0].x + 0.1, s.points[0].y + 0.1);
      ctx.strokeStyle = s.color;
      ctx.lineWidth = s.width;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.stroke();
    });
    onRecognize(canvas.toDataURL('image/png'));
  };
  return (
    <div className="ink-canvas">
      <div className="ink-toolbar">
        <div className="segmented">
          <button
            className={tool === 'pen' ? 'is-active' : ''}
            onClick={() => setTool('pen')}
            title="Pen"
            aria-label="Pen"
            aria-pressed={tool === 'pen'}
          >
            <PenLine size={16} />
          </button>
          <button
            className={tool === 'erase' ? 'is-active' : ''}
            onClick={() => setTool('erase')}
            title="Erase strokes"
            aria-label="Erase strokes"
            aria-pressed={tool === 'erase'}
          >
            <Eraser size={16} />
          </button>
          <button
            className={tool === 'select' ? 'is-active' : ''}
            onClick={() => setTool('select')}
            title="Select a region, then drag ink to move"
            aria-label="Select handwriting"
            aria-pressed={tool === 'select'}
          >
            <MousePointer2 size={16} />
          </button>
        </div>
        <span className="toolbar-divider" />
        {['#274a73', '#252d32', '#176b61'].map((c) => (
          <button
            key={c}
            className={`ink-color ${color === c ? 'is-active' : ''}`}
            style={{ '--ink': c } as React.CSSProperties}
            aria-label={`Ink ${c}`}
            aria-pressed={color === c}
            onClick={() => {
              setColor(c);
              setTool('pen');
            }}
          />
        ))}
        <div className="spacer" />
        {selected.length > 0 && (
          <>
            <span className="small-muted">{selected.length} selected</span>
            <button
              className="icon-button"
              title="Duplicate selected ink"
              aria-label="Duplicate selected ink"
              onClick={() => {
                onChange([
                  ...strokes,
                  ...strokes
                    .filter((s) => selected.includes(s.id))
                    .map((s) => ({
                      ...s,
                      id: uid(),
                      points: s.points.map((p) => ({
                        ...p,
                        x: Math.min(WIDTH, p.x + 16),
                        y: Math.min(HEIGHT, p.y + 16),
                      })),
                    })),
                ]);
              }}
            >
              <Copy size={15} />
            </button>
            <button
              className="icon-button"
              title="Delete selected ink"
              aria-label="Delete selected ink"
              onClick={() => {
                onChange(strokes.filter((s) => !selected.includes(s.id)));
                setSelected([]);
              }}
            >
              <Trash2 size={15} />
            </button>
          </>
        )}
        <button className="button small" disabled={!strokes.length} onClick={recognize}>
          <Scan size={15} /> Convert {selected.length ? 'selection' : 'to math'}
        </button>
      </div>
      <div className="ink-surface">
        {!strokes.length && !draft.length && (
          <div className="ink-placeholder">
            <PenLine size={22} />
            <span>A little room to think.</span>
            <small>Write with your pencil, finger, or mouse</small>
          </div>
        )}
        <svg
          ref={svg}
          viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
          role="img"
          aria-label="Handwriting canvas"
          className={`ink-input tool-${tool}`}
          onPointerDown={down}
          onPointerMove={move}
          onPointerUp={end}
          onPointerCancel={() => {
            gesture.current = null;
            setDraft([]);
            setSelection(null);
            setMoving(null);
          }}
        >
          {strokes
            .filter((s) => !gesture.current?.erased.has(s.id))
            .map((s) => (
              <path
                key={s.id}
                d={path(s.points)}
                stroke={s.color}
                strokeWidth={selected.includes(s.id) ? s.width + 1 : s.width}
                opacity={selected.includes(s.id) ? 0.65 : 1}
                transform={
                  selected.includes(s.id) && moving
                    ? `translate(${moving.x},${moving.y})`
                    : undefined
                }
                fill="none"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            ))}
          {draft.length > 0 && tool === 'pen' && (
            <path
              d={path(draft)}
              stroke={color}
              strokeWidth={2.6}
              fill="none"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          )}
          {selection && (
            <rect
              x={selection.x}
              y={selection.y}
              width={selection.w}
              height={selection.h}
              fill="#176b6110"
              stroke="#176b61"
              strokeDasharray="5 4"
            />
          )}
        </svg>
      </div>
      <div className="ink-caption">
        <Sparkles size={12} />
        <span>Original ink stays safe when you convert.</span>
        <span className="spacer" />
        <span>{strokes.length} strokes</span>
      </div>
    </div>
  );
}
