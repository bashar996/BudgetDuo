// One loan, wide: what's owed and when the next installment is due, the summary,
// extra payment (with what it saves), settle early, the payments made and the full schedule.
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import type { Ledger } from '../data/ledger'
import { prepayEffect, type LoanState } from '../data/loans'
import { loanPayments } from '../data/ledger'
import { useStore } from '../data/store'
import { css, sx } from '../lib/css'
import { dLab, isoD, mLabel } from '../lib/dates'
import { pc } from '../lib/money'
import { useUI, type Panel } from '../shell/ui'
import { TxButton } from '../tabs/activity'
import { BTN_LINE, BTN_SOLID, inputStyle, PanelFrame } from './PanelFrame'
import { dueText, loanMeta, n2, ordinal, pct, r2, rateText, termText } from './loanBits'
import { parse } from './parts'

const H22 = css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")
const CARD = css('background:var(--card);border-radius:24px;padding:18px 20px;display:flex;flex-direction:column;gap:12px')
const PILL = "flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 18px;height:46px;border-radius:16px;cursor:pointer"
const TH = css('position:sticky;top:0;background:var(--bg);font-weight:500;font-size:12.5px;color:var(--mute);text-align:right;padding:8px 8px;border-bottom:1px solid var(--line);white-space:nowrap')
const TD = 'padding:7px 8px;text-align:right;white-space:nowrap'

function Line({ k, v, sub }: { k: string; v: ReactNode; sub?: string }) {
  return (
    <div style={css('display:flex;justify-content:space-between;align-items:baseline;gap:14px;padding:10px 0;border-bottom:1px solid var(--line)')}>
      <span style={css('font-size:14px;color:var(--mute);flex:none')}>{k}</span>
      <span style={css('text-align:right;min-width:0')}>
        <span style={css('font-size:15px;font-weight:500')}>{v}</span>
        {sub && <span style={css('display:block;font-size:12.5px;color:var(--mute)')}>{sub}</span>}
      </span>
    </div>
  )
}

export function LoanPanel({ L, id }: { L: Ledger; id: string }) {
  const ui = useUI()
  const { act } = useStore()
  const line = L.loanBy[id]
  const [mode, setMode] = useState<'' | 'settle' | 'delete'>('')
  const [extra, setExtra] = useState('')
  const [err, setErr] = useState('')
  // A loan deleted elsewhere (or not synced yet): give it a moment, then close.
  useEffect(() => { if (!line) { const t = setTimeout(ui.closeAll, 1500); return () => clearTimeout(t) } }, [!line])
  if (!line) return null

  const { doc: l, st, payments, bill } = line
  const { f, todayIso } = L
  const done = st.balance <= 0.005
  const self: Panel = { kind: 'loan', id }
  const due = dueText(st.nextDue, todayIso)
  const ex = parse(extra) || 0
  const eff = prepayEffect(l, loanPayments(L.data.tx, l.id), todayIso, ex)
  const fee = l.fee ?? 0
  const startYm = st.schedule[0]?.date.slice(0, 7)
  const agreedEnd = st.schedule[st.schedule.length - 1]?.date.slice(0, 7)
  const viaBill = bill && st.nextDue && !bill.paid?.[st.nextDue.slice(0, 7)]

  const paid = (what: string, t: ReturnType<typeof act.payLoan>) => { if (t) ui.toast(what, () => act.deleteTx(t)) }
  const payInst = () => paid('Paid ' + f(r2(viaBill ? bill!.amt : st.installment)) + ' on ' + l.name, act.payLoan(l, 'installment', st.installment))
  const payExtra = () => {
    if (!(ex > 0)) return setErr('Type the extra amount first.')
    const amt = Math.min(ex, r2(st.balance))
    paid('Paid ' + f(amt) + ' extra on ' + l.name, act.payLoan(l, 'extra', amt))
    setExtra('')
  }
  const settle = () => {
    if (mode !== 'settle') { setErr(''); return setMode('settle') }
    paid('Settled ' + l.name + ' with ' + f(r2(st.settlement)), act.payLoan(l, 'extra', r2(st.settlement)))
    setMode('')
  }
  const del = () => {
    if (mode !== 'delete') { setMode('delete'); return setErr('Delete ' + l.name + (bill ? ' and its bill' : '') + '? Its ' + payments.length + ' payments stay in Activity as ordinary expenses.') }
    act.deleteLoan(l)
    ui.toast('Deleted ' + l.name)
    ui.closeAll()
  }

  const head = (
    <div style={css('padding:14px 0 6px;display:flex;flex-direction:column;gap:10px')}>
      <div style={css('font-size:13.5px;color:#3a3566')}>{loanMeta(l) + (st.simple ? '' : ' · ' + termText(st.termMonths!))}</div>
      <div style={css('display:flex;flex-wrap:wrap;align-items:flex-end;justify-content:space-between;gap:10px 28px')}>
        <div>
          <div style={css('font-size:13px;color:#3a3566')}>{done ? 'Paid off' : 'Outstanding'}</div>
          <div style={css("font:500 60px/1 'Geist',sans-serif;letter-spacing:-.045em;margin-top:4px")}>{f(Math.round(st.balance))}</div>
        </div>
        {!st.simple && (
          <div style={css('flex:1;min-width:240px;max-width:460px;padding-bottom:6px')}>
            <div style={css('display:flex;justify-content:space-between;font-size:13px;font-weight:500')}>
              <span>{st.installmentsPaid + ' of ' + st.termMonths + ' paid'}</span>
              <span style={css('color:#3a3566')}>{Math.round(st.progress * 100) + '% of ' + f(st.principal) + ' repaid'}</span>
            </div>
            <div style={css('height:8px;border-radius:4px;background:rgba(11,11,12,.16);margin-top:8px')}>
              <div style={sx('height:100%;border-radius:4px;background:#0b0b0c', { width: pc(st.progress) })} />
            </div>
          </div>
        )}
      </div>
    </div>
  )

  return (
    <PanelFrame wide title={l.name} head={head} err={err}
      onDelete={del} deleteLabel={mode === 'delete' ? 'Confirm delete' : 'Delete'}
      actions={<>
        <button type="button" onClick={() => ui.open({ kind: 'loanForm', id, back: self })} style={BTN_LINE}>Edit</button>
        {!done && <button type="button" onClick={payInst} style={BTN_SOLID}>{'Pay installment · ' + f(r2(viaBill ? bill!.amt : st.installment))}</button>}
      </>}>
      <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,360px),1fr));gap:26px 34px;align-items:start;padding-bottom:10px')}>
        <div style={css('display:flex;flex-direction:column;gap:22px;min-width:0')}>
          {!done && (
            <div style={CARD}>
              <div style={css('display:flex;justify-content:space-between;align-items:baseline;gap:10px')}>
                <span style={css('font-size:13px;color:var(--mute)')}>Next installment</span>
                <span style={sx('font-size:13.5px;font-weight:500', { color: due.bad ? 'var(--bad)' : 'var(--ink)' })}>{due.text}</span>
              </div>
              <div style={css("font:500 30px 'Geist',sans-serif;letter-spacing:-.02em")}>{f(r2(st.installment))}</div>
              <div style={css('font-size:13px;color:var(--mute);text-wrap:pretty')}>
                {'From ' + L.aName(l.acct ?? L.mainAcct) + (bill ? '. Also under Bills on the ' + ordinal(bill.day) + '; paying either one counts once.' : '.')}
              </div>
            </div>
          )}
          {st.simple && (
            <div style={CARD}>
              <div style={css('font-size:15px;font-weight:500')}>Add the loan details for a full schedule</div>
              <div style={css('font-size:13.5px;color:var(--mute);text-wrap:pretty')}>This loan only has a balance and a monthly payment. With the amount borrowed, the term and the first payment date, Twofold works out the schedule, interest and end date the way your lender does.</div>
              <button type="button" onClick={() => ui.open({ kind: 'loanForm', id, back: self })} style={sx(PILL, { alignSelf: 'flex-start', border: 'none', background: 'var(--btn)', color: 'var(--btnInk)' })}>Add details</button>
            </div>
          )}

          <section>
            <span style={H22}>Summary</span>
            <div style={css('margin-top:4px')}>
              {!st.simple && <Line k="Borrowed" v={f(st.principal)} sub={startYm ? 'first installment ' + mLabel(startYm, true) : undefined} />}
              <Line k="Outstanding" v={f(r2(st.balance))} />
              <Line k="Installment" v={f(r2(st.installment)) + ' a month'} sub={l.installment ? 'as on your bank statement' : st.simple ? undefined : 'worked out from the rate and term'} />
              <Line k="Rate" v={rateText(l, st, todayIso)} sub={(l.rateChanges ?? []).length && st.rateType === 'reducing' ? (l.rateChanges ?? []).map((c) => pct(c.rate) + ' from ' + mLabel(c.from, true)).join(' · ') : undefined} />
              {!st.simple && <Line k="Term" v={termText(st.termMonths!)} sub={startYm && agreedEnd ? mLabel(startYm, true) + ' → ' + mLabel(agreedEnd, true) + ' as agreed' : undefined} />}
              <Line k="Ends" v={done ? 'Paid off' : st.endsYm ? mLabel(st.endsYm, true) : 'Not at this pace'} sub={done ? undefined : st.installmentsLeft + ' installments to go'} />
              <Line k="Interest paid" v={f(Math.round(st.interestPaid))} />
              <Line k="Interest to go" v={f(Math.round(st.interestLeft))} sub={st.simple ? undefined : f(Math.round(st.totalInterest)) + ' over the whole loan'} />
              <Line k="Total left to pay" v={f(Math.round(st.totalLeft))} />
              {!done && <Line k="Settle today" v={f(r2(st.settlement))} sub={fee ? 'includes a ' + pct(fee) + ' early-settlement fee' : 'no early-settlement fee'} />}
            </div>
          </section>

          {!done && (
            <section style={CARD}>
              <span style={css("font:500 18px 'Geist',sans-serif;letter-spacing:-.01em")}>Pay extra</span>
              <div style={css('display:flex;gap:8px')}>
                <input className="h-focus-ink" inputMode="decimal" aria-label="Extra payment" placeholder={'Amount (' + L.cur + ')'} value={extra}
                  onChange={(e) => { setErr(''); setExtra(e.target.value.replace(/[^0-9.,]/g, '')) }}
                  onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); payExtra() } }}
                  style={sx('', { ...inputStyle, background: 'var(--bg)', flex: 1, minWidth: 0 })} />
                <button type="button" onClick={payExtra} style={sx(PILL, { height: 52, border: 'none', background: 'var(--btn)', color: 'var(--btnInk)' })}>Pay extra</button>
              </div>
              <div style={css('font-size:13.5px;text-wrap:pretty')}>
                {ex > 0
                  ? (eff.interestSaved > 0.5 || eff.monthsSaved > 0
                    ? 'Saves ' + f(Math.round(eff.interestSaved)) + ' interest and ' + eff.monthsSaved + (eff.monthsSaved === 1 ? ' month' : ' months') + ', keeping the same installment.'
                    : 'Too small to change the end date or the interest much.')
                  : 'Paying extra cuts the balance straight away. Type an amount to see what it saves.'}
              </div>
              <div style={css('border-top:1px solid var(--line);padding-top:12px;display:flex;flex-wrap:wrap;align-items:center;gap:10px')}>
                <span style={css('flex:1;min-width:180px;font-size:13.5px;text-wrap:pretty')}>
                  {mode === 'settle'
                    ? 'Pay ' + f(r2(st.settlement)) + ' from ' + L.aName(l.acct ?? L.mainAcct) + ' now and close the loan?'
                    : 'Settle early: clear it today for ' + f(r2(st.settlement)) + (fee ? ', fee included.' : '.')}
                </span>
                {mode === 'settle' && <button type="button" onClick={() => setMode('')} style={sx(PILL, { border: '1px solid var(--chip)', background: 'transparent', color: 'var(--ink)' })}>Cancel</button>}
                <button type="button" onClick={settle} style={sx(PILL, { border: '1.5px solid var(--ink)', background: mode === 'settle' ? 'var(--ink)' : 'transparent', color: mode === 'settle' ? 'var(--bg)' : 'var(--ink)' })}>{mode === 'settle' ? 'Confirm settle' : 'Settle early'}</button>
              </div>
            </section>
          )}

          <section>
            <div style={css('display:flex;justify-content:space-between;align-items:baseline;gap:10px')}>
              <span style={H22}>Payments made</span>
              <span style={css('font-size:13px;color:var(--mute)')}>{payments.length ? f(Math.round(payments.reduce((a, t) => a + t.amt, 0))) + ' in Twofold' : ''}</span>
            </div>
            {payments.map((t) => <TxButton key={t.id} L={L} t={t} badge={false} back={self} />)}
            {!payments.length && <div style={css('padding:8px 0;font-size:14px;color:var(--mute);text-wrap:pretty')}>No payments logged yet. Pay an installment here or from Bills.</div>}
            {(l.paidBefore ?? 0) > 0 && <div style={css('font-size:12.5px;color:var(--mute);padding-top:10px')}>{'Plus ' + l.paidBefore + ' installments paid before the loan was added.'}</div>}
          </section>
        </div>

        {!st.simple && <Schedule L={L} st={st} />}
      </div>
    </PanelFrame>
  )

}

/** The schedule as agreed: paid rows ticked, the next one highlighted, overdue ones in red. */
function Schedule({ L, st }: { L: Ledger; st: LoanState }) {
  const agreedEnd = st.schedule[st.schedule.length - 1]?.date.slice(0, 7)
  const box = useRef<HTMLDivElement>(null)
  const next = st.schedule.findIndex((r) => !r.paid)
  // Start with the next installment in view.
  useLayoutEffect(() => {
    const el = box.current, row = el?.querySelector<HTMLElement>('[data-next]')
    if (el && row) el.scrollTop = Math.max(0, row.offsetTop - 120)
  }, [])
  return (
    <section style={css('min-width:0;position:sticky;top:12px')}>
      <div style={css('display:flex;justify-content:space-between;align-items:baseline;gap:10px')}>
        <span style={H22}>Payment schedule</span>
        <span style={css('font-size:13px;color:var(--mute)')}>{st.schedule.length + ' installments'}</span>
      </div>
      <div ref={box} style={css('max-height:calc(100vh - 230px);min-height:260px;overflow:auto;margin-top:8px;border-radius:16px')}>
        <table style={css('width:100%;border-collapse:collapse;font-size:13.5px;font-variant-numeric:tabular-nums')}>
          <thead>
            <tr>
              <th style={sx('', { ...TH, textAlign: 'left' })}>#</th>
              <th style={sx('', { ...TH, textAlign: 'left' })}>Date</th>
              <th style={TH}>Payment</th>
              <th style={TH}>Interest</th>
              <th style={TH}>Principal</th>
              <th style={TH}>Balance</th>
            </tr>
          </thead>
          <tbody>
            {st.schedule.map((r, i) => {
              const isNext = i === next, late = !r.paid && r.date < L.todayIso
              return (
                <tr key={r.n} data-next={isNext ? '' : undefined} title={r.paid ? 'Paid' : late ? 'Overdue' : undefined}
                  style={sx('', { background: isNext ? 'var(--acc)' : 'transparent', color: r.paid ? 'var(--mute)' : late ? 'var(--bad)' : 'var(--ink)', fontWeight: isNext ? 500 : 400 })}>
                  <td style={sx(TD, { textAlign: 'left', borderRadius: isNext ? '10px 0 0 10px' : undefined })}>{r.paid ? '✓' : r.n}</td>
                  <td style={sx(TD, { textAlign: 'left' })}>{dLab(isoD(r.date)).slice(4) + ' ' + r.date.slice(0, 4)}</td>
                  <td style={css(TD)}>{n2(r.payment)}</td>
                  <td style={css(TD)}>{n2(r.interest)}</td>
                  <td style={css(TD)}>{n2(r.principal)}</td>
                  <td style={sx(TD, { borderRadius: isNext ? '0 10px 10px 0' : undefined })}>{L.num(Math.round(r.balance))}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      <div style={css('font-size:12.5px;color:var(--mute);padding-top:10px;text-wrap:pretty')}>
        {'As agreed with the lender, in ' + L.cur + '. Ticked rows are paid' + (st.endsYm && agreedEnd && st.endsYm !== agreedEnd ? '; with what you’ve paid so far it now ends ' + mLabel(st.endsYm, true) + '.' : '.')}
      </div>
    </section>
  )
}
