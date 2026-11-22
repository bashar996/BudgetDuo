import { useEffect, useState, type ReactNode } from 'react'
import { css, sx } from '../lib/css'
import { useUI } from '../shell/ui'

export interface PanelFrameProps {
  title: string
  /** Expense / Income / Transfer chips under the title. */
  types?: { label: string; on: boolean; pick(): void }[]
  /** Oversized 68px amount input in the lavender top. */
  amount?: { value: string; onChange(v: string): void; currency: string }
  err?: string
  onDelete?: () => void
  /** "Confirm delete" on the second step of a two-step delete. */
  deleteLabel?: string
  onSave: () => void
  saveLabel?: string
  children: ReactNode
}

/**
 * The side panel from the design: slides in from the right, lavender top with
 * title, close button, optional type chips and big amount, blob edge, the form
 * on cream, and a sticky footer with the error line, Delete and Save.
 */
export function PanelFrame(p: PanelFrameProps) {
  const { close } = useUI()
  const [shown, setShown] = useState(false)
  useEffect(() => { const t = setTimeout(() => setShown(true), 20); return () => clearTimeout(t) }, [])
  const shut = () => { setShown(false); setTimeout(close, 230) }
  useEffect(() => {
    const k = (e: KeyboardEvent) => { if (e.key === 'Escape') shut() }
    window.addEventListener('keydown', k)
    return () => window.removeEventListener('keydown', k)
  }, [])

  return (
    <div className="nodrag" onClick={shut} style={sx('position:fixed;inset:0;z-index:50;background:rgba(0,0,0,.55);display:flex;justify-content:flex-end;transition:opacity .22s', { opacity: shown ? 1 : 0 })}>
      <div data-stage="cream" role="dialog" aria-label={p.title} onClick={(e) => e.stopPropagation()}
        style={sx('width:min(480px,100%);height:100%;overflow:auto;box-sizing:border-box;background:var(--bg);color:var(--ink);display:flex;flex-direction:column;transition:transform .28s cubic-bezier(.2,.8,.2,1)', { transform: shown ? 'translateX(0)' : 'translateX(100%)' })}>
        <div style={css('background:var(--accBase);color:#0b0b0c;padding:18px 18px 0 24px;flex:none')}>
          <div style={css('display:flex;justify-content:space-between;align-items:center;gap:12px')}>
            <span style={css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")}>{p.title}</span>
            <button onClick={shut} aria-label="Close" style={css('width:44px;height:44px;flex:none;border:none;border-radius:15px;background:#0b0b0c;color:#ffffff;font-size:20px;cursor:pointer')}>×</button>
          </div>
          {p.types && (
            <div style={css('display:flex;gap:6px;margin-top:16px')}>
              {p.types.map((c) => (
                <button key={c.label} onClick={c.pick} aria-pressed={c.on} style={sx("height:44px;padding:0 16px;border-radius:22px;border:1.5px solid #0b0b0c;font:500 14px 'Geist',sans-serif;cursor:pointer", { background: c.on ? '#0b0b0c' : 'transparent', color: c.on ? '#ffffff' : '#0b0b0c' })}>{c.label}</button>
              ))}
            </div>
          )}
          {p.amount && (
            <label style={css('display:flex;align-items:baseline;gap:10px;margin-top:18px;padding-right:6px')}>
              <span style={css("font:500 24px 'Geist',sans-serif;color:#3a3566")}>{p.amount.currency}</span>
              <input autoFocus inputMode="decimal" placeholder="0" value={p.amount.value} onChange={(e) => p.amount!.onChange(e.target.value.replace(/[^0-9.]/g, ''))}
                style={css("flex:1;min-width:0;border:none;background:transparent;color:#0b0b0c;font:500 68px/1 'Geist',sans-serif;letter-spacing:-.045em;outline:none;padding:0")} />
            </label>
          )}
        </div>
        <div style={css('background:var(--accBase);flex:none')}>
          <div style={css('height:56px;background:var(--bg);-webkit-mask-image:var(--blob);mask-image:var(--blob);-webkit-mask-size:800px 56px;mask-size:800px 56px;-webkit-mask-repeat:repeat-x;mask-repeat:repeat-x')} />
        </div>
        <form onSubmit={(e) => { e.preventDefault(); p.onSave() }} style={css('flex:1;display:flex;flex-direction:column')}>
          <div style={css('flex:1;padding:8px 24px 0;margin-top:-1px;display:flex;flex-direction:column;gap:16px')}>{p.children}</div>
          <div style={css('display:flex;flex-wrap:wrap;gap:8px 10px;position:sticky;bottom:0;background:var(--bg);padding:14px 24px 24px;flex:none')}>
            <div role="alert" style={css('flex-basis:100%;font-size:13.5px;font-weight:500;color:var(--bad)')}>{p.err}</div>
            {p.onDelete && <button type="button" onClick={p.onDelete} style={css("font:500 15px 'Geist',sans-serif;padding:0 20px;height:58px;border-radius:20px;border:1.5px solid var(--bad);background:transparent;color:var(--bad);cursor:pointer")}>{p.deleteLabel ?? 'Delete'}</button>}
            <button type="submit" style={css("flex:1;font:500 17px 'Geist',sans-serif;height:58px;border-radius:20px;border:none;background:var(--btn);color:var(--btnInk);cursor:pointer")}>{p.saveLabel ?? 'Save'}</button>
          </div>
        </form>
      </div>
    </div>
  )
}

/** Labelled input in the panel body ("font-size:13px;color:var(--mute)" label). */
export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label style={css('display:flex;flex-direction:column;gap:6px')}>
      <span style={css('font-size:13px;color:var(--mute)')}>{label}</span>
      {children}
    </label>
  )
}

/** Panel text input, exactly as in the design (focus ring via .h-focus-ink). */
export const inputStyle = css("box-sizing:border-box;width:100%;height:52px;padding:0 16px;border:none;border-radius:16px;background:var(--card);color:var(--ink);font:500 15px 'Geist',sans-serif;outline:none")
