// New / edit account. The balance is typed as it stands today; we store the
// opening balance that makes the entries add up to it.
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import type { Account, AccountType, Who } from '../data/types'
import { ACCOUNT_TYPES } from '../data/catalog'
import { CARD_DEFAULTS } from '../data/loans'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { useUI } from '../shell/ui'
import { PanelFrame } from './PanelFrame'
import { ChipGroup, chips, Pair, TextField, parse } from './parts'

export function AcctPanel({ L, acct, preset }: { L: Ledger; acct?: Account; preset?: AccountType }) {
  const { act } = useStore()
  const { close, setView } = useUI()
  const old = acct ? L.data.accounts.find((a) => a.id === acct.id) : undefined
  const curBal = old ? L.balance(old) : 0
  const [d, setD] = useState(() => old
    ? { name: old.name, atype: old.type, who: old.who, amt: String(Math.round(curBal * 100) / 100), bank: old.bank ?? '', last4: old.last4 ?? '', limit: old.limit ? String(old.limit) : '', apr: old.apr ? String(old.apr) : '', apy: old.apy ? String(old.apy) : '', cost: old.cost ? String(old.cost) : '',
        stmt: old.statementDay ? String(old.statementDay) : '', due: old.dueDay ? String(old.dueDay) : '', minPct: old.minPct != null ? String(old.minPct) : '', minFloor: old.minFloor != null ? String(old.minFloor) : '' }
    : { name: '', atype: preset ?? ('current' as AccountType), who: 'J' as Who, amt: '', bank: '', last4: '', limit: '', apr: '', apy: '', cost: '', stmt: '', due: '', minPct: '', minFloor: '' })
  const [err, setErr] = useState('')
  const set = <K extends keyof typeof d>(k: K, v: (typeof d)[K]) => { setErr(''); setD((x) => ({ ...x, [k]: v })) }

  const save = () => {
    const name = d.name.trim(), bal = parse(d.amt.replace('−', '-'))
    if (!name) return setErr('Give it a name.')
    if (isNaN(bal)) return setErr('Add the balance as it stands today.')
    const opening = old ? old.opening + (bal - curBal) : bal
    const card = d.atype === 'card', sav = d.atype === 'save', inv = d.atype === 'invest'
    const cost = inv ? parse(d.cost) : NaN
    const day = (s: string) => { const v = Math.round(parse(s)); return card && v >= 1 && v <= 31 ? v : null }
    const opt = (s: string) => { const v = parse(s); return card && v >= 0 ? v : null }
    if (card && ((d.stmt && !day(d.stmt)) || (d.due && !day(d.due)))) return setErr('Statement and due days are days of the month, 1 to 31.')
    const id = act.saveAccount({
      id: old?.id, createdAt: old?.createdAt ?? undefined, name, type: d.atype, who: d.who, opening,
      bank: d.bank.trim() || null, last4: d.last4.trim() || null,
      limit: card ? parse(d.limit) || 0 : null, apr: card ? parse(d.apr) || null : null, apy: sav ? parse(d.apy) || 0 : null,
      cost: cost > 0 ? cost : undefined,
      statementDay: day(d.stmt), dueDay: day(d.due), minPct: opt(d.minPct), minFloor: opt(d.minFloor),
    })
    setView({ selAcct: id })
    close()
  }
  const del = () => {
    if (!old) return
    act.deleteAccount(old.id)
    setView({ selAcct: L.accounts.find((a) => a.id !== old.id)?.id ?? null })
    close()
  }

  return (
    <PanelFrame title={old ? 'Edit account' : 'New account'} err={err} onSave={save} onDelete={old ? del : undefined}>
      <div style={css('display:flex;flex-direction:column;gap:14px')}>
        <TextField label="Name" value={d.name} onChange={(v) => set('name', v)} />
        <ChipGroup label="Type" chips={chips<AccountType>(Object.entries(ACCOUNT_TYPES).map(([k, v]) => [k as AccountType, v[0]]), d.atype, (k) => set('atype', k))} />
        <ChipGroup grow label="Whose is it" chips={chips<Who>([['J', L.whoName.J], ['A', L.whoName.A], ['B', L.whoName.B]], d.who, (w) => set('who', w))} />
        <Pair>
          <TextField label={'Balance now (' + L.cur + '), minus if owed'} value={d.amt} onChange={(v) => set('amt', v)} />
          <TextField label="Bank or provider" value={d.bank} onChange={(v) => set('bank', v)} />
        </Pair>
        <TextField label="Last 4 digits (optional)" value={d.last4} onChange={(v) => set('last4', v.replace(/\D/g, '').slice(0, 4))} />
        {d.atype === 'card' && (
          <Pair>
            <TextField label="Credit limit" decimal value={d.limit} onChange={(v) => set('limit', v)} />
            <TextField label="Interest rate (APR %)" decimal placeholder={String(CARD_DEFAULTS.apr)} value={d.apr} onChange={(v) => set('apr', v)} />
          </Pair>
        )}
        {d.atype === 'card' && (
          <Pair>
            <TextField label="Statement day (of the month)" decimal placeholder="e.g. 20" value={d.stmt} onChange={(v) => set('stmt', v.replace(/\D/g, ''))} />
            <TextField label="Payment due day" decimal placeholder="e.g. 12" value={d.due} onChange={(v) => set('due', v.replace(/\D/g, ''))} />
          </Pair>
        )}
        {d.atype === 'card' && (
          <Pair>
            <TextField label="Minimum payment (% of balance)" decimal placeholder={String(CARD_DEFAULTS.minPct)} value={d.minPct} onChange={(v) => set('minPct', v)} />
            <TextField label={'Minimum at least (' + L.cur + ')'} decimal placeholder={String(CARD_DEFAULTS.minFloor)} value={d.minFloor} onChange={(v) => set('minFloor', v)} />
          </Pair>
        )}
        {d.atype === 'save' && <TextField label="Interest rate (% a year)" decimal value={d.apy} onChange={(v) => set('apy', v)} />}
        {d.atype === 'invest' && <TextField label="Amount you put in (optional)" decimal value={d.cost} onChange={(v) => set('cost', v)} />}
      </div>
    </PanelFrame>
  )
}
