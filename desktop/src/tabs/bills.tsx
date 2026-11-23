// Bills: month calendar plus the list of bills with Pay / Paid.
import { css, sx } from '../lib/css'
import { addDays, dim, isoD, isoOf, MN, WD, mLabel } from '../lib/dates'
import { daysBetween } from '../lib/period'
import { sum } from '../lib/money'
import type { Ledger } from '../data/ledger'
import { useStore } from '../data/store'
import { useUI, type TabDef } from '../shell/ui'

const LEGEND: [string, string][] = [
  ['due', 'background:var(--acc)'],
  ['paid', 'background:var(--soft)'],
  ['overdue', 'background:var(--bad)'],
  ['payday', 'border:1.5px solid var(--ink);box-sizing:border-box'],
  ['today', 'background:var(--ink)'],
]

function Calendar({ L }: { L: Ledger }) {
  const { ym, isCur, curYm, billsM, H, period, todayIso, start } = L
  // The budget month's days from its first day, weekday-aligned (it may span two calendar months).
  const from = isoD(period.from)
  const cells: { d: number | ''; mon: string; bd: string; bg: string; fg: string; dots: number }[] = []
  for (let i = 0; i < from.getDay(); i++) cells.push({ d: '', mon: '', bd: 'transparent', bg: 'transparent', fg: 'var(--mute)', dots: 0 })
  for (let i = 0; i < period.days; i++) {
    const dt = addDays(from, i), iso = isoOf(dt), d = dt.getDate(), dm = dim(iso.slice(0, 7))
    const bs = billsM.filter((b) => b.due === iso), due = bs.some((b) => !b.isPaid), late = due && (ym < curYm || (isCur && iso < todayIso))
    const pay = H.incomes.some((x) => x.amt > 0 && Math.min(x.day, dm) === d), t = isCur && iso === todayIso
    cells.push({
      d, dots: bs.length,
      // Name the month where it changes (and on the first day when it isn't the 1st).
      mon: start > 1 && (i === 0 || d === 1) ? MN[dt.getMonth()].slice(0, 3) : '',
      bd: pay ? 'var(--ink)' : 'transparent',
      bg: t ? 'var(--ink)' : late ? 'var(--bad)' : due ? 'var(--acc)' : bs.length ? 'var(--soft)' : 'transparent',
      fg: t ? 'var(--bg)' : late ? '#ffffff' : 'var(--ink)',
    })
  }
  return (
    <section style={css('background:var(--card);border-radius:28px;padding:22px')}>
      <div style={css('display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:5px')}>
        {WD.map((w) => <div key={w} style={css('font-size:12px;color:var(--mute);text-align:center;padding-bottom:4px')}>{w[0]}</div>)}
        {cells.map((c, i) => (
          <div key={i} style={sx('aspect-ratio:1;border-radius:12px;padding:6px;box-sizing:border-box;display:flex;flex-direction:column;justify-content:space-between;overflow:hidden', { border: '1.5px solid ' + c.bd, background: c.bg, color: c.fg })}>
            <span style={css('font-size:12.5px;font-weight:500;line-height:1;white-space:nowrap')}>{c.d}{c.mon && <span style={css('font-weight:400;opacity:.7')}> {c.mon}</span>}</span>
            <span style={css('display:flex;gap:3px;flex-wrap:wrap')}>
              {Array.from({ length: c.dots }, (_, k) => <span key={k} style={css('width:6px;height:6px;border-radius:50%;background:currentColor')} />)}
            </span>
          </div>
        ))}
      </div>
      <div style={css('display:flex;flex-wrap:wrap;gap:8px 16px;margin-top:16px;font-size:12.5px;color:var(--mute)')}>
        {LEGEND.map(([label, s]) => (
          <span key={label} style={css('display:flex;align-items:center;gap:6px')}><span style={css('width:12px;height:12px;border-radius:4px;' + s)} />{label}</span>
        ))}
      </div>
    </section>
  )
}

function Body({ L }: { L: Ledger }) {
  const { act } = useStore()
  const { open } = useUI()
  const { ym, curYm, isCur, todayIso } = L
  return (
    <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:30px 40px;align-items:start')}>
      <Calendar L={L} />
      <section>
        <div style={css('display:flex;justify-content:space-between;align-items:center;gap:10px;padding-bottom:6px')}>
          <span style={css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")}>Bills &amp; subscriptions</span>
          <button onClick={() => open({ kind: 'item', item: 'bill' })} style={css("flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 16px;height:44px;border-radius:22px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);cursor:pointer")}>+ New bill</button>
        </div>
        {L.billsM.map((b) => {
          const n = daysBetween(todayIso, b.due)
          const st = b.isPaid ? 'Paid' : ym < curYm ? 'Missed' : isCur ? (n < 0 ? 'Overdue' : n === 0 ? 'Due today' : n === 1 ? 'Tomorrow' : 'In ' + n + ' days') : 'Scheduled'
          const bad = st === 'Overdue' || st === 'Missed'
          return (
            <div key={b.id} style={css('display:flex;align-items:center;gap:12px;padding:10px 0;border-bottom:1px solid var(--line)')}>
              <span style={css('width:44px;height:44px;flex:none;border-radius:13px;background:var(--ink);color:var(--bg);display:flex;flex-direction:column;align-items:center;justify-content:center;line-height:1.05')}>
                <span style={css('font-size:16px;font-weight:600')}>{b.d}</span><span style={css('font-size:10px')}>{MN[+b.due.slice(5, 7) - 1].slice(0, 3)}</span>
              </span>
              <button onClick={() => open({ kind: 'item', item: 'bill', id: b.id })} style={css('flex:1;min-width:0;display:flex;flex-direction:column;background:none;border:none;padding:0;font:inherit;color:inherit;text-align:left;cursor:pointer')}>
                <span style={css('font-size:16px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:100%')}>{b.name}</span>
                <span style={sx('font-size:13px', { color: bad ? 'var(--bad)' : 'var(--mute)' })}>{st} · {L.f(b.amt)}</span>
              </button>
              <button onClick={() => act.togglePaid(b, b.pm, L.mainAcct)} style={sx("flex:none;font:500 13.5px 'Geist',sans-serif;padding:0 16px;height:44px;border-radius:22px;cursor:pointer", {
                border: '1.5px solid ' + (b.isPaid ? 'var(--chip)' : 'var(--btn)'),
                background: b.isPaid ? 'transparent' : 'var(--btn)',
                color: b.isPaid ? 'var(--ink)' : 'var(--btnInk)',
              })}>{b.isPaid ? 'Paid' : 'Pay'}</button>
            </div>
          )
        })}
        {!L.billsM.length && <div style={css('padding:8px 0;font-size:14px;color:var(--mute)')}>No bills yet. Add rent, utilities and subscriptions.</div>}
      </section>
    </div>
  )
}

export const billsTab: TabDef = {
  id: 'bills',
  stage: 'cream',
  kicker: () => 'Bills & subscriptions',
  hero: (L) => {
    const paid = sum(L.billsM.filter((b) => b.isPaid), (b) => b.amt)
    const due = sum(L.billsM.filter((b) => !b.isPaid), (b) => b.amt)
    const subsMo = sum(L.data.bills.filter((b) => b.sub), (b) => b.amt)
    return {
      label: 'Still due · ' + mLabel(L.ym), cur: true, num: L.num(due), fg: 'var(--accBase)',
      sub: L.f(paid) + ' paid so far across ' + L.billsM.length + ' bills.',
      stats: [['This month', L.f(paid + due)], ['Paid', L.f(paid)], ['Subscriptions a year', L.f(subsMo * 12)]],
    }
  },
  Body,
}
