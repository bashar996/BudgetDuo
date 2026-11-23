// One card installment plan, wide (the loan panel's layout): what's still to be billed, the next
// installment Twofold will post on the card, the summary, close early, the entries posted on the
// card and the schedule. There's no Pay button: each installment bills itself (store.tsx billPlans).
import { useEffect, useState } from 'react'
import type { Ledger } from '../data/ledger'
import { useStore } from '../data/store'
import { css, sx } from '../lib/css'
import { dLab, isoD, mLabel } from '../lib/dates'
import { pc } from '../lib/money'
import { useUI, type Panel } from '../shell/ui'
import { TxButton } from '../tabs/activity'
import { BTN_LINE, PanelFrame } from './PanelFrame'
import { Line, Schedule } from './LoanPanel'
import { ordinal, pct, r2, rateText, termText } from './loanBits'

const H22 = css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")
const CARD = css('background:var(--card);border-radius:24px;padding:18px 20px;display:flex;flex-direction:column;gap:12px')
const PILL = "flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 18px;height:46px;border-radius:16px;cursor:pointer"

/** "0% · interest-free" or the loan wording ("3.5% flat ≈ 6.6% reducing"). */
export const planRate = (L: Ledger, id: string) => {
  const p = L.planBy[id]
  return !p ? '' : p.st.rate > 0 ? rateText(p.doc, p.st, L.todayIso) : '0% · interest-free'
}

export function PlanPanel({ L, id }: { L: Ledger; id: string }) {
  const ui = useUI()
  const { act } = useStore()
  const line = L.planBy[id]
  const [mode, setMode] = useState<'' | 'close' | 'delete'>('')
  const [err, setErr] = useState('')
  // Deleted elsewhere (or not synced yet): give it a moment, then close.
  useEffect(() => { if (!line) { const t = setTimeout(ui.closeAll, 1500); return () => clearTimeout(t) } }, [!line])
  if (!line) return null

  const { doc: p, st, ps, payments } = line
  const { f } = L
  const self: Panel = { kind: 'loan', id }
  const card = L.aName(p.acct)
  const catName = L.catOf(L.catOr(p.cat || 'shopping')).name
  const startYm = st.schedule[0]?.date.slice(0, 7)
  const fee = p.fee ?? 0
  const postedHere = payments.filter((t) => (t.debtPart ?? 'installment') === 'installment').length

  const close = () => {
    if (mode !== 'close') { setErr(''); return setMode('close') }
    const t = act.closePlan(p)
    if (t) ui.toast('Closed ' + p.name + ': ' + f(t.amt) + ' on ' + card, () => act.deleteTx(t))
    setMode('')
  }
  const del = () => {
    if (mode !== 'delete') { setMode('delete'); return setErr('Delete the ' + p.name + ' plan? Its ' + payments.length + ' entries stay on ' + card + ' as ordinary expenses, and nothing more is billed.') }
    act.deleteLoan(p)
    ui.toast('Deleted ' + p.name)
    ui.closeAll()
  }

  const head = (
    <div style={css('padding:14px 0 6px;display:flex;flex-direction:column;gap:10px')}>
      <div style={css('font-size:13.5px;color:#3a3566')}>{'Installment plan on ' + card + ' · ' + termText(ps.term)}</div>
      <div style={css('display:flex;flex-wrap:wrap;align-items:flex-end;justify-content:space-between;gap:10px 28px')}>
        <div>
          <div style={css('font-size:13px;color:#3a3566')}>{ps.closed ? 'Closed early' : ps.done ? 'All billed' : 'Still to be billed'}</div>
          <div style={css("font:500 60px/1 'Geist',sans-serif;letter-spacing:-.045em;margin-top:4px")}>{f(Math.round(ps.remaining))}</div>
        </div>
        <div style={css('flex:1;min-width:240px;max-width:460px;padding-bottom:6px')}>
          <div style={css('display:flex;justify-content:space-between;font-size:13px;font-weight:500')}>
            <span>{ps.billed + ' of ' + ps.term + ' billed'}</span>
            <span style={css('color:#3a3566')}>{f(st.principal) + ' in all'}</span>
          </div>
          <div style={css('height:8px;border-radius:4px;background:rgba(11,11,12,.16);margin-top:8px')}>
            <div style={sx('height:100%;border-radius:4px;background:#0b0b0c', { width: pc(ps.closed ? 1 : ps.billed / (ps.term || 1)) })} />
          </div>
        </div>
      </div>
    </div>
  )

  return (
    <PanelFrame wide title={p.name} head={head} err={err}
      onDelete={del} deleteLabel={mode === 'delete' ? 'Confirm delete' : 'Delete'}
      actions={<button type="button" onClick={() => ui.open({ kind: 'planForm', id, back: self })} style={sx('', { ...BTN_LINE, flex: 1 })}>Edit</button>}>
      <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,360px),1fr));gap:26px 34px;align-items:start;padding-bottom:10px')}>
        <div style={css('display:flex;flex-direction:column;gap:22px;min-width:0')}>
          {ps.next && (
            <div style={CARD}>
              <div style={css('display:flex;justify-content:space-between;align-items:baseline;gap:10px')}>
                <span style={css('font-size:13px;color:var(--mute)')}>{'Next: installment ' + ps.next.n + ' of ' + ps.term}</span>
                <span style={css('font-size:13.5px;font-weight:500')}>{dLab(isoD(ps.next.date)) + ' ' + ps.next.date.slice(0, 4)}</span>
              </div>
              <div style={css("font:500 30px 'Geist',sans-serif;letter-spacing:-.02em")}>{f(ps.next.amt)}</div>
              <div style={css('font-size:13px;color:var(--mute);text-wrap:pretty')}>
                {'Twofold posts it on ' + card + ' on the ' + ordinal(Number(ps.next.date.slice(8, 10))) + ', under ' + catName + ', so each month’s budget counts one installment.'}
              </div>
            </div>
          )}

          <section>
            <span style={H22}>Summary</span>
            <div style={css('margin-top:4px')}>
              <Line k="Bought for" v={f(st.principal)} sub={startYm ? 'first installment ' + mLabel(startYm, true) : undefined} />
              <Line k="Still to be billed" v={f(r2(ps.remaining))} sub={ps.done ? undefined : 'held against the card’s limit'} />
              <Line k="Installment" v={f(r2(st.installment)) + ' a month'} sub={catName} />
              <Line k="Rate" v={planRate(L, id)} />
              <Line k="Term" v={termText(ps.term)} sub={startYm && ps.endsYm ? mLabel(startYm, true) + ' → ' + mLabel(ps.endsYm, true) : undefined} />
              {st.totalInterest > 0.005 && <Line k="Interest" v={f(Math.round(st.totalInterest))} sub="over the whole plan" />}
              {(p.procFee ?? 0) > 0 && <Line k="Processing fee" v={f(p.procFee!)} sub="posted once, when the plan was added" />}
              {!ps.done && <Line k="Close today" v={f(r2(ps.settlement))} sub={fee ? 'includes a ' + pct(fee) + ' early-closure fee' : 'no early-closure fee'} />}
            </div>
          </section>

          {!ps.done && (
            <section style={sx('', { ...CARD, flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 10 })}>
              <span style={css('flex:1;min-width:200px;font-size:13.5px;text-wrap:pretty')}>
                {mode === 'close'
                  ? 'Post ' + f(r2(ps.settlement)) + ' on ' + card + ' now and stop the installments?'
                  : 'Close early: everything left goes on the card at once, ' + f(r2(ps.settlement)) + (fee ? ', fee included.' : '.')}
              </span>
              {mode === 'close' && <button type="button" onClick={() => setMode('')} style={sx(PILL, { border: '1px solid var(--chip)', background: 'transparent', color: 'var(--ink)' })}>Cancel</button>}
              <button type="button" onClick={close} style={sx(PILL, { border: '1.5px solid var(--ink)', background: mode === 'close' ? 'var(--ink)' : 'transparent', color: mode === 'close' ? 'var(--bg)' : 'var(--ink)' })}>{mode === 'close' ? 'Confirm close' : 'Close early'}</button>
            </section>
          )}

          <section>
            <div style={css('display:flex;justify-content:space-between;align-items:baseline;gap:10px')}>
              <span style={H22}>{'Posted on ' + card}</span>
              <span style={css('font-size:13px;color:var(--mute)')}>{payments.length ? f(r2(payments.reduce((a, t) => a + t.amt, 0))) : ''}</span>
            </div>
            {payments.map((t) => <TxButton key={t.id} L={L} t={t} badge={false} back={self} />)}
            {!payments.length && <div style={css('padding:8px 0;font-size:14px;color:var(--mute);text-wrap:pretty')}>Nothing posted yet. Each installment is posted on the card on its date.</div>}
            <div style={css('font-size:12.5px;color:var(--mute);padding-top:10px;text-wrap:pretty')}>
              {((p.paidBefore ?? 0) > 0 ? 'Plus ' + p.paidBefore + ' billed before the plan was added. ' : '')
                + (ps.billed - (p.paidBefore ?? 0) > postedHere ? 'A deleted installment isn’t posted again.' : '')}
            </div>
          </section>
        </div>

        <Schedule L={L} st={st} billed={ps.billed} title="Installments"
          foot={'In ' + L.cur + '. Ticked rows are billed on the card' + (ps.closed ? '; the plan was closed early.' : '.')} />
      </div>
    </PanelFrame>
  )
}
