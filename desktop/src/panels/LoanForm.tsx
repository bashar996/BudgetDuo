// New / edit loan: what was borrowed, the rate (reducing or flat), the term and the first
// payment date. The installment is worked out unless the bank's figure is typed in.
// A live line at the bottom shows the installment, the interest and the end date.
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import type { Debt } from '../data/types'
import { flatToReducing, installmentOf, isSimple, loanState, nthDue, type RateType } from '../data/loans'
import { loanPayments } from '../data/ledger'
import { useStore } from '../data/store'
import { css, sx } from '../lib/css'
import { addM, dim, dLab, isoD, mLabel, pad } from '../lib/dates'
import { useUI } from '../shell/ui'
import { Field, inputStyle, PanelFrame } from './PanelFrame'
import { ChipGroup, chips, Pair, Pill, Switch, TextField, parse } from './parts'
import { LOAN_KINDS, pct, r2, termText, type LoanKind } from './loanBits'

interface Draft {
  name: string; kind: LoanKind; lender: string; principal: string; rate: string; rateType: RateType
  years: string; months: string; due: string; installment: string; paidBefore: string
  acct: string; inBills: boolean; fee: string; changes: { from: string; rate: string }[]
}

const isDate = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s)
/** The first installment's date, given the date of installment n + 1 (n already paid). */
const backDate = (due: string, n: number) => {
  const ym = addM(due.slice(0, 7), -n)
  return ym + '-' + pad(Math.min(Number(due.slice(8, 10)) || 1, dim(ym)))
}

export function LoanForm({ L, id }: { L: Ledger; id?: string }) {
  const { act } = useStore()
  const ui = useUI()
  const line = id ? L.loanBy[id] : undefined
  const old = line?.doc
  const [d, setD] = useState<Draft>(() => {
    const t = old?.termMonths ?? 0
    return {
      name: old?.name ?? '', kind: old?.kind ?? 'personal', lender: old?.lender ?? '',
      principal: old?.principal ? String(old.principal) : '', rate: old ? String(old.rate ?? old.apr ?? '') : '',
      rateType: old?.rateType ?? 'reducing',
      years: t ? String(Math.floor(t / 12)) : '', months: t ? String(t % 12 || '') : '',
      // The date asked for is installment (already paid + 1): the first one paid in Twofold.
      due: old?.firstDue ? nthDue(old.firstDue, old.paidBefore ?? 0) : '', installment: old?.installment ? String(old.installment) : '',
      paidBefore: old?.paidBefore ? String(old.paidBefore) : '',
      acct: old?.acct ?? L.mainAcct, inBills: old ? !!line?.bill : true, fee: old?.fee ? String(old.fee) : '',
      changes: (old?.rateChanges ?? []).map((c) => ({ from: c.from, rate: String(c.rate) })),
    }
  })
  const [err, setErr] = useState('')
  const [delStep, setDelStep] = useState(false)
  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => { setErr(''); setD((x) => ({ ...x, [k]: v })) }
  const f = L.f

  // The loan as typed so far, for the placeholder and the live summary.
  const principal = parse(d.principal), rate = parse(d.rate) || 0
  const term = Math.round((parseInt(d.years) || 0) * 12 + (parseInt(d.months) || 0))
  const paidN = Math.round(Math.max(0, Math.min(term || Infinity, parseInt(d.paidBefore) || 0)))
  const firstDue = isDate(d.due) ? backDate(d.due, paidN) : ''
  const ready = principal > 0 && term > 0 && isDate(firstDue)
  const changes = d.rateType === 'reducing'
    ? d.changes.filter((c) => /^\d{4}-\d{2}$/.test(c.from) && !isNaN(parse(c.rate))).map((c) => ({ from: c.from, rate: parse(c.rate) })).sort((a, b) => (a.from < b.from ? -1 : 1))
    : []
  const bank = parse(d.installment)
  const doc: Debt = {
    ...(old ?? {}), id: old?.id ?? 'draft', name: d.name.trim(), kind: d.kind, lender: d.lender.trim() || null,
    principal: principal > 0 ? principal : null, rate, rateType: d.rateType, termMonths: term || null,
    firstDue: firstDue || null, installment: bank > 0 ? bank : null,
    paidBefore: paidN || null,
    rateChanges: changes.length ? changes : null, fee: parse(d.fee) > 0 ? parse(d.fee) : null, acct: d.acct || null,
    billId: old?.billId ?? null, balance: principal > 0 ? principal : old?.balance ?? 0, apr: rate, min: old?.min ?? 0,
  }
  const calc = ready ? installmentOf({ ...doc, installment: null }) : 0
  const st = ready ? loanState(doc, old ? loanPayments(L.data.tx, old.id) : [], L.todayIso) : null
  const ends = st ? st.endsYm ?? st.schedule[st.schedule.length - 1]?.date.slice(0, 7) : null
  // Installments due before today by the schedule, less those already logged in Twofold.
  let dueSoFar = 0
  if (ready) while (dueSoFar < term && nthDue(firstDue, dueSoFar) < L.todayIso) dueSoFar++
  const logged = old ? line!.payments.filter((t) => (t.debtPart ?? 'installment') === 'installment').length : 0
  const suggest = Math.max(0, dueSoFar - logged)

  const save = () => {
    if (!doc.name) return setErr('Give the loan a name.')
    // An older simple loan can be renamed or moved without adding the full details.
    const keepSimple = !!old && isSimple(old) && !(principal > 0) && !(term > 0)
    if (!keepSimple) {
      if (!(principal > 0)) return setErr('Add the amount borrowed.')
      if (!(term > 0)) return setErr('Add the term, in years or months.')
      if (!isDate(d.due)) return setErr(paidN ? 'Add the date of installment ' + (paidN + 1) + ', your next one.' : 'Add the date of the first installment.')
    }
    if (rate < 0 || rate > 100) return setErr('The interest rate looks off. Use a yearly % like 7.9.')
    const { id: _draft, ...rest } = doc
    const nid = act.saveLoan({ ...rest, id: old?.id, createdAt: old?.createdAt ?? undefined }, d.inBills)
    if (old) ui.close()
    else ui.open({ kind: 'loan', id: nid })
  }
  const del = !old ? undefined : () => {
    if (!delStep) { setDelStep(true); return setErr('Delete ' + old.name + (line?.bill ? ' and its bill' : '') + '? Its payments stay in Activity as ordinary expenses.') }
    act.deleteLoan(old)
    ui.toast('Deleted ' + old.name)
    ui.closeAll()
  }
  const setChange = (i: number, k: 'from' | 'rate', v: string) => set('changes', d.changes.map((c, j) => (j === i ? { ...c, [k]: v } : c)))
  const payers = L.accounts.filter((a) => a.type === 'current' || a.type === 'cash' || a.type === 'save')

  return (
    <PanelFrame title={old ? 'Edit loan' : 'New loan'} err={err} onSave={save} onDelete={del} deleteLabel={delStep ? 'Confirm delete' : 'Delete'}>
      <div style={css('display:flex;flex-direction:column;gap:16px')}>
        {old && line?.st.simple && (
          <div style={css('font-size:13.5px;text-wrap:pretty')}>
            {'Add what you borrowed, the term and the first payment date for a full schedule. Until then it uses the balance of ' + f(old.balance) + ' and ' + f(old.min) + ' a month.'}
          </div>
        )}
        <TextField label="Name" placeholder="e.g. Car loan" value={d.name} onChange={(v) => set('name', v)} />
        <ChipGroup label="Kind" chips={chips<LoanKind>(LOAN_KINDS, d.kind, (k) => set('kind', k))} />
        <Pair>
          <TextField label="Lender (optional)" value={d.lender} onChange={(v) => set('lender', v)} />
          <TextField label={'Amount borrowed (' + L.cur + ')'} decimal value={d.principal} onChange={(v) => set('principal', v)} />
        </Pair>
        <div style={css('display:flex;flex-direction:column;gap:10px')}>
          <Pair>
            <TextField label="Interest rate (% a year)" decimal placeholder="0" value={d.rate} onChange={(v) => set('rate', v)} />
            <ChipGroup grow label="Charged on" chips={chips<RateType>([['reducing', 'Reducing'], ['flat', 'Flat']], d.rateType, (k) => set('rateType', k))} />
          </Pair>
          <div style={css('font-size:12.5px;color:var(--mute);text-wrap:pretty')}>
            {d.rateType === 'flat'
              ? 'Flat: interest on the full amount borrowed for the whole term, common for car and personal loans.' + (rate > 0 && term > 0 ? ' ' + pct(rate) + ' flat costs the same as ' + pct(flatToReducing(rate, term), 1) + ' reducing.' : '')
              : 'Reducing: interest only on what’s still owed, like most bank loans and mortgages.'}
          </div>
        </div>
        <Pair>
          <TextField label="Term: years" decimal value={d.years} onChange={(v) => set('years', v.replace(/\D/g, ''))} />
          <TextField label="and months" decimal value={d.months} onChange={(v) => set('months', v.replace(/\D/g, ''))} />
        </Pair>
        <Pair>
          <TextField label="Installments already paid" decimal placeholder="0" value={d.paidBefore} onChange={(v) => set('paidBefore', v.replace(/\D/g, ''))} />
          <Field label={paidN ? 'Installment ' + (paidN + 1) + ' due (your next)' : 'First installment due'}>
            <input type="date" className="h-focus-ink" value={d.due} onChange={(e) => set('due', e.target.value)} style={inputStyle} />
          </Field>
        </Pair>
        {ready && suggest > paidN && (
          // Moving installments into "already paid" keeps the first installment's date put.
          <Pill onClick={() => setD((x) => ({ ...x, paidBefore: String(suggest), due: nthDue(firstDue, suggest) }))}>
            {'Mark ' + suggest + ' as paid: the ones due before today' + (logged ? ' not logged here' : '')}
          </Pill>
        )}
        <TextField label="Installment, as on your bank statement (optional)" decimal placeholder={calc ? L.num(r2(calc)) + ' worked out' : 'Worked out for you'}
          value={d.installment} onChange={(v) => set('installment', v)} />
        <ChipGroup label="Pays from" chips={payers.map((a) => ({ key: a.id, label: a.name, on: d.acct === a.id, pick: () => set('acct', a.id) }))} />
        <Switch label="Show installments in Bills" on={d.inBills} onChange={(v) => set('inBills', v)} />
        <TextField label="Early settlement fee (% of what’s owed, optional)" decimal placeholder="0" value={d.fee} onChange={(v) => set('fee', v)} />
        {d.rateType === 'reducing' && (
          <div style={css('display:flex;flex-direction:column;gap:8px')}>
            <div>
              <div style={css('font-size:13px;color:var(--mute)')}>Rate changes</div>
              <div style={css('font-size:12.5px;color:var(--mute);text-wrap:pretty')}>For variable rates: from that month on, the new rate. The installment is worked out again over the months left.</div>
            </div>
            {d.changes.map((c, i) => (
              <div key={i} style={css('display:flex;gap:8px;align-items:center')}>
                <input type="month" aria-label="From month" className="h-focus-ink" value={c.from} onChange={(e) => setChange(i, 'from', e.target.value)} style={sx('', { ...inputStyle, flex: 1.3, minWidth: 0 })} />
                <input inputMode="decimal" aria-label="New rate %" placeholder="Rate %" className="h-focus-ink" value={c.rate} onChange={(e) => setChange(i, 'rate', e.target.value)} style={sx('', { ...inputStyle, flex: 1, minWidth: 0 })} />
                <button type="button" aria-label="Remove rate change" onClick={() => set('changes', d.changes.filter((_, j) => j !== i))}
                  style={css('width:44px;height:44px;flex:none;border:1px solid var(--chip);border-radius:15px;background:transparent;color:var(--ink);font-size:18px;cursor:pointer')}>×</button>
              </div>
            ))}
            <Pill onClick={() => set('changes', [...d.changes, { from: '', rate: '' }])}>+ Add rate change</Pill>
          </div>
        )}
        <div style={css('background:#0b0b0c;color:#ffffff;border-radius:20px;padding:16px 18px;display:flex;flex-direction:column;gap:4px')}>
          {st ? (
            <>
              <span style={css("font:500 18px 'Geist',sans-serif;letter-spacing:-.01em")}>
                {f(r2(installmentOf(doc))) + '/month · ' + f(Math.round(st.totalInterest)) + ' interest · ends ' + (ends ? mLabel(ends, true) : '—')}
              </span>
              <span style={css('font-size:12.5px;color:#a9a7b8')}>
                {termText(term) + ' · ' + f(Math.round(principal + st.totalInterest)) + ' in total' + (st.installmentsPaid ? ' · ' + f(Math.round(st.balance)) + ' still owed today' : '')}
              </span>
              <span style={css('font-size:12.5px;color:#d9d7e4')}>
                {(st.nextDue ? 'Installment ' + (st.installmentsPaid + 1) + ' of ' + term + ' due ' + dLab(isoD(st.nextDue)) + ' ' + st.nextDue.slice(0, 4) : 'All ' + term + ' installments paid')
                  + ' · first one ' + dLab(isoD(firstDue)) + ' ' + firstDue.slice(0, 4)}
              </span>
            </>
          ) : (
            <span style={css('font-size:14px;color:#a9a7b8')}>Add the amount, term and first installment to see the monthly payment, the interest and the end date.</span>
          )}
        </div>
      </div>
    </PanelFrame>
  )
}
