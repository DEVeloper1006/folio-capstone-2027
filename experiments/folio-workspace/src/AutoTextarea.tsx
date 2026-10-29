import { useEffect, useLayoutEffect, useRef, type TextareaHTMLAttributes } from 'react';

/** Keep text readable after typing, resizing, and switching document layouts. */
export default function AutoTextarea(props: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const ref = useRef<HTMLTextAreaElement>(null);
  const resize = () => {
    const element = ref.current;
    if (!element) return;
    element.style.height = '0px';
    element.style.height = `${element.scrollHeight}px`;
  };
  useLayoutEffect(resize, [props.value]);
  useEffect(() => {
    let width = -1;
    let frame = 0;
    const observer = new ResizeObserver(([entry]) => {
      if (entry.contentRect.width !== width) {
        width = entry.contentRect.width;
        cancelAnimationFrame(frame);
        frame = requestAnimationFrame(resize);
      }
    });
    if (ref.current) observer.observe(ref.current);
    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
    };
  }, []);
  return <textarea {...props} ref={ref} />;
}
