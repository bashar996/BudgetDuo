// Debt (cream): debt-free date and timeline, strategy, extra payment, payoff order,
// then every loan (schedule-based, see data/loans.ts) and every credit card.
// Design: Tandem Budget.dc.html, template `is.goals` and `debt` in renderVals(); loans and
// cards follow round 6 (no design file, same visual language).
import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from 'react'
import type { HeroBar, TabDef } from '../shell/ui'
import { useUI } from '../shell/ui'
import { useStore } from '../data/store'
import { simDebt, type CardLine, type Ledger, type LoanLine } from '../data/ledger'
import { css, sx } from '../lib/css'
import { addM, dLab, isoD, mLabel } from '../lib/dates'
import { pc, sum } from '../lib/money'
import { dueText, loanMeta, pct, r2, rateText } from '../panels/loanBits'

const LAV = 'var(--accBase)', CRM = '#fbf9ef'
const NEVER = 720
const H22 = css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")
const HEAD = css('display:flex;justify-content:space-between;align-items:center;gap:10px;padding-bottom:10px')
const PILL = css("flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 16px;height:44px;border-radius:22px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);cursor:pointer")
const SOLID = "flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 18px;height:44px;border-radius:16px;border:none;background:var(--btn);color:var(--btnInk);cursor:pointer"
const LINE_BTN = "flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 16px;height:44px;border-radius:16px;border:1px solid var(--chip);background:transparent;color:var(--ink);cursor:pointer"
const GRID = css('display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,330px),1fr));gap:14px')
const TILE = 'background:var(--card);border-radius:28px;padding:22px;display:flex;flex-direction:column;gap:14px;cursor:pointer;text-align:left;min-width:0'
const EMPTY = css('padding:8px 0;font-size:14px;color:var(--mute);text-wrap:pretty')

/** A white tile that opens something; buttons inside stop the click. */
function Tile({ onOpen, label, children }: { onOpen(): void; label: string; children: ReactNode }) {
  const key = (e: KeyboardEvent) => { if (e.target === e.currentTarget && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); onOpen() } }
  return <div role="button" tabIndex={0} aria-label={label} onClick={onOpen} onKeyDown={key} style={css(TILE)}>{children}</div>
}
const stop = (fn: () => void) => (e: { stopPropagation(): void }) => { e.stopPropagation(); fn() }

/** Thin bar: lavender fill on the ink track. */
function Bar({ v, color = 'var(--acc)' }: { v: number; color?: string }) {
  return (
    <div style={css('height:6px;border-radius:3px;background:var(--track)')}>
      <div style={sx('height:100%;border-radius:3px;transition:width .4s', { width: pc(v), background: color })} />
    </div>
  )
}

function LoanTile({ L, x }: { L: Ledger; x: LoanLine }) {
  const ui = useUI()
  const { act } = useStore()
  const { f, todayIso } = L
  const { doc: l, st, bill } = x
  const done = st.balance <= 0.005
  const due = dueText(st.nextDue, todayIso)
  const viaBill = bill && st.nextDue && !bill.paid?.[st.nextDue.slice(0, 7)]
  const amt = r2(viaBill ? bill!.amt : st.installment)
  const pay = () => {
    const t = act.payLoan(l, 'installment', st.installment)
    if (t) ui.toast('Paid ' + f(amt) + ' on ' + l.name, () => act.deleteTx(t))
  }
  return (
    <Tile label={l.name} onOpen={() => ui.open({ kind: 'loan', id: l.id })}>
      <div style={css('display:flex;justify-content:space-between;align-items:flex-start;gap:10px')}>
        <span style={css('min-width:0;display:flex;flex-direction:column')}>
          <span style={css('font-size:17px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap')}>{l.name}</span>
          <span style={css('font-size:13px;color:var(--mute)')}>{loanMeta(l)}</span>
        </span>
        <span style={css('font-size:13px;color:var(--mute);text-align:right;white-space:nowrap')}>{rateText(l, st, todayIso)}</span>
      </div>
      <span>
        <span style={css('display:block;font-size:12.5px;color:var(--mute)')}>{done ? 'Paid off' : 'Outstanding'}</span>
        <span style={css("display:block;font:500 34px/1.05 'Geist',sans-serif;letter-spacing:-.03em;white-space:nowrap")}>{f(Math.round(st.balance))}</span>
        {!done && <span style={css('display:block;font-size:14px;font-weight:500;margin-top:4px')}>{f(r2(st.installment))}<span style={css('font-weight:400;color:var(--mute)')}> a month</span></span>}
      </span>
      {st.simple ? (
        <button onClick={stop(() => ui.open({ kind: 'loanForm', id: l.id }))} style={css("align-self:flex-start;border:none;background:none;padding:0;font:500 13.5px 'Geist',sans-serif;color:var(--ink);text-decoration:underline;text-underline-offset:3px;cursor:pointer;text-align:left")}>Add the loan details for a full schedule</button>
      ) : (
        <div style={css('display:flex;flex-direction:column;gap:8px')}>
          <Bar v={st.progress} />
          <span style={css('font-size:12.5px;color:var(--mute)')}>
            {st.installmentsPaid + ' of ' + st.termMonths + ' paid' + (done ? '' : ' · ends ' + (st.endsYm ? mLabel(st.endsYm, true) : 'not at this pace'))}
          </span>
        </div>
      )}
      <div style={css('display:flex;align-items:center;gap:10px;border-top:1px solid var(--line);padding-top:12px;min-height:44px')}>
        <span style={sx('flex:1;min-width:0;font-size:13.5px;font-weight:500', { color: due.bad ? 'var(--bad)' : 'var(--ink)' })}>{done ? 'All paid. Well done, you two.' : due.text}</span>
        {!done && <button onClick={stop(pay)} aria-label={'Pay ' + l.name + ' installment'} style={css(SOLID)}>Pay</button>}
      </div>
    </Tile>
  )
}

function CardTile({ L, x }: { L: Ledger; x: CardLine }) {
  const ui = useUI()
  const { f } = L
  const { acct: a, cs } = x
  const used = cs.utilisation ?? 0
  const card = L.data.accounts.find((z) => z.id === a.id)
  const pay = (amt: number) => ui.open({ kind: 'tx', pre: { type: 'xfer', acct: L.mainAcct, to: a.id, amt: r2(amt), name: a.name + ' payment' } })
  const minOnly = cs.minOnly.never ? 'Paying only the minimum, it’s never paid off.'
    : 'Paying only the minimum: ' + cs.minOnly.months + (cs.minOnly.months === 1 ? ' month, ' : ' months, ') + f(Math.round(cs.minOnly.interest)) + ' interest.'
  return (
    <Tile label={a.name} onOpen={() => ui.open({ kind: 'acct', acct: card })}>
      <div style={css('display:flex;justify-content:space-between;align-items:flex-start;gap:10px')}>
        <span style={css('min-width:0;display:flex;flex-direction:column')}>
          <span style={css('font-size:17px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap')}>{a.name}</span>
          <span style={css('font-size:13px;color:var(--mute)')}>{[a.bank, a.last4 ? '•• ' + a.last4 : '', pct(cs.apr) + ' a year'].filter(Boolean).join(' · ')}</span>
        </span>
      </div>
      <span>
        <span style={css('display:block;font-size:12.5px;color:var(--mute)')}>Owed</span>
        <span style={css("display:block;font:500 34px/1.05 'Geist',sans-serif;letter-spacing:-.03em;white-space:nowrap")}>{f(r2(cs.owed))}</span>
      </span>
      {cs.limit ? (
        <div style={css('display:flex;flex-direction:column;gap:8px')}>
          <Bar v={used} color={used > 0.3 ? 'var(--warn)' : 'var(--acc)'} />
          <span style={sx('font-size:12.5px', { color: used > 0.3 ? 'var(--warn)' : 'var(--mute)' })}>{Math.round(used * 100) + '% of ' + f(cs.limit) + ' used' + (used > 0.3 ? ', above the 30% lenders like' : '')}</span>
        </div>
      ) : <span style={css('font-size:12.5px;color:var(--mute)')}>No limit set</span>}
      {cs.owed > 0 ? (
        <div style={css('display:flex;flex-direction:column;gap:4px;font-size:13.5px')}>
          {cs.nextDue
            ? <span style={css('font-weight:500')}>{'Minimum ' + f(r2(cs.minDue)) + ' due ' + dLab(isoD(cs.nextDue))}</span>
            : <span><span style={css('font-weight:500')}>{'Minimum ' + f(r2(cs.minDue))}</span>{' · '}<button onClick={stop(() => ui.open({ kind: 'acct', acct: card }))} style={css("border:none;background:none;padding:0;font:500 13.5px 'Geist',sans-serif;color:var(--ink);text-decoration:underline;text-underline-offset:3px;cursor:pointer")}>Set the due day</button></span>}
          <span style={css('color:var(--mute);text-wrap:pretty')}>{minOnly}</span>
          <span style={css('color:var(--mute)')}>{'Interest next month if you pay only the minimum: ' + f(r2(cs.interestIfMin))}</span>
        </div>
      ) : <span style={css('font-size:13.5px;color:var(--mute)')}>Nothing owed on this card.</span>}
      {cs.owed > 0 && (
        <div style={css('display:flex;gap:8px;border-top:1px solid var(--line);padding-top:12px')}>
          <button onClick={stop(() => pay(cs.owed))} style={sx(SOLID, { flex: 1 })}>Pay in full</button>
          <button onClick={stop(() => pay(cs.minDue))} style={sx(LINE_BTN, { flex: 1 })}>Pay minimum</button>
        </div>
      )}
    </Tile>
  )
}

function Body({ L }: { L: Ledger }) {
  const ui = useUI()
  const { act } = useStore()
  const { f, allDebts, calYm: curYm } = L

  // The slider moves locally and saves once it settles, so dragging doesn't write on every step.
  const [extra, setExtraLocal] = useState(L.extra)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => { if (!timer.current) setExtraLocal(L.extra) }, [L.extra])
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current) }, [])
  const onExtra = (v: number) => {
    setExtraLocal(v)
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => { timer.current = null; act.setExtra(v) }, 250)
  }

  const res = extra === L.extra ? L.debtPlan : simDebt(allDebts, extra, L.strat)
  const base = simDebt(allDebts, 0, L.strat)
  const saveNote = extra > 0 && base.months > res.months
    ? (base.months >= NEVER
      ? 'That extra ' + f(extra) + ' is what gets everything cleared at all — without it the balance never comes down.'
      : 'That extra ' + f(extra) + ' clears everything ' + (base.months - res.months) + ' months sooner and keeps ' + f(Math.round(base.interest - res.interest)) + ' of interest in your pocket.')
    : 'Slide to see how a little extra each month changes the finish line.'
  const strat: [string, 'avalanche' | 'snowball'][] = [['Highest interest first', 'avalanche'], ['Smallest balance first', 'snowball']]

  return (
    <div style={css('display:flex;flex-direction:column;gap:38px')}>
      <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:30px 40px;align-items:start')}>
        <section style={css('background:var(--card);border-radius:28px;padding:24px;display:flex;flex-direction:column;gap:18px')}>
          <span style={H22}>Payoff plan</span>
          <div style={css('display:flex;flex-wrap:wrap;gap:6px')}>
            {strat.map(([label, id]) => {
              const on = L.strat === id
              return (
                <button key={id} onClick={() => act.setStrategy(id)} aria-pressed={on}
                  style={sx("height:44px;padding:0 15px;border-radius:22px;font:500 13.5px 'Geist',sans-serif;cursor:pointer", { border: '1px solid ' + (on ? 'var(--ink)' : 'var(--chip)'), background: on ? 'var(--ink)' : 'transparent', color: on ? 'var(--bg)' : 'var(--ink)' })}>{label}</button>
              )
            })}
          </div>
          <div>
            <div style={css('display:flex;justify-content:space-between;align-items:flex-end;gap:10px')}>
              <span style={css('font-size:16px')}>Extra payment each month</span>
              <span style={css('font-size:27px;letter-spacing:-.02em;line-height:1')}>{f(extra)}</span>
            </div>
            <input type="range" min={0} max={5000} step={100} value={extra} onChange={(e) => onExtra(+e.target.value)} aria-label="Extra payment each month" style={css('width:100%;height:40px;accent-color:var(--ink)')} />
            <div style={css('font-size:14.5px;text-wrap:pretty')}>{saveNote}</div>
          </div>
        </section>
        <section>
          <div style={css('padding-bottom:6px;min-height:44px;display:flex;align-items:center')}><span style={H22}>Order of payoff</span></div>
          {res.order.map((id, i) => {
            const x = allDebts.find((z) => z.id === id)!
            const ln = L.loanBy[id]
            const m = res.done[id]
            return (
              <button key={id} className="h-row" onClick={() => (x.card ? ui.open({ kind: 'acct', acct: x.card }) : ui.open({ kind: 'loan', id: x.id }))}
                style={css('display:flex;align-items:center;gap:12px;width:100%;padding:10px 0;background:none;border:none;border-bottom:1px solid var(--line);font:inherit;color:inherit;cursor:pointer;text-align:left')}>
                <span style={css('width:44px;height:44px;flex:none;border-radius:13px;background:var(--ink);color:var(--bg);display:grid;place-items:center;font-size:17px;font-weight:600')}>{i + 1}</span>
                <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
                  <span style={css('font-size:16px;font-weight:500')}>{x.name}</span>
                  <span style={css('font-size:13px;color:var(--mute)')}>{(ln ? rateText(ln.doc, ln.st, L.todayIso) : pct(x.apr)) + ' · ' + f(r2(x.min)) + (x.card ? '/mo minimum' : '/mo')}</span>
                </span>
                <span style={css('display:flex;flex-direction:column;align-items:flex-end')}>
                  <span style={css('font-size:15px;font-weight:500;white-space:nowrap')}>{f(Math.round(x.balance))}</span>
                  <span style={css('font-size:12.5px;color:var(--mute)')}>{m ? 'clear ' + mLabel(addM(curYm, m), true) : 'not cleared at this pace'}</span>
                </span>
              </button>
            )
          })}
          {!allDebts.length && <div style={EMPTY}>Nothing owed. Add a loan below to plan its payoff.</div>}
          <div style={css('font-size:13px;color:var(--mute);padding-top:12px;text-wrap:pretty')}>Loans at their installment and real rate; credit cards at their minimum.</div>
        </section>
      </div>

      <section>
        <div style={HEAD}>
          <span style={H22}>Loans</span>
          <button onClick={() => ui.open({ kind: 'loanForm' })} style={PILL}>+ Loan</button>
        </div>
        <div style={GRID}>{L.loans.map((x) => <LoanTile key={x.doc.id} L={L} x={x} />)}</div>
        {!L.loans.length && <div style={EMPTY}>No loans yet. Add a car loan, mortgage or personal loan to see its schedule, interest and end date.</div>}
      </section>

      <section>
        <div style={HEAD}>
          <span style={H22}>Credit cards</span>
          <button onClick={() => ui.open({ kind: 'acct', preset: 'card' })} style={PILL}>+ Card</button>
        </div>
        <div style={GRID}>{L.cards.map((x) => <CardTile key={x.acct.id} L={L} x={x} />)}</div>
        {!L.cards.length && <div style={EMPTY}>No credit cards. Cards you add under Accounts show here with their minimum and due date.</div>}
      </section>
    </div>
  )
}

export const goalsTab: TabDef = {
  id: 'goals',
  stage: 'cream',
  kicker: () => 'Payoff plan, loans and cards',
  hero: (L) => {
    const { f, allDebts, debtPlan: res, calYm: curYm } = L
    const total = f(Math.round(sum(allDebts, (x) => x.balance)))
    const never = res.months >= NEVER
    const stp = Math.max(1, Math.ceil(res.series.length / 30)), dHi = res.series[0] || 1
    const bars: HeroBar[] = res.series.filter((_, i) => i % stp === 0).map((v, i) => ({
      h: pc(Math.max(0.02, v / dHi)),
      bg: i === 0 ? LAV : CRM,
      tag: i === 0 ? total : '',
      title: mLabel(addM(curYm, i * stp), true) + ' · ' + f(Math.round(v)),
    }))
    const payments = sum(allDebts, (x) => x.min)
    const monthly = f(Math.round(payments + L.extra)) + ' a month goes to debt in total. '
    return {
      label: 'Debt-free by',
      num: !allDebts.length ? 'Debt-free' : never ? 'Not at this pace' : mLabel(addM(curYm, res.months), true),
      fg: LAV,
      sub: never
        ? monthly + 'That isn’t enough to outrun the interest, so the balance never clears. Add a little extra below.'
        : monthly + 'As each one clears, its payment rolls onto the next.',
      stats: [['Owed today', total], ['Monthly payments', f(Math.round(payments))], ['Interest to go', never ? '—' : f(Math.round(res.interest))]],
      bars,
    }
  },
  Body,
}
