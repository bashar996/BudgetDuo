// 24×24 stroke icons from the design (stroke-width 1.8, round caps).
export const ICON: Record<string, string> = {home:'M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z',activity:'M9 6h12M9 12h12M9 18h12M4 6h1M4 12h1M4 18h1',budget:'M12 3a9 9 0 1 0 9 9h-9z M15.5 3.6A9 9 0 0 1 20.4 8.5H15.5z',bills:'M5 5h14a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z M4 10h16 M8 3v4 M16 3v4',accounts:'M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z M3 10h18 M7 15h3',savings:'M4 7c0-1.7 3.6-3 8-3s8 1.3 8 3-3.6 3-8 3-8-1.3-8-3z M4 7v5c0 1.7 3.6 3 8 3s8-1.3 8-3V7 M4 12v5c0 1.7 3.6 3 8 3s8-1.3 8-3v-5',goals:'M3 7l6 6 4-4 8 8 M21 11v6h-6',reports:'M5 20v-9 M12 20V4 M19 20v-6 M3 20h18',plan:'M3 17l5-5 4 3 8-9 M15 6h5v5',us:'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z M2.5 20c0-3.3 2.9-6 6.5-6s6.5 2.7 6.5 6 M16 4.3a3.5 3.5 0 0 1 0 6.4 M18 14.3c2 .8 3.5 2.9 3.5 5.7',more:'M4 7h16M4 12h16M4 17h16',worth:'M12 3 3 8l9 5 9-5z M3 12.5l9 5 9-5 M3 17l9 5 9-5',
  import:'M12 4v11 M7.5 10.5 12 15l4.5-4.5 M4 15v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3',
  trash:'M4 7h16 M10 11v6 M14 11v6 M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12 M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2',
  panel:'M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z M9.5 4v16',
  settings:'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z'}

export function Icon({ d, size = 22 }: { d: string; size?: number }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" style={{ width: size, height: size, flex: 'none', fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' }}>
      <path d={d} />
    </svg>
  )
}
