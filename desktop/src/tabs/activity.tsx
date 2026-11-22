// Activity: every entry this month, searchable and filterable from the black header.
import { css, sx } from '../lib/css'
import { dLab, isoD, mLabel } from '../lib/dates'
import { download, sum, toCsv } from '../lib/money'
import type { Ledger } from '../data/ledger'
import type { Tx, Who } from '../data/types'
import { useUI, type Panel, type TabDef, type ViewState } from '../shell/ui'
import { EntryRow } from '../shell/entry'

/** One entry as a list row (the design's txRow). */
export function txRow(L: Ledger, t: Tx) {
  const c = L.catOf(t.cat), isInc = t.type === 'inc', x = t.type === 'xfer'
  return {
    ini: ((t.name || '?').trim()[0] || '?').toUpperCase(),
    name: t.name + (isInc ? ' · ' + L.whoName[t.who] : ''),
    sub: x ? L.aName(t.acct) + ' → ' + L.aName(t.to) : c.name + ' · ' + L.aName(t.acct) + (t.note ? ' · ' + t.note : ''),
    who: x ? '↔' : (L.whoName[t.who] || '?')[0],
    whoTitle: x ? 'Transfer' : L.whoName[t.who],
    whoCol: x ? 'var(--line)' : L.whoCol[t.who],
    amt: (isInc ? '+' : '') + L.f(t.amt),
    amtColor: isInc ? 'var(--good)' : x ? 'var(--mute)' : 'var(--ink)',
  }
}

/** This month's entries after the header's search and filters, newest first. */
export function filtered(L: Ledger, v: ViewState) {
  const q = v.q.trim().toLowerCase()
  return L.mtx.filter((t) =>
    (v.fWho === 'all' || t.who === v.fWho) &&
    (v.fCat === 'all' || t.cat === v.fCat) &&
    (v.fAcct === 'all' || t.acct === v.fAcct || t.to === v.fAcct) &&
    (!q || (t.name + ' ' + (t.note || '') + ' ' + L.catOf(t.cat).name).toLowerCase().includes(q)),
  ).sort(L.desc)
}

const CHIP = "height:44px;padding:0 15px;border-radius:22px;font:500 13.5px 'Geist',sans-serif;cursor:pointer"
function Chip({ label, on, onClick, scroll }: { label: string; on: boolean; onClick(): void; scroll?: boolean }) {
  return (
    <button onClick={onClick} style={sx(CHIP, {
      flex: scroll ? 'none' : undefined,
      border: '1px solid ' + (on ? 'var(--ink)' : 'var(--chip)'),
      background: on ? 'var(--ink)' : 'transparent',
      color: on ? 'var(--bg)' : 'var(--ink)',
    })}>{label}</button>
  )
}

function Header({ L }: { L: Ledger }) {
  const { view, setView, open } = useUI()
  const exportCsv = () => {
    const rows: (string | number)[][] = [['Date', 'Name', 'Category', 'Who', 'Type', 'Amount', 'Note']]
    filtered(L, view).forEach((t) => rows.push([t.date, t.name, t.cat, t.who, t.type, t.amt, t.note || '']))
    download('twofold-' + L.ym + '.csv', toCsv(rows), 'text/csv')
  }
  const who: ['all' | Who, string][] = [['all', 'Everyone'], ['A', L.A], ['B', L.B], ['J', 'Joint']]
  return (
    <div style={css('display:flex;flex-direction:column;gap:10px')}>
      <div style={css('display:flex;flex-wrap:wrap;gap:10px')}>
        <input className="h-focus" placeholder="Search name, note or category" value={view.q} onChange={(e) => setView({ q: e.target.value })}
          style={css("flex:1;min-width:200px;box-sizing:border-box;height:50px;padding:0 18px;border:none;border-radius:18px;background:#1d1d22;color:#ffffff;font:500 15px 'Geist',sans-serif;outline:none")} />
        <button className="h-dark" onClick={() => open({ kind: 'import', acct: view.fAcct !== 'all' ? view.fAcct : undefined })} style={css("font:500 14px 'Geist',sans-serif;padding:0 18px;height:50px;border-radius:18px;border:1px solid rgba(255,255,255,.3);background:transparent;color:#ffffff;cursor:pointer")}>Import statement</button>
        <button className="h-dark" onClick={exportCsv} style={css("font:500 14px 'Geist',sans-serif;padding:0 18px;height:50px;border-radius:18px;border:1px solid rgba(255,255,255,.3);background:transparent;color:#ffffff;cursor:pointer")}>Export CSV</button>
      </div>
      <div style={css('display:flex;flex-wrap:wrap;gap:6px')}>
        {who.map(([k, label]) => <Chip key={k} label={label} on={view.fWho === k} onClick={() => setView({ fWho: k })} />)}
      </div>
      <div className="noscroll" style={css('display:flex;gap:6px;overflow-x:auto;scrollbar-width:none')}>
        <Chip scroll label="All accounts" on={view.fAcct === 'all'} onClick={() => setView({ fAcct: 'all' })} />
        {L.accounts.filter((a) => a.type !== 'invest').map((a) => <Chip scroll key={a.id} label={a.name} on={view.fAcct === a.id} onClick={() => setView({ fAcct: a.id })} />)}
      </div>
      <div className="noscroll" style={css('display:flex;gap:6px;overflow-x:auto;scrollbar-width:none')}>
        <Chip scroll label="All categories" on={view.fCat === 'all'} onClick={() => setView({ fCat: 'all' })} />
        {L.cats.map((c) => <Chip scroll key={c.id} label={c.name} on={view.fCat === c.id} onClick={() => setView({ fCat: c.id })} />)}
      </div>
    </div>
  )
}

/** One entry row (click to edit, hover or right-click to delete). Today reuses it for recent
 *  entries without the who badge; a loan's payments pass `back` to return to the loan. */
export function TxButton({ L, t, badge = true, back }: { L: Ledger; t: Tx; badge?: boolean; back?: Panel }) {
  const r = txRow(L, t)
  return (
    <EntryRow t={t} back={back}>
      <span style={css('width:44px;height:44px;border-radius:13px;flex:none;background:var(--soft);display:grid;place-items:center;font-weight:600;font-size:17px')}>{r.ini}</span>
      <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
        <span style={css('font-size:16px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap')}>{r.name}</span>
        <span style={css('font-size:13px;color:var(--mute);overflow:hidden;text-overflow:ellipsis;white-space:nowrap')}>{r.sub}</span>
      </span>
      {badge ? (
        <>
          <span title={r.whoTitle} style={sx("width:26px;height:26px;flex:none;border-radius:50%;display:grid;place-items:center;font:600 11px 'Geist',sans-serif;box-sizing:border-box", { border: '1.5px solid ' + r.whoCol })}>{r.who}</span>
          <span style={sx('font-size:15px;font-weight:500;min-width:88px;text-align:right;white-space:nowrap', { color: r.amtColor })}>{r.amt}</span>
        </>
      ) : (
        <span style={css('font-size:15px;font-weight:500;white-space:nowrap')}>{r.amt}</span>
      )}
    </EntryRow>
  )
}

function Body({ L }: { L: Ledger }) {
  const { view } = useUI()
  const list = filtered(L, view)
  const groups: { date: string; n: number; items: Tx[] }[] = []
  list.forEach((t) => {
    let g = groups[groups.length - 1]
    if (!g || g.date !== t.date) groups.push((g = { date: t.date, n: 0, items: [] }))
    g.items.push(t)
    g.n += t.type === 'inc' ? t.amt : t.type === 'exp' ? -t.amt : 0
  })
  return (
    <div>
      <div style={css('columns:2 380px;column-gap:48px')}>
        {groups.map((g) => (
          <div key={g.date} style={css('break-inside:avoid;padding-bottom:22px')}>
            <div style={css('display:flex;justify-content:space-between;font-size:13px;color:var(--mute)')}><span>{dLab(isoD(g.date))}</span><span>{(g.n > 0 ? '+' : '') + L.f(g.n)}</span></div>
            {g.items.map((t) => <TxButton key={t.id} L={L} t={t} />)}
          </div>
        ))}
      </div>
      {!list.length && <div style={css('padding:40px 0;color:var(--mute)')}>Nothing here yet. Use “Add entry” to log the first one, or “Import statement” to bring in a month from your bank.</div>}
    </div>
  )
}

export const activityTab: TabDef = {
  id: 'activity',
  stage: 'cream',
  kicker: () => 'Every entry, searchable',
  hero: (L, view) => {
    const list = filtered(L, view)
    return {
      label: list.length + ' entries in ' + mLabel(L.ym), cur: true,
      num: L.num(Math.round(sum(list.filter((t) => t.type === 'exp'), (t) => t.amt))),
      fg: '#ffffff', sub: 'Money out across everything shown below.',
    }
  },
  Header,
  Body,
}
