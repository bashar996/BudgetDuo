// Small pieces the side panels share: chip rows, labelled inputs, the switch.
import type { ReactNode } from 'react'
import { css, sx } from '../lib/css'
import { Field, inputStyle } from './PanelFrame'

export interface ChipOpt { key: string; label: string; on: boolean; pick(): void }

/** The design's `chip()`: ink when picked, hairline outline otherwise. */
export function Chip({ c, grow }: { c: ChipOpt; grow?: boolean }) {
  return (
    <button type="button" onClick={c.pick} aria-pressed={c.on}
      style={sx("height:44px;padding:0 15px;border-radius:22px;font:500 13.5px 'Geist',sans-serif;cursor:pointer", {
        flex: grow ? 1 : undefined,
        border: '1px solid ' + (c.on ? 'var(--ink)' : 'var(--chip)'),
        background: c.on ? 'var(--ink)' : 'transparent',
        color: c.on ? 'var(--bg)' : 'var(--ink)',
      })}>{c.label}</button>
  )
}

/** "Category", "Paid from", … followed by a wrapping row of chips. */
export function ChipGroup({ label, chips, grow }: { label: string; chips: ChipOpt[]; grow?: boolean }) {
  return (
    <div>
      <div style={css('font-size:13px;color:var(--mute);margin-bottom:8px')}>{label}</div>
      <div style={sx('display:flex;gap:6px', { flexWrap: grow ? 'nowrap' : 'wrap' })}>
        {chips.map((c) => <Chip key={c.key} c={c} grow={grow} />)}
      </div>
    </div>
  )
}

export const chips = <K extends string>(opts: [K, string][], cur: K | string | undefined, set: (k: K) => void): ChipOpt[] =>
  opts.map(([k, label]) => ({ key: k, label, on: cur === k, pick: () => set(k) }))

/** Labelled text input (52px). */
export function TextField({ label, value, onChange, placeholder, decimal, type }: {
  label: string; value: string; onChange(v: string): void; placeholder?: string; decimal?: boolean; type?: string
}) {
  return (
    <Field label={label}>
      <input className="h-focus-ink" type={type} inputMode={decimal ? 'decimal' : undefined} placeholder={placeholder} value={value}
        onChange={(e) => onChange(e.target.value)} style={inputStyle} />
    </Field>
  )
}

/** The 64px / 30px limit input from the budget and category panels. */
export function BigField({ label, value, onChange, placeholder }: { label: string; value: string; onChange(v: string): void; placeholder?: string }) {
  return (
    <Field label={label}>
      <input className="h-focus-ink" inputMode="decimal" placeholder={placeholder} value={value} onChange={(e) => onChange(e.target.value)}
        style={css("box-sizing:border-box;width:100%;height:64px;padding:0 16px;border:none;border-radius:18px;background:var(--card);color:var(--ink);font:500 30px 'Geist',sans-serif;letter-spacing:-.02em;outline:none")} />
    </Field>
  )
}

/** Two fields side by side, wrapping under 320px. */
export function Pair({ children }: { children: ReactNode }) {
  return <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:10px')}>{children}</div>
}

/** Outline pill button ("Use 3-month average", "+100"). */
export function Pill({ children, onClick }: { children: ReactNode; onClick(): void }) {
  return (
    <button type="button" onClick={onClick}
      style={css("align-self:flex-start;font:500 13.5px 'Geist',sans-serif;padding:0 16px;height:44px;border-radius:22px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);cursor:pointer")}>{children}</button>
  )
}

/** On/off switch, as the auto-save toggle in Savings. */
export function Switch({ on, onChange, label }: { on: boolean; onChange(v: boolean): void; label: string }) {
  return (
    <div style={css('display:flex;align-items:center;gap:10px')}>
      <button type="button" role="switch" aria-checked={on} aria-label={label} onClick={() => onChange(!on)}
        style={css('width:48px;height:44px;padding:8px 0;border:none;background:none;cursor:pointer;flex:none')}>
        <span style={sx('display:block;position:relative;width:48px;height:28px;border-radius:14px;transition:background .2s', { background: on ? 'var(--ink)' : 'var(--chip)' })}>
          <span style={sx('position:absolute;top:3px;width:22px;height:22px;border-radius:50%;background:#ffffff;transition:left .2s', { left: on ? 23 : 3 })} />
        </span>
      </button>
      <span style={css('font-size:13.5px')}>{label}</span>
    </div>
  )
}

/** Parses a typed amount; NaN when empty. */
export const parse = (s: string) => parseFloat(String(s).replace(/,/g, ''))
