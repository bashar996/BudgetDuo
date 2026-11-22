// Net worth (cream): everything you own (accounts, investments, assets) minus everything
// you owe, with the six-month history in the header.
// Design: round-3/Tandem Budget.dc.html, template `is.worth`, `worth` and HV.worth in renderVals().
import type { HeroBar, TabDef } from '../shell/ui'
import { useUI } from '../shell/ui'
import type { Ledger } from '../data/ledger'
import type { Tx } from '../data/types'
import { ACCOUNT_TYPES, assetKind } from '../data/catalog'
import { css, sx } from '../lib/css'
import { addM, dim, MN, pad } from '../lib/dates'
import { pc, sum } from '../lib/money'

const LAV = 'var(--accBase)', CRM = '#fbf9ef'
const H22 = css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")
const HEAD = css('display:flex;justify-content:space-between;align-items:center;gap:10px;padding-bottom:6px')
const PILL = css("flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 16px;height:44px;border-radius:22px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);cursor:pointer")
const ROW_BTN = css('display:flex;align-items:center;gap:12px;width:100%;padding:10px 0;background:none;border:none;border-bottom:1px solid var(--line);font:inherit;color:inherit;cursor:pointer;text-align:left')
const TILE = css('width:44px;height:44px;flex:none;border-radius:13px;background:var(--soft);display:grid;place-items:center;font-weight:600;font-size:17px')
const EMPTY = css('padding:8px 0;font-size:14px;color:var(--mute);text-wrap:pretty')

/** Net worth at the end of each of the last six months (the last one is now):
 *  today's figure minus everything entered after that month ended. Loans and
 *  assets are kept at today's value since entries don't move them. */
function netHist(L: Ledger) {
  const net = L.assets - L.liab
  const eff = (t: Tx) =>
    (L.acctBy[t.acct] ? (t.type === 'inc' ? t.amt : -t.amt) : 0) + (t.type === 'xfer' && t.to && L.acctBy[t.to] ? t.amt : 0)
  return [5, 4, 3, 2, 1, 0].map((k) => {
    if (!k) return net
    const m = addM(L.curYm, -k), end = m + '-' + pad(dim(m))
    return net - sum(L.data.tx.filter((t) => t.date > end), eff)
  })
}

/** "+AED 12,000 · +23%" */
const gainText = (L: Ledger, g: number, cost: number) =>
  (g >= 0 ? '+' : '') + L.f(g) + ' · ' + (g >= 0 ? '+' : '−') + Math.abs(Math.round((g / cost) * 100)) + '%'

function Body({ L }: { L: Ledger }) {
  const ui = useUI()
  const { f } = L
  const own = L.assets
  const owe = L.accounts.filter((a) => a.balance < 0).map((a) => ({ id: a.id, name: a.name, meta: (ACCOUNT_TYPES[a.type] ?? ACCOUNT_TYPES.current)[0], bal: -a.balance }))
    .concat(L.data.debts.map((x) => ({ id: x.id, name: x.name, meta: x.apr + '% interest', bal: x.balance })))

  return (
    <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:30px 40px;align-items:start')}>
      <div style={css('display:flex;flex-direction:column;gap:30px;min-width:0')}>
        <section>
          <div style={css('display:flex;justify-content:space-between;align-items:baseline;gap:10px')}>
            <span style={H22}>What you own</span>
            <span style={css('font-size:13px;color:var(--mute)')}>{f(own)}</span>
          </div>
          <div style={css('display:flex;gap:3px;height:16px;margin:14px 0 6px')}>
            {L.ownGroups.filter((s) => s.v > 0).map((s) => (
              <div key={s.label} title={s.label + ' · ' + f(s.v)} style={sx('flex-basis:0;min-width:6px;border-radius:5px', { flexGrow: s.v, background: s.color })} />
            ))}
          </div>
          {L.ownGroups.map((r) => (
            <div key={r.label} style={css('display:flex;align-items:center;gap:12px;padding:11px 0;border-bottom:1px solid var(--line)')}>
              <span style={sx('width:14px;height:14px;flex:none;border-radius:5px', { background: r.color })} />
              <span style={css('flex:1;min-width:0;font-size:16px')}>{r.label}</span>
              <span style={css('font-size:13px;color:var(--mute)')}>{Math.round((r.v / (own || 1)) * 100) + '%'}</span>
              <span style={css('font-size:15px;font-weight:500;min-width:96px;text-align:right;white-space:nowrap')}>{f(r.v)}</span>
            </div>
          ))}
        </section>
        <section>
          <div style={HEAD}>
            <span style={H22}>What you owe</span>
            <button onClick={() => ui.go('goals')} style={PILL}>Payoff plan →</button>
          </div>
          {owe.map((o) => (
            <div key={o.id} style={css('display:flex;align-items:center;gap:12px;padding:11px 0;border-bottom:1px solid var(--line)')}>
              <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
                <span style={css('font-size:16px;font-weight:500')}>{o.name}</span>
                <span style={css('font-size:13px;color:var(--mute)')}>{o.meta}</span>
              </span>
              <span style={css('font-size:15px;font-weight:500;white-space:nowrap')}>{f(o.bal)}</span>
            </div>
          ))}
          {!owe.length && <div style={css('padding:8px 0;font-size:14px;color:var(--mute)')}>Nothing owed.</div>}
          <div style={css('display:flex;justify-content:space-between;gap:10px;padding-top:12px;font-size:15px;font-weight:500')}><span>Total owed</span><span>{f(L.liab)}</span></div>
        </section>
      </div>

      <div style={css('display:flex;flex-direction:column;gap:30px;min-width:0')}>
        <section>
          <div style={HEAD}>
            <span style={H22}>Assets</span>
            <button onClick={() => ui.open({ kind: 'asset' })} style={PILL}>+ Add asset</button>
          </div>
          {L.holdings.map((x) => (
            <button key={x.id} onClick={() => ui.open({ kind: 'asset', id: x.id })} style={ROW_BTN}>
              <span style={TILE}>{assetKind(x.kind)[0]}</span>
              <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
                <span style={css('font-size:16px;font-weight:500')}>{x.name}</span>
                <span style={css('font-size:13px;color:var(--mute)')}>{assetKind(x.kind)}</span>
              </span>
              <span style={css('font-size:15px;font-weight:500;white-space:nowrap')}>{f(x.value)}</span>
            </button>
          ))}
          {!L.holdings.length && <div style={EMPTY}>Add a home, a car, gold or anything else of value that doesn’t sit in an account.</div>}
        </section>
        <section>
          <div style={HEAD}>
            <span style={H22}>Investments</span>
            <button onClick={() => ui.open({ kind: 'acct', preset: 'invest' })} style={PILL}>+ Add investment</button>
          </div>
          {L.investments.map((a) => (
            <button key={a.id} onClick={() => ui.open({ kind: 'acct', acct: L.data.accounts.find((x) => x.id === a.id) })} style={ROW_BTN}>
              <span style={TILE}>{(a.name || '?')[0].toUpperCase()}</span>
              <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
                <span style={css('font-size:16px;font-weight:500')}>{a.name}</span>
                <span style={css('font-size:13px;color:var(--mute)')}>{[L.whoName[a.who], a.bank].filter(Boolean).join(' · ')}</span>
              </span>
              <span style={css('display:flex;flex-direction:column;align-items:flex-end')}>
                <span style={css('font-size:15px;font-weight:500;white-space:nowrap')}>{f(a.balance)}</span>
                <span style={sx('font-size:12.5px;white-space:nowrap', { color: a.gain === null ? 'var(--mute)' : a.gain >= 0 ? 'var(--good)' : 'var(--bad)' })}>
                  {a.gain === null ? 'Add what you put in to see the gain' : gainText(L, a.gain, a.cost!)}
                </span>
              </span>
            </button>
          ))}
          {!L.investments.length && <div style={EMPTY}>Add a brokerage, fund or long-term plan with what it’s worth today.</div>}
        </section>
      </div>
    </div>
  )
}

export const worthTab: TabDef = {
  id: 'worth',
  stage: 'cream',
  kicker: () => 'Everything you own, minus what you owe',
  hero: (L) => {
    const { f } = L
    const net = L.assets - L.liab
    const hist = netHist(L)
    const lo = Math.min(...hist), hLo = lo - Math.abs(lo) * 0.06, hHi = Math.max(...hist)
    const m0 = L.today.getMonth()
    const bars: HeroBar[] = hist.map((v, i) => ({
      h: pc(Math.max(0.08, (v - hLo) / (hHi - hLo || 1))),
      bg: i === 5 ? LAV : CRM,
      label: MN[(m0 - 5 + i + 12) % 12].slice(0, 3),
      tag: i === 5 ? f(v) : '',
      title: f(Math.round(v)),
    }))
    return {
      label: 'Net worth',
      cur: true,
      num: L.num(net),
      fg: '#ffffff',
      sub: (net - hist[4] >= 0 ? '+' : '') + f(net - hist[4]) + ' since last month',
      stats: [['You own', f(L.assets)], ['You owe', f(L.liab)], ['Investment gain', L.invGain === null ? '—' : (L.invGain >= 0 ? '+' : '') + f(L.invGain)]],
      bars,
    }
  },
  Body,
}
