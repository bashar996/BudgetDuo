// Import a bank or card statement (CSV, Excel, PDF): pick the account, check the columns,
// review the rows (duplicates, bills, categories), import in one go with Undo.
import { useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import type { Ledger } from '../data/ledger'
import type { Who } from '../data/types'
import { useStore } from '../data/store'
import { css, sx } from '../lib/css'
import { MN } from '../lib/dates'
import { useUI } from '../shell/ui'
import { BTN_LINE, inputStyle, PanelFrame } from '../panels/PanelFrame'
import { ChipGroup, type ChipOpt } from '../panels/parts'
import { detectMapping, finalize, inferSign, prepare, rawRows, shapeOf, type Mapping, type RawRow } from './detect'
import { importIds } from './dedupe'
import { linesToRows } from './pdfText'
import { planRows, ready, toEntry, type PlanRow, type Status } from './plan'
import { ACCEPT, loadFile, type Loaded } from './read'
import type { DateOrder } from './dates'

// MARK: Remembered column choices (per account and file shape, this Mac only)

interface Memory { map?: Partial<Mapping>; posOut?: boolean; order?: DateOrder }
const memKey = (acct: string) => 'twofold:importMap:' + acct
function recall(acct: string, shape: string): Memory | null {
  try { return (JSON.parse(localStorage.getItem(memKey(acct)) || '{}') as Record<string, Memory>)[shape] ?? null } catch { return null }
}
function remember(acct: string, shape: string, m: Memory) {
  try {
    const all = JSON.parse(localStorage.getItem(memKey(acct)) || '{}') as Record<string, Memory>
    all[shape] = m
    localStorage.setItem(memKey(acct), JSON.stringify(all))
  } catch { /* private mode */ }
}

type Filter = 'all' | 'new' | 'dupe' | 'cat'
type Edit = Partial<Pick<PlanRow, 'on' | 'name' | 'cat' | 'catHow' | 'who'>>

const ROLE_LABEL: [keyof Mapping, string][] = [['date', 'Date'], ['desc', 'Description'], ['amount', 'Amount'], ['debit', 'Money out (debit)'], ['credit', 'Money in (credit)'], ['balance', 'Balance']]
const shortDate = (iso: string) => Number(iso.slice(8, 10)) + ' ' + MN[Number(iso.slice(5, 7)) - 1].slice(0, 3)

export function ImportPanel({ L, file: initialFile, acct: initialAcct }: { L: Ledger; file?: File; acct?: string }) {
  const { act } = useStore()
  const ui = useUI()
  const [file, setFile] = useState<File | null>(initialFile ?? null)
  const [loaded, setLoaded] = useState<Loaded | null>(null)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const [pwd, setPwd] = useState<{ wrong: boolean; value: string } | null>(null)
  const pickable = L.accounts.filter((a) => a.type !== 'invest')
  const [acct, setAcct] = useState<string>(() =>
    (initialAcct && pickable.some((a) => a.id === initialAcct) && initialAcct) || (pickable.length === 1 ? pickable[0].id : ''))
  const [mapEdit, setMapEdit] = useState<Partial<Mapping>>({})
  const [signEdit, setSignEdit] = useState<boolean | null>(null)
  const [orderEdit, setOrderEdit] = useState<DateOrder | null>(null)
  const [edits, setEdits] = useState<Record<string, Edit>>({})
  const [filter, setFilter] = useState<Filter>('all')
  const [showCols, setShowCols] = useState(false)
  const [ids, setIds] = useState<{ key: string; ids: string[] } | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const account = L.acctBy[acct]
  const isCard = account?.type === 'card'

  // Read the file (again with the password when one is given).
  const read = async (f: File, password?: string) => {
    setBusy(true); setErr('')
    try {
      const l = await loadFile(f, password)
      setLoaded(l); setPwd(null)
      guessAccount(l)
    } catch (e: any) {
      if (e?.name === 'NeedPassword') setPwd({ wrong: !!e.wrong, value: '' })
      else { setErr(e?.message || 'This file couldn’t be read.'); setLoaded(null) }
    } finally { setBusy(false) }
  }
  useEffect(() => { if (file) void read(file) }, [file])

  /** Picks the account whose last four digits appear near the top of the statement. */
  const guessAccount = (l: Loaded) => {
    if (acct) return
    const text = (l.kind === 'pdf' ? l.lines.slice(0, 60) : l.table.slice(0, 30).map((r) => r.join(' '))).join(' ')
    const hit = pickable.find((a) => a.last4 && new RegExp('(^|[^0-9])' + a.last4 + '($|[^0-9])').test(text))
    if (hit) setAcct(hit.id)
  }

  // Columns: detected, then what was remembered for this account and file shape, then the user's changes.
  const detected = useMemo(() => {
    if (!loaded || loaded.kind !== 'table' || !loaded.table.length) return null
    const m = detectMapping(loaded.table, isCard)
    return { m, shape: shapeOf(loaded.table, m) }
  }, [loaded, isCard])
  const shape = loaded?.kind === 'pdf' ? 'pdf' : detected?.shape ?? ''
  const mem = useMemo(() => (acct && shape ? recall(acct, shape) : null), [acct, shape])
  const map: Mapping | null = detected ? { ...detected.m, ...(mem?.map ?? {}), ...mapEdit, order: orderEdit ?? mem?.order ?? detected.m.order } : null

  // Rows before and after the sign convention.
  const pdfParsed = useMemo(() => (loaded?.kind === 'pdf' ? linesToRows(loaded.lines, isCard) : null), [loaded, isCard])
  const raw: RawRow[] = useMemo(() => {
    if (loaded?.kind === 'table' && map) return prepare(rawRows(loaded.table, map), isCard)
    return pdfParsed?.rows ?? []
  }, [loaded, pdfParsed, JSON.stringify(map), isCard])
  const sign = useMemo(() => inferSign(raw, isCard), [raw, isCard])
  const posOut = signEdit ?? mem?.posOut ?? sign.posOut
  const rows = useMemo(() => finalize(raw, posOut), [raw, posOut])

  // Import IDs (SHA-256, async), then the plan.
  const idKey = acct + '|' + rows.map((r) => r.date + r.amount + r.desc).join('\n')
  useEffect(() => {
    if (!acct || !rows.length) return
    let live = true
    void importIds(acct, rows).then((x) => { if (live) setIds({ key: idKey, ids: x }) })
    return () => { live = false }
  }, [idKey])
  const plan: PlanRow[] = useMemo(() => {
    if (!acct || !ids || ids.key !== idKey) return []
    return planRows(rows, L.data, acct, ids.ids)
  }, [ids, L.data])
  const merged = plan.map((p) => ({ ...p, ...edits[p.importId] }))

  const edit = (p: PlanRow, e: Edit) => setEdits((x) => ({ ...x, [p.importId]: { ...x[p.importId], ...e } }))
  const editMany = (list: PlanRow[], e: Edit) => setEdits((x) => { const n = { ...x }; list.forEach((p) => (n[p.importId] = { ...n[p.importId], ...e })); return n })

  const isDup = (p: PlanRow) => p.status === 'dupe' || p.status === 'imported'
  const needsCat = (p: PlanRow) => p.kind === 'exp' && !p.cat
  const shown = merged.filter((p) => filter === 'all' || (filter === 'new' ? !isDup(p) : filter === 'dupe' ? isDup(p) : needsCat(p)))
  const toImport = merged.filter((p) => p.on && ready(p))
  const blocked = merged.filter((p) => p.on && !ready(p)).length
  const nNew = merged.filter((p) => !isDup(p)).length, nDup = merged.length - nNew, nCat = merged.filter(needsCat).length

  const doImport = () => {
    if (!acct) return setErr('Pick the account this statement is for.')
    if (!toImport.length) return setErr(blocked ? 'Pick a category for the ticked rows first.' : 'Tick at least one row to import.')
    const res = act.importEntries(toImport.map((p) => toEntry(p, acct)))
    if (shape) remember(acct, shape, { map: map ? { date: map.date, vdate: map.vdate, desc: map.desc, amount: map.amount, debit: map.debit, credit: map.credit, balance: map.balance, dir: map.dir } : undefined, posOut, order: map?.order ?? pdfParsed?.order })
    const last = toImport.reduce((m, p) => (p.row.date > m ? p.row.date : m), '')
    ui.closeAll()
    ui.go('activity')
    ui.setView({ fAcct: acct, q: '', fCat: 'all', fWho: 'all' })
    if (last) ui.setYm(last.slice(0, 7))
    const n = res.ids.length
    ui.toast('Imported ' + n + (n === 1 ? ' entry' : ' entries'), () => act.undoImport(res))
  }

  const choose = () => inputRef.current?.click()
  const setMap = (patch: Partial<Mapping>) => { setMapEdit((m) => ({ ...m, ...patch })); setEdits({}) }

  const head = (
    <div style={css('padding:14px 0 6px;display:flex;flex-direction:column;gap:4px')}>
      <span style={css('font-size:14.5px;color:#3a3566')}>{file ? file.name : 'CSV, Excel or PDF statement from your bank or card.'}</span>
      {merged.length > 0 && (
        <span style={css("font:500 30px/1.1 'Geist',sans-serif;letter-spacing:-.03em")}>
          {nNew + ' new'}<span style={css('color:#3a3566')}>{' · ' + nDup + ' already in Twofold' + (nCat ? ' · ' + nCat + ' need a category' : '')}</span>
        </span>
      )}
    </div>
  )

  return (
    <PanelFrame wide title="Import statement" head={head} err={err || (blocked ? blocked + (blocked === 1 ? ' ticked row needs' : ' ticked rows need') + ' a category — pick one, or it’s left out.' : '')}
      onSave={merged.length ? doImport : undefined}
      saveLabel={'Import ' + toImport.length + (toImport.length === 1 ? ' entry' : ' entries')}
      actions={file ? <button type="button" onClick={choose} style={BTN_LINE}>Choose another file</button> : undefined}>
      <input ref={inputRef} type="file" accept={ACCEPT} hidden onChange={(e) => {
        const f = e.target.files?.[0]
        e.target.value = ''
        if (f) { setLoaded(null); setEdits({}); setMapEdit({}); setSignEdit(null); setOrderEdit(null); setIds(null); setFile(f) }
      }} />

      {!file && (
        <button type="button" onClick={choose} className="h-row"
          style={css("display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;min-height:220px;border:1.5px dashed var(--chip);border-radius:24px;background:transparent;color:var(--ink);font:inherit;cursor:pointer;padding:24px;text-align:center")}>
          <span style={css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")}>Drop a statement here, or choose a file</span>
          <span style={css('font-size:14px;color:var(--mute);max-width:440px;text-wrap:pretty')}>CSV or Excel downloads work best. Text PDFs work too (password-protected ones ask for the password). Nothing leaves this Mac until you import.</span>
          <span style={css("margin-top:10px;font:500 15px 'Geist',sans-serif;height:48px;line-height:48px;padding:0 22px;border-radius:16px;background:var(--btn);color:var(--btnInk)")}>Choose file</span>
        </button>
      )}

      {busy && <div style={css('padding:30px 0;color:var(--mute)')}>Reading {file?.name}…</div>}

      {pwd && (
        <section style={css('display:flex;flex-direction:column;gap:10px;max-width:460px')}>
          <span style={css("font:500 18px 'Geist',sans-serif")}>This PDF is password-protected</span>
          <span style={css('font-size:14px;color:var(--mute);text-wrap:pretty')}>{pwd.wrong ? 'That password didn’t work. Try again.' : 'Banks often protect statements with a password (your date of birth or part of your card or account number). It’s only used to open the file.'}</span>
          <div style={css('display:flex;gap:8px')}>
            <input autoFocus type="password" className="h-focus-ink" placeholder="Password" value={pwd.value} onChange={(e) => setPwd({ ...pwd, value: e.target.value })}
              onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); if (file && pwd.value) void read(file, pwd.value) } }}
              style={sx('', { ...inputStyle, flex: 1 })} />
            <button type="button" disabled={!pwd.value} onClick={() => file && void read(file, pwd.value)}
              style={sx("font:500 15px 'Geist',sans-serif;padding:0 22px;height:52px;border-radius:16px;border:none;background:var(--btn);color:var(--btnInk);cursor:pointer", { opacity: pwd.value ? 1 : 0.5 })}>Unlock</button>
          </div>
        </section>
      )}

      {loaded && !busy && (
        <>
          <ChipGroup label="Which account is this statement for?" chips={pickable.map((a): ChipOpt => ({ key: a.id, label: a.name + (a.last4 ? ' ·· ' + a.last4 : ''), on: acct === a.id, pick: () => { setAcct(a.id); setEdits({}); setSignEdit(null) } }))} />
          {!pickable.length && <div style={css('font-size:14px;color:var(--mute)')}>Add the account under Accounts first, then import its statement.</div>}

          {acct && (
            <Columns open={showCols} toggle={() => setShowCols((s) => !s)} loaded={loaded} map={map} setMap={setMap}
              sign={sign} posOut={posOut} isCard={isCard} setSign={(v) => { setSignEdit(v); setEdits({}) }}
              order={map?.order ?? pdfParsed?.order ?? 'dmy'} setOrder={loaded.kind === 'table' ? (o) => { setOrderEdit(o); setEdits({}) } : undefined}
              count={rows.length} />
          )}

          {acct && rows.length === 0 && (
            <div style={css('padding:12px 0;font-size:14.5px;color:var(--mute);text-wrap:pretty')}>
              {loaded.kind === 'pdf' ? 'No transactions found in this PDF. It may be a scanned image or an unusual layout — the CSV or Excel download from your bank will work better.' : 'No rows with a date and an amount. Check the columns above.'}
            </div>
          )}

          {merged.length > 0 && (
            <Review L={L} list={shown} all={merged} filter={filter} setFilter={setFilter} counts={{ all: merged.length, new: nNew, dupe: nDup, cat: nCat }}
              edit={edit} editMany={editMany} />
          )}
        </>
      )}
    </PanelFrame>
  )
}

// MARK: Columns

function Columns({ open, toggle, loaded, map, setMap, sign, posOut, isCard, setSign, order, setOrder, count }: {
  open: boolean; toggle(): void; loaded: Loaded; map: Mapping | null; setMap(p: Partial<Mapping>): void
  sign: { posOut: boolean; sure: boolean; show: boolean }; posOut: boolean; isCard: boolean; setSign(v: boolean): void
  order: DateOrder; setOrder?: (o: DateOrder) => void; count: number
}) {
  const table = loaded.kind === 'table' ? loaded.table : null
  const width = table ? Math.max(0, ...table.slice(0, 60).map((r) => r.length)) : 0
  const colName = (c: number) => (map && map.header >= 0 && table![map.header][c]) || 'Column ' + (c + 1)
  const single = !!map && map.amount >= 0
  const summary = table && map
    ? [map.date >= 0 ? 'Date: ' + colName(map.date) : 'No date column', map.desc >= 0 ? 'Description: ' + colName(map.desc) : '', single ? 'Amount: ' + colName(map.amount) : 'Debit: ' + (map.debit >= 0 ? colName(map.debit) : '—') + ', Credit: ' + (map.credit >= 0 ? colName(map.credit) : '—')].filter(Boolean).join(' · ')
    : count + ' transaction lines found in the PDF'
  const showSign = (single || loaded.kind === 'pdf') && sign.show
  const signChips: ChipOpt[] = [
    { key: 'neg', label: loaded.kind === 'pdf' ? 'Plain amounts are money in' : 'Money out is negative', on: !posOut, pick: () => setSign(false) },
    { key: 'pos', label: loaded.kind === 'pdf' ? 'Plain amounts are money out' : isCard ? 'Charges are positive' : 'Money out is positive', on: posOut, pick: () => setSign(true) },
  ]
  const preview = table && map ? table.slice(Math.max(0, map.header), Math.max(0, map.header) + 7) : loaded.kind === 'pdf' ? null : []

  return (
    <section style={css('border-radius:20px;background:var(--card);padding:6px 18px')}>
      <button type="button" onClick={toggle} aria-expanded={open}
        style={css("display:flex;align-items:center;gap:12px;width:100%;min-height:52px;border:none;background:none;padding:0;color:var(--ink);font:inherit;cursor:pointer;text-align:left")}>
        <span style={css("font:500 16px 'Geist',sans-serif;flex:none")}>Columns</span>
        <span style={css('flex:1;min-width:0;font-size:13.5px;color:var(--mute);overflow:hidden;text-overflow:ellipsis;white-space:nowrap')}>{summary}</span>
        {showSign && !sign.sure && !open && <span style={css("flex:none;font:500 12.5px 'Geist',sans-serif;padding:4px 10px;border-radius:10px;border:1px solid var(--warn);color:var(--warn)")}>Check money in / out</span>}
        <span style={sx('flex:none;font-size:18px;transition:transform .2s', { transform: open ? 'rotate(90deg)' : 'none' })}>›</span>
      </button>
      {open && (
        <div style={css('display:flex;flex-direction:column;gap:16px;padding:6px 0 18px')}>
          {table && map && (
            <>
              <div style={css('display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:10px')}>
                {ROLE_LABEL.filter(([k]) => (single ? k !== 'debit' && k !== 'credit' : k !== 'amount')).map(([k, label]) => (
                  <label key={k} style={css('display:flex;flex-direction:column;gap:6px')}>
                    <span style={css('font-size:13px;color:var(--mute)')}>{label}</span>
                    <select value={map[k] as number} onChange={(e) => setMap({ [k]: Number(e.target.value) })} style={SELECT}>
                      <option value={-1}>—</option>
                      {Array.from({ length: width }, (_, c) => <option key={c} value={c}>{colName(c)}</option>)}
                    </select>
                  </label>
                ))}
              </div>
              <ChipGroup label="Amounts are in" chips={[
                { key: 'one', label: 'One amount column', on: single, pick: () => { if (!single) setMap({ amount: map.debit >= 0 ? map.debit : map.credit, debit: -1, credit: -1 }) } },
                { key: 'two', label: 'Debit and Credit columns', on: !single, pick: () => { if (single) setMap({ debit: map.amount, credit: Math.min(width - 1, map.amount + 1), amount: -1 }) } },
              ]} />
            </>
          )}
          {showSign && <ChipGroup label={sign.sure ? 'Money in and out' : 'Money in and out — couldn’t tell from the file, please check'} chips={signChips} />}
          {setOrder && <ChipGroup label="Dates" chips={[
            { key: 'dmy', label: 'Day first (31/12/2026)', on: order === 'dmy', pick: () => setOrder('dmy') },
            { key: 'mdy', label: 'Month first (12/31/2026)', on: order === 'mdy', pick: () => setOrder('mdy') },
          ]} />}
          {preview && preview.length > 0 && (
            <div style={css('overflow-x:auto;border-radius:14px;border:1px solid var(--line)')}>
              <table style={css('border-collapse:collapse;font-size:12.5px;width:100%')}>
                <tbody>
                  {preview.map((r, i) => (
                    <tr key={i} style={sx('', { background: i === 0 && map!.header >= 0 ? 'var(--soft)' : undefined, fontWeight: i === 0 && map!.header >= 0 ? 600 : 400 })}>
                      {Array.from({ length: width }, (_, c) => (
                        <td key={c} style={sx('padding:7px 10px;border-bottom:1px solid var(--line);white-space:nowrap;max-width:260px;overflow:hidden;text-overflow:ellipsis', { color: roleOfCol(map!, c) ? 'var(--ink)' : 'var(--mute)' })}>{r[c] ?? ''}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </section>
  )
}
const roleOfCol = (m: Mapping, c: number) => [m.date, m.desc, m.amount, m.debit, m.credit, m.balance].includes(c)

const SELECT: CSSProperties = css("box-sizing:border-box;width:100%;height:44px;padding:0 12px;border:1px solid var(--chip);border-radius:14px;background:transparent;color:var(--ink);font:500 14px 'Geist',sans-serif;outline:none;cursor:pointer")

// MARK: Review

function Review({ L, list, all, filter, setFilter, counts, edit, editMany }: {
  L: Ledger; list: PlanRow[]; all: PlanRow[]; filter: Filter; setFilter(f: Filter): void; counts: Record<Filter, number>
  edit(p: PlanRow, e: Edit): void; editMany(list: PlanRow[], e: Edit): void
}) {
  const ticked = all.filter((p) => p.on)
  const tickedExp = ticked.filter((p) => p.kind === 'exp')
  const allOn = list.length > 0 && list.every((p) => p.on)
  const filters: [Filter, string][] = [['all', 'All'], ['new', 'New'], ['dupe', 'Duplicates'], ['cat', 'Needs category']]
  return (
    <section style={css('display:flex;flex-direction:column;gap:10px')}>
      <div style={css('display:flex;flex-wrap:wrap;align-items:center;gap:6px')}>
        {filters.map(([k, label]) => (
          <PillChip key={k} on={filter === k} onClick={() => setFilter(k)}>{label + ' ' + counts[k]}</PillChip>
        ))}
        <span style={css('flex:1')} />
        <select value="" disabled={!tickedExp.length} onChange={(e) => { if (e.target.value) editMany(tickedExp, { cat: e.target.value, catHow: 'user' }) }}
          style={sx('', { ...SELECT, width: 'auto', minWidth: 230, opacity: tickedExp.length ? 1 : 0.5 })}>
          <option value="">Set category for ticked ({tickedExp.length})</option>
          {L.cats.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          <option value="other">Other (no category)</option>
        </select>
      </div>
      <div style={css('display:grid;grid-template-columns:28px 58px minmax(0,1fr) 180px 30px 116px;gap:12px;align-items:center;padding:8px 0;border-bottom:1px solid var(--line);font-size:12.5px;color:var(--mute)')}>
        <Check on={allOn} onClick={() => editMany(list, { on: !allOn })} label={allOn ? 'Untick all shown' : 'Tick all shown'} />
        <span>Date</span><span>Name</span><span>Category</span><span title="Who">Who</span><span style={css('text-align:right')}>Amount</span>
      </div>
      {list.map((p) => <ReviewRow key={p.key} L={L} p={p} edit={edit} />)}
      {!list.length && <div style={css('padding:20px 0;color:var(--mute);font-size:14px')}>Nothing in this filter.</div>}
    </section>
  )
}

const BADGE: Record<Status, string> = {
  new: '', income: 'background:var(--soft)', salary: 'background:var(--soft)', refund: 'background:var(--soft)',
  needsCat: 'border:1px solid var(--warn);color:var(--warn)',
  imported: 'background:var(--soft);color:var(--mute)', dupe: 'background:var(--soft);color:var(--mute)',
  transfer: 'border:1px dashed var(--chip)', cardPayment: 'border:1px dashed var(--chip)',
  bill: 'background:var(--accBase);color:#0b0b0c', loan: 'background:var(--accBase);color:#0b0b0c',
}
const NEXT: Record<Who, Who> = { J: 'A', A: 'B', B: 'J' }

function ReviewRow({ L, p, edit }: { L: Ledger; p: PlanRow; edit(p: PlanRow, e: Edit): void }) {
  const isIn = p.row.amount > 0
  const missing = p.kind === 'exp' && !p.cat
  const badge = missing ? 'Needs a category' : p.status === 'new' ? (p.catHow === 'history' ? 'Like before' : '') : p.note
  const fixedCat = p.kind === 'xfer' ? 'Transfer' + (p.to ? ' → ' + L.aName(p.to) : '') : p.kind === 'inc' ? 'Income' : null
  return (
    <div className="h-row" style={sx('display:grid;grid-template-columns:28px 58px minmax(0,1fr) 180px 30px 116px;gap:12px;align-items:center;padding:8px 0;border-bottom:1px solid var(--line);transition:opacity .15s', { opacity: p.on ? 1 : 0.55 })}>
      <Check on={p.on} onClick={() => edit(p, { on: !p.on })} label={(p.on ? 'Untick ' : 'Tick ') + p.name} />
      <span style={css('font-size:13.5px;color:var(--mute);white-space:nowrap')}>{shortDate(p.row.date)}</span>
      <span style={css('min-width:0;display:flex;flex-direction:column;gap:2px')}>
        <input className="h-focus-ink" value={p.name} aria-label="Name" onChange={(e) => edit(p, { name: e.target.value })}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); (e.target as HTMLInputElement).blur() } }}
          style={css("box-sizing:border-box;width:100%;height:32px;margin-left:-8px;padding:0 8px;border:none;border-radius:10px;background:transparent;color:var(--ink);font:500 15px 'Geist',sans-serif;outline:none")} />
        <span style={css('display:flex;align-items:center;gap:8px;min-width:0')}>
          {badge && <span style={sx("flex:none;font:500 12px 'Geist',sans-serif;padding:2px 9px;border-radius:9px;white-space:nowrap;max-width:330px;overflow:hidden;text-overflow:ellipsis", css(BADGE[missing ? 'needsCat' : p.status]))} title={p.note}>{badge}</span>}
          <span title={p.row.raw} style={css('min-width:0;font-size:12px;color:var(--mute);overflow:hidden;text-overflow:ellipsis;white-space:nowrap')}>{p.row.desc}</span>
        </span>
      </span>
      {fixedCat ? (
        <span style={css('font-size:13.5px;color:var(--mute);padding-left:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap')}>{fixedCat}</span>
      ) : (
        <select value={p.cat ?? ''} aria-label="Category" onChange={(e) => edit(p, { cat: e.target.value || null, catHow: 'user' })}
          style={sx('', { ...SELECT, height: 38, borderColor: missing ? 'var(--warn)' : 'var(--chip)', color: missing ? 'var(--warn)' : 'var(--ink)' })}>
          <option value="">Pick a category…</option>
          {L.cats.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          <option value="other">Other (no category)</option>
        </select>
      )}
      {p.kind === 'xfer' ? <span /> : (
        <button type="button" onClick={() => edit(p, { who: NEXT[p.who] })} title={L.whoName[p.who] + ' · click to change'} aria-label={'Who: ' + L.whoName[p.who]}
          style={sx("width:28px;height:28px;padding:0;border-radius:50%;background:transparent;color:var(--ink);display:grid;place-items:center;font:600 11px 'Geist',sans-serif;cursor:pointer;box-sizing:border-box", { border: '1.5px solid ' + L.whoCol[p.who] })}>{(L.whoName[p.who] || '?')[0]}</button>
      )}
      <span style={sx("font:500 15px 'Geist',sans-serif;text-align:right;white-space:nowrap", { color: isIn ? 'var(--good)' : 'var(--ink)' })}>{(isIn ? '+' : '') + L.f(Math.abs(p.row.amount))}</span>
    </div>
  )
}

function Check({ on, onClick, label }: { on: boolean; onClick(): void; label: string }) {
  return (
    <button type="button" role="checkbox" aria-checked={on} aria-label={label} onClick={onClick}
      style={sx('width:24px;height:24px;padding:0;border-radius:8px;display:grid;place-items:center;cursor:pointer;box-sizing:border-box;font-size:14px;line-height:1', { border: '1.5px solid ' + (on ? 'var(--ink)' : 'var(--chip)'), background: on ? 'var(--ink)' : 'transparent', color: 'var(--bg)' })}>{on ? '✓' : ''}</button>
  )
}

function PillChip({ on, onClick, children }: { on: boolean; onClick(): void; children: ReactNode }) {
  return (
    <button type="button" onClick={onClick} aria-pressed={on}
      style={sx("height:40px;padding:0 14px;border-radius:20px;font:500 13.5px 'Geist',sans-serif;cursor:pointer", { border: '1px solid ' + (on ? 'var(--ink)' : 'var(--chip)'), background: on ? 'var(--ink)' : 'transparent', color: on ? 'var(--bg)' : 'var(--ink)' })}>{children}</button>
  )
}
