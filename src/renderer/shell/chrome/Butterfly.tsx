/** Original butterfly mark (hand-drawn SVG, not a Microsoft asset). */
export function Butterfly({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" className={className} aria-hidden="true">
      <g>
        {/* left wings */}
        <path
          d="M30 32 C18 14 6 10 4 18 C2 26 14 32 26 34 C14 36 4 42 7 50 C10 57 22 50 30 38 Z"
          fill="#ffd34e"
          stroke="#e8a33d"
          strokeWidth="1.5"
        />
        {/* right wings */}
        <path
          d="M34 32 C46 14 58 10 60 18 C62 26 50 32 38 34 C50 36 60 42 57 50 C54 57 42 50 34 38 Z"
          fill="#ffd34e"
          stroke="#e8a33d"
          strokeWidth="1.5"
        />
        {/* body */}
        <ellipse cx="32" cy="34" rx="3.4" ry="10" fill="#5a3c00" />
        <circle cx="32" cy="22" r="3.8" fill="#5a3c00" />
        {/* antennae */}
        <path d="M30 19 C27 13 23 11 20 12" fill="none" stroke="#5a3c00" strokeWidth="1.6" strokeLinecap="round" />
        <path d="M34 19 C37 13 41 11 44 12" fill="none" stroke="#5a3c00" strokeWidth="1.6" strokeLinecap="round" />
      </g>
    </svg>
  );
}
