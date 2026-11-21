// Debt (cream): debt-free date and timeline, strategy, extra payment, payoff order.
// Design: Tandem Budget.dc.html, template `is.goals` and `debt` in renderVals().
import { useEffect, useRef, useState } from 'react'
import type { HeroBar, TabDef } from '../shell/ui'
import { useUI } from '../shell/ui'
import { useStore } from '../data/store'
import { simDebt, type Ledger } from '../data/ledger'
import { css, sx } from '../lib/css'
import { addM, mLabel } from '../lib/dates'
import { pc, sum } from '../lib/money'

const LAV = 'var(--accBase)', CRM = '#fbf9ef'
const NEVER = 720
const H22 = css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")

function Body({ L }: { L: Ledger }) {
  const ui = useUI()
  const { act } = useStore()
  const { f, allDebts, curYm } = L

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
        <div style={css('display:flex;justify-content:space-between;align-items:center;gap:10px;padding-bottom:6px')}>
          <span style={H22}>Order of payoff</span>
          <button onClick={() => ui.open({ kind: 'item', item: 'debt' })} style={css("flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 16px;height:44px;border-radius:22px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);cursor:pointer")}>+ Loan</button>
        </div>
        {res.order.map((id, i) => {
          const x = allDebts.find((z) => z.id === id)!
          const m = res.done[id]
          return (
            <button key={id} onClick={() => (x.card ? ui.open({ kind: 'acct', acct: x.card }) : ui.open({ kind: 'item', item: 'debt', id: x.id }))}
              style={css('display:flex;align-items:center;gap:12px;width:100%;padding:10px 0;background:none;border:none;border-bottom:1px solid var(--line);font:inherit;color:inherit;cursor:pointer;text-align:left')}>
              <span style={css('width:44px;height:44px;flex:none;border-radius:13px;background:var(--ink);color:var(--bg);display:grid;place-items:center;font-size:17px;font-weight:600')}>{i + 1}</span>
              <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
                <span style={css('font-size:16px;font-weight:500')}>{x.name}</span>
                <span style={css('font-size:13px;color:var(--mute)')}>{x.apr + '% · ' + f(x.min) + '/mo minimum'}</span>
              </span>
              <span style={css('display:flex;flex-direction:column;align-items:flex-end')}>
                <span style={css('font-size:15px;font-weight:500;white-space:nowrap')}>{f(x.balance)}</span>
                <span style={css('font-size:12.5px;color:var(--mute)')}>{m ? 'clear ' + mLabel(addM(curYm, m), true) : 'not cleared at this pace'}</span>
              </span>
            </button>
          )
        })}
        {!allDebts.length && <div style={css('padding:8px 0;font-size:14px;color:var(--mute)')}>No debts. Add a loan to plan its payoff.</div>}
        <div style={css('font-size:13px;color:var(--mute);padding-top:12px;text-wrap:pretty')}>Credit card balances from Accounts are included automatically.</div>
      </section>
    </div>
  )
}

export const goalsTab: TabDef = {
  id: 'goals',
  stage: 'cream',
  kicker: () => 'Payoff plan and timeline',
  hero: (L) => {
    const { f, allDebts, debtPlan: res, curYm } = L
    const total = f(sum(allDebts, (x) => x.balance))
    const never = res.months >= NEVER
    const stp = Math.max(1, Math.ceil(res.series.length / 30)), dHi = res.series[0] || 1
    const bars: HeroBar[] = res.series.filter((_, i) => i % stp === 0).map((v, i) => ({
      h: pc(Math.max(0.02, v / dHi)),
      bg: i === 0 ? LAV : CRM,
      tag: i === 0 ? total : '',
      title: mLabel(addM(curYm, i * stp), true) + ' · ' + f(Math.round(v)),
    }))
    const monthly = f(sum(allDebts, (x) => x.min) + L.extra) + ' a month goes to debt in total. '
    return {
      label: 'Debt-free by',
      num: !allDebts.length ? 'Debt-free' : never ? 'Not at this pace' : mLabel(addM(curYm, res.months), true),
      fg: LAV,
      sub: never
        ? monthly + 'That isn’t enough to outrun the interest, so the balance never clears. Add a little extra below.'
        : monthly + 'As each one clears, its payment rolls onto the next.',
      stats: [['Owed today', total], ['Interest to go', never ? '—' : f(Math.round(res.interest))]],
      bars,
    }
  },
  Body,
}
