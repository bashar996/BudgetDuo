// Plan ahead: 30-day cash forecast, what moves the balance, trips and events,
// and planned purchases that wait for both of you to say yes.
import type { Ledger } from '../data/ledger'
import { useStore } from '../data/store'
import { css, sx } from '../lib/css'
import { addDays, addM, dLab, mLabel } from '../lib/dates'
import { pc } from '../lib/money'
import { useUI, type HeroBar, type TabDef } from '../shell/ui'

const LAV = 'var(--accBase)', CRM = '#fbf9ef', RED = '#ff8f85'

/** The design's 30-day forecast numbers. */
function plan(L: Ledger) {
  const fc = L.forecast(), series = fc.series, cushion = L.cushion, f = L.f
  const sLo = Math.min(0, ...series), sHi = Math.max(cushion, ...series) * 1.05
  const minV = Math.min(...series), minI = series.indexOf(minV), low = minV < cushion
  const dAt = (i: number) => addDays(L.today, i)
  const note = !L.accounts.length
    ? 'Add an account and your bills, and the next 30 days appear here.'
    : low
      ? 'Heads up: the balance dips to ' + f(Math.round(minV)) + ' around ' + dLab(dAt(minI)) + ', below your ' + f(cushion) + ' cushion. Nudging a purchase past payday keeps things comfortable.'
      : 'You stay above your ' + f(cushion) + ' cushion the whole way. The lowest point is ' + f(Math.round(minV)) + ' on ' + dLab(dAt(minI)) + '.'
  return { ...fc, sLo, sHi, minV, minI, low, dAt, note }
}

const title = "font:500 22px 'Geist',sans-serif;letter-spacing:-.01em"
const empty = 'padding:8px 0;font-size:14px;color:var(--mute)'
const outlineBtn = "flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 16px;height:44px;border-radius:22px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);cursor:pointer"
const linkBtn = "background:none;border:none;padding:0;font:500 16px 'Geist',sans-serif;color:var(--ink);cursor:pointer;text-align:left"

function Body({ L }: { L: Ledger }) {
  const { act } = useStore()
  const { open } = useUI()
  const P = plan(L), f = L.f
  const surplus = Math.max(0, L.leftAssign)

  return (
    <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:30px 40px;align-items:start')}>
      <section>
        <span style={css(title)}>What moves the balance</span>
        {P.events.slice(0, 8).map((e, k) => (
          <div key={k} style={css('display:flex;align-items:center;gap:12px;padding:11px 0;border-bottom:1px solid var(--line)')}>
            <span style={sx('font-size:13px;width:86px;flex:none', { color: e.late ? 'var(--bad)' : 'var(--mute)' })}>{e.late ? 'Overdue' : e.i === 0 ? 'Today' : dLab(e.d)}</span>
            <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
              <span style={css('font-size:16px;font-weight:500')}>{e.name}</span>
              <span style={css('font-size:12.5px;color:var(--mute)')}>balance {f(Math.round(P.series[e.i]))}</span>
            </span>
            <span style={sx('font-size:15px;font-weight:500;white-space:nowrap', { color: e.inc ? 'var(--good)' : 'var(--ink)' })}>{(e.inc ? '+' : '') + f(e.amt)}</span>
          </div>
        ))}
        {!P.events.length && <div style={css(empty)}>Nothing scheduled in the next 30 days.</div>}
      </section>

      <section>
        <div style={css('display:flex;justify-content:space-between;align-items:center;gap:10px')}>
          <span style={css(title)}>Trips &amp; events</span>
          <button onClick={() => open({ kind: 'item', item: 'event' })} style={css(outlineBtn)}>+ New</button>
        </div>
        {L.data.trips.map((t) => {
          const l = t.budget - t.spent
          return (
            <div key={t.id} style={css('padding:14px 0 12px;border-bottom:1px solid var(--line)')}>
              <div style={css('display:flex;justify-content:space-between;gap:12px;align-items:baseline')}>
                <button onClick={() => open({ kind: 'item', item: 'event', id: t.id })} style={css(linkBtn)}>{t.name}</button>
                <span style={css('font-size:13px;color:var(--mute)')}>{t.when}</span>
              </div>
              <div style={css('height:5px;border-radius:3px;background:var(--track);margin-top:10px')}>
                <div style={sx('height:100%;border-radius:3px;transition:width .4s', { width: pc(t.spent / (t.budget || 1)), background: l < 0 ? 'var(--bad)' : 'var(--acc)' })} />
              </div>
              <div style={css('display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;margin-top:8px')}>
                <span style={css('font-size:13px;color:var(--mute)')}>{f(t.spent)} of {f(t.budget)} · {l < 0 ? f(-l) + ' over' : f(l) + ' to go'}</span>
                <button onClick={() => open({ kind: 'contrib', trip: t })} style={css("font:500 13.5px 'Geist',sans-serif;padding:0 16px;height:44px;border-radius:22px;border:none;background:var(--btn);color:var(--btnInk);cursor:pointer")}>Log spend</button>
              </div>
            </div>
          )
        })}
        {!L.data.trips.length && <div style={css(empty)}>No trips or events planned.</div>}
      </section>

      <section style={css('grid-column:1/-1;display:flex;flex-direction:column;gap:12px')}>
        <div style={css('display:flex;justify-content:space-between;align-items:center;gap:12px')}>
          <div>
            <div style={css(title)}>Planned purchases</div>
            <div style={css('font-size:13px;color:var(--mute)')}>Big buys wait until you’ve both said yes.</div>
          </div>
          <button onClick={() => open({ kind: 'item', item: 'planned' })} style={css(outlineBtn)}>+ Add</button>
        </div>
        <div style={css('display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,250px),1fr));gap:10px')}>
          {L.data.planned.map((p) => {
            const n = surplus > 0 ? Math.ceil(p.cost / surplus) : 0
            const verdict = L.safe >= p.cost ? 'Fits in this month’s safe-to-spend.'
              : n ? 'Set aside ' + f(Math.ceil(p.cost / n)) + ' a month and it’s yours by ' + mLabel(addM(L.calYm, n), true) + '.'
                : 'No spare room yet — free up a category first.'
            const vote = "font:500 13.5px 'Geist',sans-serif;padding:0 14px;height:44px;border-radius:22px;border:1.5px solid var(--ink);cursor:pointer"
            return (
              <div key={p.id} style={css('background:var(--card);border-radius:24px;padding:20px;display:flex;flex-direction:column;gap:8px')}>
                <button onClick={() => open({ kind: 'item', item: 'planned', id: p.id })} style={css(linkBtn)}>{p.name}</button>
                <div style={css('font-size:30px;letter-spacing:-.03em;line-height:1')}>{f(p.cost)}</div>
                <div style={css('font-size:13px;color:var(--mute);text-wrap:pretty;flex:1')}>{verdict}</div>
                <div style={css('display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-top:6px')}>
                  <button onClick={() => act.vote(p, 'A')} aria-pressed={p.A} style={sx(vote, { background: p.A ? 'var(--a)' : 'transparent', color: p.A ? '#0b0b0c' : 'var(--ink)' })}>{(p.A ? '✓ ' : '') + L.A}</button>
                  <button onClick={() => act.vote(p, 'B')} aria-pressed={p.B} style={sx(vote, { background: p.B ? 'var(--b)' : 'transparent', color: p.B ? 'var(--bg)' : 'var(--ink)' })}>{(p.B ? '✓ ' : '') + L.B}</button>
                  {p.A && p.B && (
                    <button onClick={() => act.buyPlanned(p, L.mainAcct)} style={css("font:500 13.5px 'Geist',sans-serif;padding:0 14px;height:44px;border-radius:22px;border:none;background:var(--acc);color:var(--accInk);cursor:pointer")}>Mark bought</button>
                  )}
                </div>
              </div>
            )
          })}
          {!L.data.planned.length && <div style={css(empty)}>No planned purchases yet.</div>}
        </div>
      </section>
    </div>
  )
}

export const planTab: TabDef = {
  id: 'plan',
  stage: 'cream',
  kicker: () => 'Forecast, trips and big purchases',
  hero: (L) => {
    const P = plan(L), f = L.f, cushion = L.cushion
    const bars: HeroBar[] = P.series.map((v, i) => ({
      h: pc(Math.max(0.03, (v - P.sLo) / (P.sHi - P.sLo || 1))),
      bg: v < cushion ? RED : i === 0 ? LAV : CRM,
      label: i % 5 === 0 ? String(P.dAt(i).getDate()) : '',
      tag: i === P.minI ? f(Math.round(v)) : '',
      title: dLab(P.dAt(i)) + ' · ' + f(Math.round(v)),
    }))
    return {
      label: 'Cash in 30 days', cur: true, num: L.num(Math.round(P.series[30])),
      fg: P.low && L.accounts.length ? RED : '#ffffff', sub: P.note,
      stats: [['Today', f(P.cash)], ['Lowest point', f(Math.round(P.minV))], ['Your cushion', f(cushion)]],
      bars,
    }
  },
  Body,
}
