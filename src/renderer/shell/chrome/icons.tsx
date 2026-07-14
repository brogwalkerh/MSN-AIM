/** Original toolbar icons in the chunky early-2000s style. */

const stroke = '#1c3f94';

export function HomeIcon() {
  return (
    <svg viewBox="0 0 32 32" className="toolbar__icon" aria-hidden="true">
      <path d="M4 16 L16 5 L28 16" fill="none" stroke="#fff" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M8 15 V27 H24 V15" fill="#ffd34e" stroke={stroke} strokeWidth="1.5" />
      <rect x="13.5" y="19" width="5" height="8" fill="#3a6ea5" stroke={stroke} />
    </svg>
  );
}

export function MailIcon() {
  return (
    <svg viewBox="0 0 32 32" className="toolbar__icon" aria-hidden="true">
      <rect x="4" y="8" width="24" height="17" rx="2" fill="#ffffff" stroke={stroke} strokeWidth="1.5" />
      <path d="M4 10 L16 19 L28 10" fill="none" stroke="#e8a33d" strokeWidth="2" strokeLinejoin="round" />
    </svg>
  );
}

export function ChatIcon() {
  return (
    <svg viewBox="0 0 32 32" className="toolbar__icon" aria-hidden="true">
      <path d="M4 6 h18 a3 3 0 0 1 3 3 v8 a3 3 0 0 1 -3 3 h-9 l-6 5 v-5 h-3 a3 3 0 0 1 -3 -3 v-8 a3 3 0 0 1 3 -3 z" fill="#ffffff" stroke={stroke} strokeWidth="1.5" />
      <circle cx="11" cy="13" r="1.8" fill="#3a6ea5" />
      <circle cx="16" cy="13" r="1.8" fill="#3a6ea5" />
      <circle cx="21" cy="13" r="1.8" fill="#3a6ea5" />
      <circle cx="25" cy="24" r="4.5" fill="#35a544" stroke="#fff" strokeWidth="1.5" />
    </svg>
  );
}

export function BrowserIcon() {
  return (
    <svg viewBox="0 0 32 32" className="toolbar__icon" aria-hidden="true">
      <circle cx="16" cy="16" r="12" fill="#7fa8d9" stroke={stroke} strokeWidth="1.5" />
      <ellipse cx="16" cy="16" rx="5.5" ry="12" fill="none" stroke="#ffffff" strokeWidth="1.4" />
      <path d="M4.5 12 h23 M4.5 20 h23" fill="none" stroke="#ffffff" strokeWidth="1.4" />
    </svg>
  );
}

export function MediaIcon() {
  return (
    <svg viewBox="0 0 32 32" className="toolbar__icon" aria-hidden="true">
      <circle cx="13" cy="23" r="4" fill="#ffd34e" stroke={stroke} strokeWidth="1.5" />
      <circle cx="25" cy="20" r="4" fill="#ffd34e" stroke={stroke} strokeWidth="1.5" />
      <path d="M17 23 V8 l12 -3 v15" fill="none" stroke="#ffffff" strokeWidth="2.5" strokeLinejoin="round" />
    </svg>
  );
}
