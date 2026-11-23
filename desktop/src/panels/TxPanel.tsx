// New / edit entry: Expense, Income or Transfer (also pot deposits and withdrawals).
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import type { Tx, TxType, Who } from '../data/types'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { isoOf } from '../lib/dates'
import { useUI } from '../shell/ui'
import { inputStyle, PanelFrame } from './PanelFrame'
import { ChipGroup, chips, Pair, parse } from './parts'

interface Draft {
  type: TxType; amt: string; name: string; cat: string; who: Who; acct: string; to: string; date: string; note: string
  pot?: string | null; potDir?: 'in' | 'out' | null; billId?: string | null
  debtId?: string | null; debtPart?: 'installment' | 'extra' | null
}

export function TxPanel({ L, tx, pre }: { L: Ledger; tx?: Tx; pre?: Partial<Tx> }) {
  const { act } = useStore()
  const { close, toast, open } = useUI()
  const [d, setD] = useState<Draft>(() => {
    if (tx) return { type: tx.type, amt: String(tx.amt), name: tx.name, cat: tx.cat, who: tx.who, acct: tx.acct, to: tx.to ?? '', date: tx.date, note: tx.note ?? '', pot: tx.pot, potDir: tx.potDir, billId: tx.billId, debtId: tx.debtId, debtPart: tx.debtPart }
    const p = pre ?? {}
    return {
      type: p.type ?? 'exp', amt: p.amt ? String(p.amt) : '', name: p.name ?? '', cat: p.cat ?? L.catOr('groceries'), who: p.who ?? 'J',
      acct: p.acct ?? L.mainAcct, to: p.to ?? '', date: p.date ?? isoOf(new Date()), note: p.note ?? '', pot: p.pot, potDir: p.potDir, billId: p.billId,
      debtId: p.debtId, debtPart: p.debtPart,
    }
  })
  const [err, setErr] = useState('')
  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => { setErr(''); setD((x) => ({ ...x, [k]: v })) }

  const f = L.f, isX = d.type === 'xfer'
  const dPot = d.pot ? L.goals.find((g) => g.id === d.pot) : undefined
  const loan = d.debtId ? L.data.debts.find((x) => x.id === d.debtId) : undefined
  const out = d.potDir === 'out'
  const pickable = L.accounts.filter((a) => !dPot || a.type === 'current' || a.type === 'cash')
  const title = dPot ? (out ? 'Withdraw from ' : 'Add to ') + dPot.name : tx ? 'Edit entry' : 'New entry'
  const potInfo = dPot ? (out ? 'Comes out of ' + dPot.name + ' in ' + L.aName(dPot.acct) + '. ' + f(dPot.saved) + ' is in the pot right now.' : 'Goes into ' + dPot.name + ', kept in ' + L.aName(dPot.acct) + '.') : ''

  const save = () => {
    const amt = parse(d.amt)
    if (!(amt > 0)) return setErr('Add an amount first.')
    const inc = d.type === 'inc'
    if (isX && (!d.acct || !d.to || d.acct === d.to)) return setErr('Pick two different accounts.')
    if (!d.acct && L.accounts.length) return setErr('Pick an account.')
    const cat = isX ? 'transfer' : inc ? 'income' : d.cat === 'income' || d.cat === 'transfer' ? L.catOr('groceries') : d.cat
    const c = L.cats.find((z) => z.id === cat)
    act.saveTx({
      id: tx?.id, createdAt: tx?.createdAt ?? undefined,
      date: d.date || L.period.from,
      name: d.name.trim() || (isX ? 'Transfer' : inc ? 'Income' : (c && c.name) || 'Pocket money'),
      cat, amt, who: d.who, type: d.type, note: d.note.trim(), billId: d.billId ?? undefined, acct: d.acct,
      to: isX ? d.to : undefined, pot: isX ? d.pot ?? undefined : undefined, potDir: isX ? d.potDir ?? undefined : undefined,
      // A loan payment stays linked to its loan while it's an expense.
      debtId: d.type === 'exp' ? d.debtId ?? undefined : undefined, debtPart: d.type === 'exp' && d.debtId ? d.debtPart ?? 'installment' : undefined,
    })
    close()
  }

  const acctChips = (k: 'acct' | 'to') => pickable.map((a) => ({ key: a.id, label: a.name, on: d[k] === a.id, pick: () => set(k, a.id) }))

  return (
    <PanelFrame title={title}
      types={dPot ? undefined : ([['exp', 'Expense'], ['inc', 'Income'], ['xfer', 'Transfer']] as [TxType, string][]).map(([k, label]) => ({ label, on: d.type === k, pick: () => set('type', k) }))}
      amount={{ value: d.amt, onChange: (v) => set('amt', v), currency: L.cur }}
      err={err} onSave={save}
      onDelete={tx ? () => { act.deleteTx(tx); toast('Deleted ' + tx.name, () => act.restoreTx(tx)); close() } : undefined}>
      <div style={css('display:flex;flex-direction:column;gap:16px')}>
        {dPot && <div style={css('font-size:14.5px;text-wrap:pretty')}>{potInfo}</div>}
        {loan && d.type === 'exp' && <div style={css('font-size:14.5px;text-wrap:pretty')}>{(d.debtPart === 'extra' ? 'Extra payment' : 'Installment') + ' on ' + loan.name + '. Changing or deleting it updates the loan.'}</div>}
        <input className="h-focus-ink" placeholder="What was it? (optional)" value={d.name} onChange={(e) => set('name', e.target.value)} style={inputStyle} />
        {d.type === 'exp' && <ChipGroup label="Category" chips={L.cats.map((c) => ({ key: c.id, label: c.name, on: d.cat === c.id, pick: () => set('cat', c.id) }))} />}
        {!(dPot && out) && <ChipGroup label={isX ? 'From' : d.type === 'inc' ? 'Into account' : 'Paid from'} chips={acctChips('acct')} />}
        {isX && !(dPot && !out) && <ChipGroup label="To" chips={acctChips('to')} />}
        {!isX && <ChipGroup grow label={d.type === 'inc' ? 'Who earned it' : 'Who spent it'} chips={chips<Who>([['J', L.whoName.J], ['A', L.whoName.A], ['B', L.whoName.B]], d.who, (w) => set('who', w))} />}
        <Pair>
          <input type="date" value={d.date} onChange={(e) => set('date', e.target.value)} style={inputStyle} />
          <input className="h-focus-ink" placeholder="Note" value={d.note} onChange={(e) => set('note', e.target.value)} style={inputStyle} />
        </Pair>
        {!tx && !dPot && (
          <button type="button" onClick={() => open({ kind: 'import', acct: d.acct || undefined })}
            style={css("align-self:flex-start;height:44px;padding:0;border:none;background:none;color:var(--ink);font:500 14px 'Geist',sans-serif;text-decoration:underline;text-underline-offset:3px;cursor:pointer")}>Have a statement? Import it instead</button>
        )}
      </div>
    </PanelFrame>
  )
}
