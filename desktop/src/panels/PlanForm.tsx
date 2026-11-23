// New / edit card installment plan: what was bought, on which card, the amount, months and rate,
// how many were billed before, and the date of the next one. The live line at the bottom shows
// the installment, interest and end date, and what Twofold will post on the card straight away.
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import type { Debt } from '../data/types'
import { installmentOf, nthDue, planChargesDue, planInstallmentAmount, type RateType } from '../data/loans'
import { loanPayments } from '../data/ledger'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { addM, dim, dLab, isoD, mLabel, pad } from '../lib/dates'
import { useUI } from '../shell/ui'
import { Field, inputStyle, PanelFrame } from './PanelFrame'
import { ChipGroup, chips, Pair, Pill, TextField, parse } from './parts'
import { ordinal, pct, r2, termText } from './loanBits'

const isDate = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s)
/** The first installment's date, given the date of installment n + 1 (n already billed). */
const backDate = (due: string, n: number) => {
  const ym = addM(due.slice(0, 7), -n)
  return ym + '-' + pad(Math.min(Number(due.slice(8, 10)) || 1, dim(ym)))
}

export function PlanForm({ L, id, acct }: { L: Ledger; id?: string; acct?: string }) {
  const { act } = useStore()
  const ui = useUI()
  const line = id ? L.planBy[id] : undefined
  const old = line?.doc
  const cards = L.accounts.filter((a) => a.type === 'card')
  const [d, setD] = useState(() => ({
    name: old?.name ?? '', acct: old?.acct ?? acct ?? cards[0]?.id ?? '',
    principal: old?.principal ? String(old.principal) : '', months: old?.termMonths ? String(old.termMonths) : '',
    rate: old?.rate ? String(old.rate) : '', rateType: (old?.rateType ?? 'flat') as RateType,
    procFee: old?.procFee ? String(old.procFee) : '', paidBefore: old?.paidBefore ? String(old.paidBefore) : '',
    // As in the loan form, the date asked for is the first installment Twofold posts.
    due: old?.firstDue ? nthDue(old.firstDue, old.paidBefore ?? 0) : '',
    cat: L.catOr(old?.cat || 'shopping'), fee: old?.fee ? String(old.fee) : '',
  }))
  const [err, setErr] = useState('')
  const [delStep, setDelStep] = useState(false)
  const set = <K extends keyof typeof d>(k: K, v: (typeof d)[K]) => { setErr(''); setD((x) => ({ ...x, [k]: v })) }
  const f = L.f

  // The plan as typed so far, for the live summary.
  const principal = parse(d.principal), rate = parse(d.rate) || 0, term = Math.round(parseInt(d.months) || 0)
  const paidN = Math.round(Math.max(0, Math.min(term || Infinity, parseInt(d.paidBefore) || 0)))
  const firstDue = isDate(d.due) ? backDate(d.due, paidN) : ''
  const ready = principal > 0 && term > 0 && isDate(firstDue)
  const procFee = parse(d.procFee)
  const doc: Debt = {
    ...(old ?? {}), id: old?.id ?? 'draft', name: d.name.trim(), kind: 'cardplan', acct: d.acct || null,
    principal: principal > 0 ? principal : null, rate, rateType: d.rateType, termMonths: term || null, firstDue: firstDue || null,
    installment: null, paidBefore: paidN || null, fee: parse(d.fee) > 0 ? parse(d.fee) : null, cat: d.cat,
    procFee: procFee > 0 ? procFee : null, billedThrough: Math.max(paidN, old?.billedThrough ?? old?.paidBefore ?? 0),
    balance: principal > 0 ? principal : 0, apr: rate, min: 0,
  }
  const sched = ready ? planChargesDue(doc, old ? loanPayments(L.data.tx, old.id) : [], L.todayIso) : []
  const inst = ready ? installmentOf(doc) : 0
  const interest = ready ? r2(Array.from({ length: term }, (_, i) => planInstallmentAmount(doc, i + 1)).reduce((a, x) => a + x, 0) - principal) : 0
  const endYm = ready ? nthDue(firstDue, term - 1).slice(0, 7) : ''
  // Installments due before today by the schedule: offer to count them as billed before Twofold.
  let dueSoFar = 0
  if (ready) while (dueSoFar < term && nthDue(firstDue, dueSoFar) < L.todayIso) dueSoFar++
  const suggest = old ? 0 : dueSoFar

  const save = () => {
    if (!doc.name) return setErr('Add what you bought.')
    if (!d.acct) return setErr(cards.length ? 'Pick the card it’s on.' : 'Add the credit card under Accounts first.')
    if (!(principal > 0)) return setErr('Add the amount.')
    if (!(term > 0)) return setErr('Add the number of months.')
    if (!isDate(d.due)) return setErr(paidN ? 'Add the date of installment ' + (paidN + 1) + ', your next one.' : 'Add the date of the first installment.')
    if (rate < 0 || rate > 100) return setErr('The rate looks off. Use a yearly % like 0 or 12.')
    const { id: _draft, ...rest } = doc
    const nid = act.savePlan({ ...rest, id: old?.id, createdAt: old?.createdAt ?? undefined })
    if (old) return ui.close()
    ui.toast('Added ' + doc.name + (sched.length ? ': ' + sched.length + (sched.length === 1 ? ' installment' : ' installments') + ' posted on ' + L.aName(d.acct) : ''))
    ui.open({ kind: 'loan', id: nid })
  }
  const del = !old ? undefined : () => {
    if (!delStep) { setDelStep(true); return setErr('Delete the ' + old.name + ' plan? What’s been posted stays on the card as ordinary expenses.') }
    act.deleteLoan(old)
    ui.toast('Deleted ' + old.name)
    ui.closeAll()
  }

  return (
    <PanelFrame title={old ? 'Edit installment plan' : 'New installment plan'} err={err} onSave={save} onDelete={del} deleteLabel={delStep ? 'Confirm delete' : 'Delete'}>
      <div style={css('display:flex;flex-direction:column;gap:16px')}>
        <div style={css('font-size:13.5px;text-wrap:pretty')}>A purchase your bank split into monthly installments on the card. Each installment is posted on the card in its month, so your budget counts it then, not the full price at once.</div>
        <TextField label="What you bought" placeholder="e.g. Phone" value={d.name} onChange={(v) => set('name', v)} />
        {cards.length
          ? <ChipGroup label="Card" chips={cards.map((a) => ({ key: a.id, label: a.name, on: d.acct === a.id, pick: () => set('acct', a.id) }))} />
          : <div style={css('font-size:13.5px;color:var(--bad)')}>Add the credit card under Accounts first.</div>}
        <Pair>
          <TextField label={'Amount (' + L.cur + ')'} decimal value={d.principal} onChange={(v) => set('principal', v)} />
          <TextField label="Months" decimal placeholder="e.g. 12" value={d.months} onChange={(v) => set('months', v.replace(/\D/g, ''))} />
        </Pair>
        <div style={css('display:flex;flex-direction:column;gap:10px')}>
          <Pair>
            <TextField label="Rate (% a year)" decimal placeholder="0" value={d.rate} onChange={(v) => set('rate', v)} />
            <ChipGroup grow label="Charged on" chips={chips<RateType>([['flat', 'Flat'], ['reducing', 'Reducing']], d.rateType, (k) => set('rateType', k))} />
          </Pair>
          <div style={css('font-size:12.5px;color:var(--mute);text-wrap:pretty')}>Most plans are 0%. With a rate, flat charges it on the full amount for every month, reducing only on what’s left.</div>
        </div>
        <Pair>
          <TextField label={'Processing fee (' + L.cur + ', optional)'} decimal placeholder="0" value={d.procFee} onChange={(v) => set('procFee', v)} />
          <TextField label="Installments already billed" decimal placeholder="0" value={d.paidBefore} onChange={(v) => set('paidBefore', v.replace(/\D/g, ''))} />
        </Pair>
        <Field label={paidN ? 'Installment ' + (paidN + 1) + ' due (your next)' : 'First installment'}>
          <input type="date" className="h-focus-ink" value={d.due} onChange={(e) => set('due', e.target.value)} style={inputStyle} />
        </Field>
        {ready && suggest > paidN && (
          <Pill onClick={() => setD((x) => ({ ...x, paidBefore: String(suggest), due: nthDue(firstDue, suggest) }))}>
            {'Mark ' + suggest + ' as already billed: the ones due before today'}
          </Pill>
        )}
        <ChipGroup label="Category" chips={L.cats.map((c) => ({ key: c.id, label: c.name, on: d.cat === c.id, pick: () => set('cat', c.id) }))} />
        <TextField label="Early-closure fee (% of what’s left, optional)" decimal placeholder="0" value={d.fee} onChange={(v) => set('fee', v)} />
        <div style={css('background:#0b0b0c;color:#ffffff;border-radius:20px;padding:16px 18px;display:flex;flex-direction:column;gap:4px')}>
          {ready ? (
            <>
              <span style={css("font:500 18px 'Geist',sans-serif;letter-spacing:-.01em")}>
                {f(r2(inst)) + '/month · ' + (interest > 0.005 ? f(Math.round(interest)) + ' interest' : 'no interest') + ' · ends ' + mLabel(endYm, true)}
              </span>
              <span style={css('font-size:12.5px;color:#a9a7b8')}>
                {termText(term) + ' · ' + f(r2(principal + interest)) + ' in total' + (rate > 0 ? ' · ' + pct(rate) + ' ' + d.rateType : '') + (procFee > 0 ? ' · plus ' + f(procFee) + ' processing fee' : '')}
              </span>
              <span style={css('font-size:12.5px;color:#d9d7e4;text-wrap:pretty')}>
                {paidN >= term ? 'All ' + term + ' installments already billed.'
                  : sched.length
                    ? (old ? '' : 'On saving, ') + sched.length + (sched.length === 1 ? ' installment' : ' installments') + ' due by today ' + (old ? 'will be' : 'are') + ' posted on the card; then one on the ' + ordinal(Number(firstDue.slice(8, 10))) + ' each month.'
                    : 'Installment ' + (paidN + 1) + ' of ' + term + ' is posted ' + dLab(isoD(nthDue(firstDue, paidN))) + ' ' + nthDue(firstDue, paidN).slice(0, 4) + ', in ' + L.catOf(d.cat).name + '.'}
              </span>
            </>
          ) : (
            <span style={css('font-size:14px;color:#a9a7b8')}>Add the amount, months and first installment to see the monthly amount and when it ends.</span>
          )}
        </div>
      </div>
    </PanelFrame>
  )
}
