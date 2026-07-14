import { useEffect, useRef } from 'react';

/**
 * Placeholder for the WebContentsView, which the main process composites
 * over this area. We stream this div's rect to main and toggle visibility
 * with mount/unmount.
 */
export function BrowserPane() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const push = () => {
      const rect = el.getBoundingClientRect();
      void window.papillon.invoke('browser:setBounds', {
        bounds: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
      });
    };
    push();
    void window.papillon.invoke('browser:setVisible', { visible: true });

    const observer = new ResizeObserver(push);
    observer.observe(el);
    window.addEventListener('resize', push);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', push);
      void window.papillon.invoke('browser:setVisible', { visible: false });
    };
  }, []);

  return (
    <div ref={ref} className="browser-pane">
      Loading the web…
    </div>
  );
}
