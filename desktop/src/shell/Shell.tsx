import { useEffect, useMemo, useState } from 'react'
import { css, sx } from '../lib/css'
import { addM, mLabel } from '../lib/dates'
import { makeLedger } from '../data/ledger'
import { useStore } from '../data/store'
import { Icon, ICON } from './icons'
import { TABS, UICtx, type HeroSpec, type Panel, type TabId, type UI, type ViewState } from './ui'
import { TAB_DEFS } from '../tabs'
import { PanelHost } from '../panels/PanelHost'
import { ymOf } from '../lib/dates'

const LS = {
  get(k: string) { try { return localStorage.getItem('twofold:' + k) } catch { return null } },
  set(k: string, v: string) { try { localStorage.setItem('twofold:' + k, v) } catch { /* private mode */ } },
}

export function Shell() {
  const { data } = useStore()
  const [tab, setTab] = useState<TabId>(() => (LS.get('tab') as TabId) || 'home')
  const [ym, setYm] = useState(() => ymOf(new Date()))
  const [view, setViewState] = useState<ViewState>({ q: '', fWho: 'all', fCat: 'all', fAcct: 'all', selAcct: null })
  const [panel, setPanel] = useState<Panel | null>(null)
  const [navMin, setNavMin] = useState(() => LS.get('navMin') === '1')

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
    close: () => setPanel(null),
  }

  const L = useMemo(() => makeLedger(data, ym), [data, ym])
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
                <button className="h-dark" onClick={() => setYm(addM(ym, -1))} aria-label="Previous month" style={css('width:40px;height:40px;border:none;border-radius:12px;background:transparent;color:#ffffff;font-size:20px;cursor:pointer')}>‹</button>
                <span style={css("font:500 14px 'Geist',sans-serif;min-width:116px;text-align:center")}>{mLabel(ym)}</span>
                <button className="h-dark" onClick={() => setYm(addM(ym, 1))} aria-label="Next month" style={css('width:40px;height:40px;border:none;border-radius:12px;background:transparent;color:#ffffff;font-size:20px;cursor:pointer')}>›</button>
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
    </UICtx.Provider>
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
