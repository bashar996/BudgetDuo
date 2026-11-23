import { useEffect, useMemo, useRef, useState } from 'react'
import { css, sx } from '../lib/css'
import { addM, isoOf, mLabel } from '../lib/dates'
import { cycleStartOf, periodKey } from '../lib/period'
import { makeLedger } from '../data/ledger'
import { useStore } from '../data/store'
import { Icon, ICON } from './icons'
import { TABS, UICtx, type HeroSpec, type MenuSpec, type Panel, type TabId, type UI, type ViewState } from './ui'
import { TAB_DEFS } from '../tabs'
import { PanelHost } from '../panels/PanelHost'
import { isStatementFile } from '../import/read'

const LS = {
  get(k: string) { try { return localStorage.getItem('twofold:' + k) } catch { return null } },
  set(k: string, v: string) { try { localStorage.setItem('twofold:' + k, v) } catch { /* private mode */ } },
}

export function Shell() {
  const { data, act } = useStore()
  // Today, checked every minute, so the numbers and plan billing move on at midnight.
  const [day, setDay] = useState(() => isoOf(new Date()))
  useEffect(() => {
    const t = setInterval(() => { const d = isoOf(new Date()); setDay((x) => (x === d ? x : d)) }, 60000)
    return () => clearInterval(t)
  }, [])
  // Card installment plans bill themselves: post any installment that's come due (store.tsx billPlans).
  // It writes only what's missing and skips plans whose last write is still on its way, so the data
  // change it causes runs this again without posting anything twice.
  useEffect(() => { act.billPlans(day) }, [data, day])
  const [tab, setTab] = useState<TabId>(() => (LS.get('tab') as TabId) || 'home')
  // The budget month shown: a period key (lib/period.ts). It starts on the current one, and goes
  // back to the current one when the household changes the day budget months start.
  const start = cycleStartOf(data.household)
  const [ym, setYm] = useState(() => periodKey(isoOf(new Date()), start))
  const startRef = useRef(start)
  useEffect(() => {
    if (startRef.current === start) return
    startRef.current = start
    setYm(periodKey(isoOf(new Date()), start))
  }, [start])
  const [view, setViewState] = useState<ViewState>({ q: '', fWho: 'all', fCat: 'all', fAcct: 'all', selAcct: null })
  const [panel, setPanel] = useState<Panel | null>(null)
  const [navMin, setNavMin] = useState(() => LS.get('navMin') === '1')
  const [toast, setToast] = useState<{ n: number; text: string; undo?: () => void } | null>(null)
  const [menu, setMenu] = useState<MenuSpec | null>(null)

  // Per-Mac look: theme and accent colour.
  useEffect(() => {
    document.body.dataset.theme = LS.get('theme') === 'night' ? 'night' : 'paper'
    document.body.style.setProperty('--accBase', LS.get('accent') || '#b9b0ff')
  }, [])

  const ui: UI = {
    tab, ym, view, panel,
    go: (t) => { setTab(t); LS.set('tab', t); document.getElementById('main')?.scrollTo(0, 0) },
    setYm,
    setView: (p) => setViewState((v) => ({ ...v, ...p })),
    open: setPanel,
    close: () => setPanel((p) => (p && 'back' in p && p.back) || null),
    closeAll: () => setPanel(null),
    toast: (text, undo) => setToast((t) => ({ n: (t?.n ?? 0) + 1, text, undo })),
    menu: setMenu,
  }

  // Drop a statement anywhere on the window to import it. Every drag is cancelled here,
  // so a dropped file never replaces the page (Electron would open it).
  const [dragging, setDragging] = useState(false)
  const panelRef = useRef(panel)
  panelRef.current = panel
  useEffect(() => {
    let depth = 0
    const files = (e: DragEvent) => !!e.dataTransfer && Array.from(e.dataTransfer.types).includes('Files')
    const enter = (e: DragEvent) => { if (!files(e)) return; e.preventDefault(); depth++; setDragging(true) }
    const over = (e: DragEvent) => { e.preventDefault(); if (e.dataTransfer) e.dataTransfer.dropEffect = files(e) ? 'copy' : 'none' }
    const leave = (e: DragEvent) => { if (!files(e)) return; depth = Math.max(0, depth - 1); if (!depth) setDragging(false) }
    const drop = (e: DragEvent) => {
      e.preventDefault(); depth = 0; setDragging(false)
      const f = e.dataTransfer?.files?.[0]
      if (!f) return
      if (!isStatementFile(f.name)) { ui.toast('Drop a CSV, Excel or PDF statement to import it.'); return }
      const p = panelRef.current
      setMenu(null)
      setPanel({ kind: 'import', file: f, acct: p?.kind === 'import' ? p.acct : view.fAcct !== 'all' ? view.fAcct : tab === 'accounts' ? view.selAcct ?? undefined : undefined })
    }
    window.addEventListener('dragenter', enter); window.addEventListener('dragover', over)
    window.addEventListener('dragleave', leave); window.addEventListener('drop', drop)
    return () => {
      window.removeEventListener('dragenter', enter); window.removeEventListener('dragover', over)
      window.removeEventListener('dragleave', leave); window.removeEventListener('drop', drop)
    }
  }, [view.fAcct, view.selAcct, tab])

  const L = useMemo(() => makeLedger(data, ym), [data, ym, day])
  const def = TAB_DEFS[tab]
  const hero = def.hero?.(L, view) ?? null
  const A = data.household.nameA, B = data.household.nameB
  const title = tab === 'home' ? 'Hi, ' + A + ' & ' + B : TABS.find((t) => t[0] === tab)![1]
  const Header = def.Header, Body = def.Body

  const toggleNav = () => { setNavMin((m) => { LS.set('navMin', m ? '0' : '1'); return !m }) }

  return (
    <UICtx.Provider value={ui}>
      <div style={css('height:100vh;display:flex;background:#0b0b0c;color:#0b0b0c;font-size:15px;line-height:1.4')}>
        <aside style={sx('flex:none;height:100vh;box-sizing:border-box;padding:14px;transition:width .28s cubic-bezier(.2,.8,.2,1)', { width: navMin ? 96 : 236 })}>
          <div style={css('height:100%;box-sizing:border-box;background:#17171b;border-radius:28px;box-shadow:0 0 0 1px rgba(255,255,255,.08);padding:14px 10px;color:#ffffff;display:flex;flex-direction:column;gap:14px;overflow:hidden')}>
            {/* Room for the macOS traffic lights. */}
            <div style={css('height:22px;flex:none')} />
            <div style={sx('display:flex;align-items:center;height:46px', { justifyContent: navMin ? 'center' : 'space-between' })}>
              {!navMin && <span style={css("padding-left:13px;font:600 24px/1 'Geist',sans-serif;letter-spacing:-.03em;white-space:nowrap")}>Twofold</span>}
              <button className="h-island" onClick={toggleNav} aria-label={navMin ? 'Expand sidebar' : 'Collapse sidebar'} title={navMin ? 'Expand sidebar' : 'Collapse sidebar'} style={css('width:46px;height:46px;flex:none;border:none;border-radius:16px;background:transparent;color:#a9a7b8;display:grid;place-items:center;cursor:pointer')}><Icon d={ICON.panel} /></button>
            </div>
            <nav className="noscroll" style={css('display:flex;flex-direction:column;gap:2px;min-height:0;overflow-y:auto;flex:1')}>
              {TABS.map(([id, label]) => {
                const on = tab === id
                return (
                  <button key={id} className={on ? '' : 'h-island'} onClick={() => ui.go(id)} title={label} aria-current={on ? 'page' : undefined}
                    style={sx("display:flex;align-items:center;gap:12px;width:100%;height:46px;flex:none;padding:0 13px;border:none;border-radius:16px;font:500 15px 'Geist',sans-serif;cursor:pointer;text-align:left;white-space:nowrap;overflow:hidden;transition:background .15s", { background: on ? 'var(--accBase)' : 'transparent', color: on ? '#0b0b0c' : '#ffffff' })}>
                    <Icon d={ICON[id]} />
                    <span style={{ opacity: navMin ? 0 : 1, transition: 'opacity .18s' }}>{label}</span>
                  </button>
                )
              })}
            </nav>
            <button className="h-island" onClick={() => ui.open({ kind: 'settings' })} title="Settings"
              style={css("display:flex;align-items:center;gap:12px;width:100%;height:46px;flex:none;padding:0 13px;border:none;border-radius:16px;background:transparent;color:#a9a7b8;font:500 15px 'Geist',sans-serif;cursor:pointer;text-align:left;white-space:nowrap;overflow:hidden")}>
              <Icon d={ICON.settings} />
              <span style={{ opacity: navMin ? 0 : 1, transition: 'opacity .18s' }}>Settings</span>
            </button>
          </div>
        </aside>

        <main id="main" style={css('flex:1;min-width:0;display:flex;flex-direction:column;overflow-y:auto;height:100vh')}>
          <header data-stage="dark" style={css('padding:clamp(20px,3vw,32px) clamp(16px,3.5vw,44px) 0;color:#ffffff;display:flex;flex-direction:column;gap:clamp(22px,3vw,34px)')}>
            <div style={css('display:flex;flex-wrap:wrap;align-items:center;gap:12px 14px')}>
              <div style={css('display:flex;flex:none')}>
                <span style={css('width:46px;height:46px;border-radius:15px;background:var(--accBase);color:#0b0b0c;display:grid;place-items:center;font-weight:600;font-size:19px')}>{(A || '?')[0]}</span>
                <span style={css('width:46px;height:46px;margin-left:-10px;border-radius:15px;background:#fbf9ef;color:#0b0b0c;display:grid;place-items:center;font-weight:600;font-size:19px;box-shadow:0 0 0 3px #0b0b0c')}>{(B || '?')[0]}</span>
              </div>
              <div style={css('flex:1;min-width:140px')}>
                <h1 style={css("font:500 22px/1.2 'Geist',sans-serif;letter-spacing:-.01em;margin:0")}>{title}</h1>
                <div style={css('font-size:13.5px;color:#a9a7b8')}>{def.kicker(L)}<SyncNote /></div>
              </div>
              <div style={css('display:flex;align-items:center;gap:2px;background:#1d1d22;border-radius:16px;padding:0 4px;height:48px')}>
                <button className="h-dark" onClick={() => setYm(addM(ym, -1))} aria-label="Previous budget month" style={css('width:40px;height:40px;border:none;border-radius:12px;background:transparent;color:#ffffff;font-size:20px;cursor:pointer')}>‹</button>
                <span style={css("font:500 14px/1.15 'Geist',sans-serif;min-width:116px;text-align:center;display:flex;flex-direction:column;align-items:center")}>
                  {mLabel(ym)}
                  {L.period.range && <span style={css('font-size:11.5px;font-weight:400;color:#a9a7b8')}>{L.period.range}</span>}
                </span>
                <button className="h-dark" onClick={() => setYm(addM(ym, 1))} aria-label="Next budget month" style={css('width:40px;height:40px;border:none;border-radius:12px;background:transparent;color:#ffffff;font-size:20px;cursor:pointer')}>›</button>
              </div>
              <button onClick={() => ui.open({ kind: 'tx' })} style={css("font:500 15px 'Geist',sans-serif;padding:0 22px;height:48px;border-radius:16px;border:none;background:var(--accBase);color:#0b0b0c;cursor:pointer")}>+ Add entry</button>
            </div>
            {hero && <Hero h={hero} cur={L.cur} />}
            {Header && <Header L={L} />}
          </header>

          <div data-stage={def.stage} style={css('flex:1;display:flex;flex-direction:column;margin-top:8px')}>
            <div style={css('height:84px;flex:none;background:var(--bg);-webkit-mask-image:var(--blob);mask-image:var(--blob);-webkit-mask-size:1200px 84px;mask-size:1200px 84px;-webkit-mask-repeat:repeat-x;mask-repeat:repeat-x')} />
            <div style={css('flex:1;background:var(--bg);color:var(--ink);padding:12px clamp(16px,3.5vw,44px) 130px;margin-top:-1px')}>
              <div style={css('max-width:1280px')}><Body L={L} /></div>
            </div>
          </div>
        </main>
      </div>
      {/* Drag the window by its top edge (macOS hidden title bar). */}
      <div className="drag" aria-hidden="true" style={css('position:fixed;top:0;left:0;right:0;height:28px;z-index:40')} />
      <PanelHost L={L} />
      {menu && <Menu m={menu} close={() => setMenu(null)} />}
      {dragging && <DropTarget />}
      {toast && <Toast key={toast.n} text={toast.text} undo={toast.undo} lift={!!panel} close={() => setToast(null)} />}
    </UICtx.Provider>
  )
}

/** Shown while a file is dragged over the window. */
function DropTarget() {
  return (
    <div className="nodrag" aria-hidden="true" style={css('position:fixed;inset:0;z-index:90;pointer-events:none;background:rgba(11,11,12,.62);display:grid;place-items:center;padding:28px;box-sizing:border-box')}>
      <div style={css('width:100%;height:100%;box-sizing:border-box;border:2px dashed var(--accBase);border-radius:32px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;color:#ffffff;text-align:center')}>
        <span style={css('width:72px;height:72px;border-radius:24px;background:var(--accBase);color:#0b0b0c;display:grid;place-items:center')}><Icon d={ICON.import} size={32} /></span>
        <span style={css("font:500 30px 'Geist',sans-serif;letter-spacing:-.02em;margin-top:6px")}>Drop to import your statement</span>
        <span style={css('font-size:15px;color:#d9d7e4')}>CSV, Excel or PDF from your bank or card</span>
      </div>
    </div>
  )
}

/** "Deleted Groceries · Undo": black pill at the bottom, gone after 5 s. */
function Toast({ text, undo, lift, close }: { text: string; undo?: () => void; lift: boolean; close(): void }) {
  const [shown, setShown] = useState(false)
  useEffect(() => {
    const a = setTimeout(() => setShown(true), 20), b = setTimeout(() => setShown(false), 5000), c = setTimeout(close, 5300)
    return () => { clearTimeout(a); clearTimeout(b); clearTimeout(c) }
  }, [])
  return (
    <div role="status" className="nodrag" style={sx("position:fixed;left:50%;z-index:60;display:flex;align-items:center;gap:6px;max-width:min(560px,calc(100vw - 40px));box-sizing:border-box;padding:6px 6px 6px 20px;border-radius:20px;background:#0b0b0c;color:#ffffff;box-shadow:0 0 0 1px rgba(255,255,255,.12),0 12px 32px rgba(0,0,0,.28);font:500 14.5px 'Geist',sans-serif;transition:opacity .2s,bottom .2s,transform .28s cubic-bezier(.2,.8,.2,1)", { bottom: lift ? 104 : 28, opacity: shown ? 1 : 0, transform: 'translateX(-50%) translateY(' + (shown ? 0 : 16) + 'px)' })}>
      <span style={css('flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;padding-right:8px')}>{text}</span>
      {undo && <button onClick={() => { undo(); close() }} style={css("flex:none;height:40px;padding:0 18px;border:none;border-radius:14px;background:var(--accBase);color:#0b0b0c;font:500 14px 'Geist',sans-serif;cursor:pointer")}>Undo</button>}
      <button className="h-dark" onClick={close} aria-label="Dismiss" style={css('flex:none;width:40px;height:40px;border:none;border-radius:14px;background:transparent;color:#a9a7b8;font-size:18px;cursor:pointer')}>×</button>
    </div>
  )
}

/** Right-click menu: dark island at the pointer, closes on any click elsewhere, Escape or scrolling. */
function Menu({ m, close }: { m: MenuSpec; close(): void }) {
  const ref = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState({ x: m.x, y: m.y })
  useEffect(() => {
    const r = ref.current?.getBoundingClientRect()
    if (r) setPos({ x: Math.max(8, Math.min(m.x, innerWidth - r.width - 8)), y: Math.max(8, Math.min(m.y, innerHeight - r.height - 8)) })
    const down = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) close() }
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') close() }
    window.addEventListener('mousedown', down, true)
    window.addEventListener('keydown', key)
    window.addEventListener('blur', close)
    window.addEventListener('resize', close)
    window.addEventListener('wheel', close, true)
    return () => {
      window.removeEventListener('mousedown', down, true); window.removeEventListener('keydown', key)
      window.removeEventListener('blur', close); window.removeEventListener('resize', close); window.removeEventListener('wheel', close, true)
    }
  }, [m])
  return (
    <div ref={ref} role="menu" className="nodrag" onContextMenu={(e) => e.preventDefault()}
      style={sx('position:fixed;z-index:70;min-width:168px;padding:6px;border-radius:18px;background:#17171b;box-shadow:0 0 0 1px rgba(255,255,255,.1),0 14px 36px rgba(0,0,0,.3);display:flex;flex-direction:column;gap:2px', { left: pos.x, top: pos.y })}>
      {m.items.map((it) => (
        <button key={it.label} role="menuitem" className="h-menu" onClick={() => { close(); it.run() }}
          style={sx("height:40px;padding:0 14px;border:none;border-radius:12px;background:transparent;font:500 14.5px 'Geist',sans-serif;text-align:left;cursor:pointer", { color: it.bad ? '#ff8f85' : '#ffffff' })}>{it.label}</button>
      ))}
    </div>
  )
}

function SyncNote() {
  const { syncing, demo } = useStore()
  if (demo) return <span> · preview with sample data</span>
  return syncing ? <span> · syncing…</span> : null
}

/** Black header figure, stats and bar chart. */
function Hero({ h, cur }: { h: HeroSpec; cur: string }) {
  const bars = h.bars ?? []
  const many = bars.length > 16
  const r = many ? '5px 5px 2px 2px' : '12px 12px 5px 5px'
  return (
    <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:28px 40px;align-items:end')}>
      <div style={css('min-width:0')}>
        <div style={css('font-size:14px;color:#a9a7b8')}>{h.label}</div>
        <div style={css('display:flex;align-items:baseline;gap:10px;margin-top:6px')}>
          {h.cur && <span style={css("font:500 22px 'Geist',sans-serif;color:#a9a7b8")}>{cur}</span>}
          <span style={sx("font-family:'Geist',sans-serif;font-weight:500;line-height:.95;letter-spacing:-.045em", { fontSize: h.cur ? 'clamp(56px,8.5vw,108px)' : 'clamp(44px,6.5vw,84px)', color: h.fg })}>{h.num}</span>
        </div>
        {h.sub && <div style={css('font-size:15px;color:#d9d7e4;margin-top:14px;max-width:500px;text-wrap:pretty')}>{h.sub}</div>}
        {!!h.stats?.length && (
          <div style={css('display:flex;flex-wrap:wrap;gap:14px 30px;margin-top:22px')}>
            {h.stats.map(([k, v]) => (
              <div key={k}><div style={css('font-size:12.5px;color:#a9a7b8')}>{k}</div><div style={css("font:500 18px 'Geist',sans-serif;letter-spacing:-.01em;white-space:nowrap")}>{v}</div></div>
            ))}
          </div>
        )}
      </div>
      {bars.length > 1 && (
        <div style={sx('display:flex;height:230px;min-width:0', { gap: many ? 3 : 8 })}>
          {bars.map((b, i) => (
            <div key={i} title={b.title} style={css('flex:1;min-width:0;display:flex;flex-direction:column;align-items:center;gap:6px')}>
              <span style={sx('height:26px;box-sizing:border-box;background:#fbf9ef;color:#0b0b0c;font-size:12px;font-weight:500;line-height:26px;padding:0 9px;border-radius:9px;white-space:nowrap', { opacity: b.tag ? 1 : 0, alignSelf: i === 0 ? 'flex-start' : i === bars.length - 1 ? 'flex-end' : 'center' })}>{b.tag || ' '}</span>
              <div style={css('flex:1;width:100%;display:flex;align-items:flex-end;gap:3px')}>
                <div style={sx('flex:1;transition:height .4s', { height: b.h, background: b.bg, borderRadius: r })} />
                {b.h2 && <div style={sx('flex:1;transition:height .4s', { height: b.h2, background: b.bg2, borderRadius: r })} />}
              </div>
              <span style={css('font-size:12.5px;color:#d9d7e4;height:18px;white-space:nowrap')}>{b.label}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
