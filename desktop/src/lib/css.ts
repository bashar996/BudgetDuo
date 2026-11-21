import type { CSSProperties } from 'react'

const cache = new Map<string, CSSProperties>()

/**
 * Turns a CSS declaration string, as written in the design files, into a React
 * style object: css("display:flex;gap:10px") → { display: 'flex', gap: '10px' }.
 * Lets the design's inline styles be copied over unchanged. Results are cached.
 */
export function css(text: string): CSSProperties {
  const hit = cache.get(text)
  if (hit) return hit
  const out: Record<string, string> = {}
  // Split on ; that is not inside parentheses (url(...), gradients, var(...)).
  let depth = 0, start = 0
  const parts: string[] = []
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (c === '(') depth++
    else if (c === ')') depth--
    else if (c === ';' && depth === 0) { parts.push(text.slice(start, i)); start = i + 1 }
  }
  parts.push(text.slice(start))
  for (const part of parts) {
    const i = part.indexOf(':')
    if (i < 0) continue
    const prop = part.slice(0, i).trim()
    const value = part.slice(i + 1).trim()
    if (!prop) continue
    const key = prop.startsWith('--') ? prop
      : prop.startsWith('-webkit-') ? 'Webkit' + camel(prop.slice(8))
      : camel(prop)
    out[key] = value
  }
  cache.set(text, out as CSSProperties)
  return out as CSSProperties
}

function camel(s: string) { return s.replace(/-([a-z])/g, (_, c: string) => c.toUpperCase()) }

/** css() plus extra values, e.g. sx("height:8px", { width: pct }). */
export function sx(text: string, extra: CSSProperties): CSSProperties {
  return { ...css(text), ...extra }
}
