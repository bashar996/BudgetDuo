// Today: safe-to-spend, quick actions, first-run checklist, coach tips and a summary of every area.
import type { ReactNode } from 'react'
import { css, sx } from '../lib/css'
import { addM, dLab, dim, mLabel, pad } from '../lib/dates'
import { pc, sum } from '../lib/money'
import { ACCOUNT_TYPES } from '../data/catalog'
import type { Ledger } from '../data/ledger'
import { useUI, type TabDef, type TabId } from '../shell/ui'
import { TxButton } from './activity'
import { rowDetail, settleUp } from './us'

const H2 = "font:500 22px 'Geist',sans-serif;letter-spacing:-.01em"
const EMPTY = 'padding:8px 0;font-size:14px;color:var(--mute)'
const TILE = 'width:76px;height:76px;flex:none;border-radius:20px;border:none;background:#ffffff;color:#0b0b0c;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;cursor:pointer;font-family:inherit'

function Section({ title, link, to, children }: { title: string; link: string; to: TabId; children: ReactNode }) {
  const { go } = useUI()
  return (
    <section>
      <div style={css('display:flex;justify-content:space-between;align-items:baseline')}>
        <span style={css(H2)}>{title}</span>
        <button onClick={() => go(to)} style={css("height:44px;border:none;background:none;color:var(--ink);font:500 14px 'Geist',sans-serif;cursor:pointer;padding:0")}>{link}</button>
      </div>
      {children}
    </section>
  )
}

function tips(L: Ledger) {
  const { f, rows, isCur, daysLeft, day } = L
  const out: string[] = []
  const watch = rows.filter((r) => r.variable && r.avail > 0).sort((a, b) => b.ratio - a.ratio).slice(0, 4)
  const over = rows.filter((r) => r.left < 0).sort((a, b) => a.left - b.left)[0]
  if (over) out.push(over.name + ' went ' + f(-over.left) + ' past its limit. No stress — move a little from a category with room and you’re square.')
  const tight = watch.find((r) => r.left >= 0 && r.ratio > 0.75)
  if (tight && isCur) out.push(tight.name + ' has ' + f(tight.left) + ' left for the next ' + daysLeft + ' days — about ' + f(Math.round(tight.left / daysLeft)) + ' a day keeps it on track.')
  const diff = sum(L.pExp.filter((t) => +t.date.slice(8) <= day), (t) => t.amt) - L.tSpent
  if (isCur && L.pExp.length) out.push(diff >= 0 ? 'You’ve spent ' + f(diff) + ' less than at this point last month. Nicely done, you two.' : 'Spending is ' + f(-diff) + ' ahead of this point last month — worth a quick look together.')
  if (L.leftAssign > 0) out.push(f(L.leftAssign) + ' of income isn’t assigned yet. Sending it to a goal now means it won’t quietly disappear.')
  return { watch, tips: out.slice(0, 3) }
}

function Body({ L }: { L: Ledger }) {
  const ui = useUI()
  const { f, H, data, safe, tSpent, tAvail, unpaid, isCur, daysLeft, ym, curYm } = L
  const { watch, tips: coach } = tips(L)
  const fresh = !data.tx.length && !data.accounts.length
  const perDay = fresh ? 'A clean slate. Add your accounts and pay, and this becomes your safe-to-spend number.'
    : isCur ? (safe > 0 ? 'About ' + f(Math.round(safe / daysLeft)) + ' a day for the next ' + daysLeft + ' days, after every bill is covered.' : 'Budgets are used up for now. Bills are still covered — a small top-up from a quiet category will do it.')
    : ym < curYm ? 'This month is closed — here’s how it ended.' : 'This month hasn’t started yet.'
  const spentW = pc(tSpent / tAvail), billsW = pc(Math.max(0, Math.min(unpaid, tAvail - tSpent)) / tAvail)

  const steps: [string, string, boolean, () => void][] = [
    ['Add your accounts', 'Current, cash, card, savings', data.accounts.length > 0, () => { ui.go('accounts'); ui.open({ kind: 'acct' }) }],
    ['Set your pay', 'So the budget has something to divide', L.income > 0, () => ui.go('us')],
    ['Give categories a limit', 'Tap any category in Budget', L.tLimit > 0, () => ui.go('budget')],
    ['Log your first entry', 'Or add your regular bills', data.tx.length > 0, () => ui.open({ kind: 'tx' })],
  ]
  const showStart = steps.some((s) => !s[2])

  const ev = L.events(30).slice(0, 5)
  const recent = [...L.mtx].sort(L.desc).slice(0, 6)
  const goals = L.goals.slice(0, 3)
  const accts = L.accounts.filter((a) => a.type !== 'invest').slice(0, 5)
  const us = settleUp(L)

  return (
    <div style={css('display:flex;flex-direction:column;gap:34px')}>
      <section style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:28px 40px;align-items:end')}>
        <div style={css('min-width:0')}>
          <div style={css('font-size:14px;color:var(--mute)')}>Safe to spend this month</div>
          <div style={css('display:flex;align-items:baseline;gap:10px;margin-top:4px')}>
            <span style={css("font:500 24px 'Geist',sans-serif;color:var(--mute)")}>{L.cur}</span>
            <span style={css("font:500 clamp(64px,10vw,124px)/.92 'Geist',sans-serif;letter-spacing:-.05em")}>{L.num(Math.round(safe))}</span>
          </div>
          <div style={css('font-size:15px;margin-top:14px;max-width:460px;text-wrap:pretty')}>{perDay}</div>
        </div>
        <div style={css('min-width:0')}>
          <div style={css('display:flex;justify-content:space-between;gap:12px;font-size:13.5px;font-weight:500')}><span>Spent {f(tSpent)}</span><span style={css('color:var(--mute)')}>of {f(tAvail)}</span></div>
          <div style={css('position:relative;height:8px;border-radius:4px;background:rgba(11,11,12,.16);margin:12px 0 10px')}>
            <div style={sx('position:absolute;left:0;top:0;bottom:0;background:#0b0b0c;border-radius:4px;transition:width .5s', { width: spentW })} />
            <div style={sx('position:absolute;top:0;bottom:0;background:repeating-linear-gradient(135deg,#0b0b0c 0 2px,transparent 2px 6px)', { left: spentW, width: billsW })} />
            <div style={sx('position:absolute;top:-5px;bottom:-5px;width:2px;border-radius:1px;background:#ffffff', { left: pc(L.pace) })} />
          </div>
          <div style={css('display:flex;flex-wrap:wrap;gap:6px 16px;font-size:12.5px;color:var(--mute)')}>
            <span style={css('display:flex;align-items:center;gap:6px')}><span style={css('width:10px;height:10px;border-radius:3px;background:#0b0b0c')} />spent</span>
            <span style={css('display:flex;align-items:center;gap:6px')}><span style={css('width:10px;height:10px;border-radius:3px;background:repeating-linear-gradient(135deg,#0b0b0c 0 2px,transparent 2px 5px)')} />bills still due {f(unpaid)}</span>
            <span style={css('display:flex;align-items:center;gap:6px')}><span style={css('width:2px;height:12px;background:#ffffff')} />today</span>
          </div>
          <div style={css('display:flex;flex-wrap:wrap;gap:10px;margin-top:20px')}>
            <button onClick={() => ui.open({ kind: 'tx', pre: { type: 'inc' } })} style={css(TILE)}><span style={css('font-size:24px;line-height:1')}>↓</span><span style={css('font-size:11.5px;font-weight:500')}>Income</span></button>
            <button onClick={() => ui.open({ kind: 'tx', pre: { type: 'xfer' } })} style={css(TILE)}><span style={css('font-size:24px;line-height:1')}>↗</span><span style={css('font-size:11.5px;font-weight:500')}>Move</span></button>
            <button onClick={() => ui.open({ kind: 'tx' })} style={css(TILE)}><span style={css('font-size:24px;line-height:1')}>+</span><span style={css('font-size:11.5px;font-weight:500')}>Spend</span></button>
            <button onClick={() => ui.go('reports')} style={css("flex:1 1 120px;height:76px;border-radius:20px;border:none;background:#0b0b0c;color:#ffffff;font:500 16px 'Geist',sans-serif;cursor:pointer")}>Reports</button>
          </div>
        </div>
      </section>

      {showStart && (
        <section style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,220px),1fr));gap:10px')}>
          {steps.map(([t, s, done, go], i) => (
            <button key={t} onClick={go} style={css('display:flex;gap:12px;align-items:flex-start;text-align:left;padding:18px;background:var(--card);border:none;border-radius:24px;font:inherit;color:inherit;cursor:pointer')}>
              <span style={sx("width:28px;height:28px;flex:none;border-radius:9px;border:1.5px solid var(--ink);display:grid;place-items:center;font:600 12.5px 'Geist',sans-serif;box-sizing:border-box", { background: done ? 'var(--ink)' : 'transparent', color: done ? 'var(--bg)' : 'var(--ink)' })}>{done ? '✓' : i + 1}</span>
              <span style={css('display:flex;flex-direction:column;gap:2px')}><span style={css('font-weight:600')}>{t}</span><span style={css('font-size:13px;color:var(--mute)')}>{s}</span></span>
            </button>
          ))}
        </section>
      )}

      {H.coachTips !== false && coach.length > 0 && (
        <section style={css('background:#0b0b0c;color:#ffffff;border-radius:28px;padding:6px 26px;display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,230px),1fr));gap:0 36px')}>
          {coach.map((t, i) => (
            <div key={i} style={css('padding:18px 0;display:flex;gap:12px;align-items:flex-start')}>
              <span style={css("font:500 12.5px 'Geist',sans-serif;color:var(--accBase);padding-top:2px")}>{pad(i + 1)}</span>
              <span style={css('font-size:14.5px;text-wrap:pretty')}>{t}</span>
            </div>
          ))}
        </section>
      )}

      <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),1fr));gap:30px 40px;align-items:start')}>
        <Section title="Coming up" link="Forecast →" to="plan">
          {ev.map((e, i) => (
            <div key={i} style={css('display:flex;align-items:center;gap:12px;padding:12px 0;border-bottom:1px solid var(--line)')}>
              <span style={sx('font-size:13px;width:86px;flex:none', { color: e.late ? 'var(--bad)' : 'var(--mute)' })}>{e.late ? 'Overdue' : e.i === 0 ? 'Today' : dLab(e.d)}</span>
              <span style={css('flex:1;min-width:0;font-weight:500')}>{e.name}</span>
              <span style={sx('font-size:15px;font-weight:500;white-space:nowrap', { color: e.inc ? 'var(--good)' : 'var(--ink)' })}>{(e.inc ? '+' : '') + f(e.amt)}</span>
            </div>
          ))}
          {!ev.length && <div style={css(EMPTY)}>No bills or paydays in the next 30 days.</div>}
        </Section>

        <Section title="Transactions" link="See all →" to="activity">
          {recent.map((t) => <TxButton key={t.id} L={L} t={t} badge={false} />)}
          {!recent.length && <div style={css(EMPTY)}>No entries yet this month.</div>}
        </Section>

        <Section title="Categories to watch" link="Budget →" to="budget">
          {watch.map((r) => (
            <button key={r.id} className="h-row" onClick={() => ui.open({ kind: 'budget', cat: r.id })} style={css('display:block;width:100%;padding:12px 0 4px;background:none;border:none;font:inherit;color:inherit;cursor:pointer;text-align:left')}>
              <span style={css('display:flex;justify-content:space-between;align-items:flex-end;gap:10px')}>
                <span style={css('font-size:16px')}>{r.name}</span>
                <span style={sx('font-size:27px;letter-spacing:-.02em;line-height:1', { color: r.left < 0 ? 'var(--bad)' : 'var(--ink)' })}>{Math.round(r.ratio * 100)}%</span>
              </span>
              <span style={css('display:block;position:relative;height:5px;border-radius:3px;background:var(--track);margin-top:8px')}>
                <span style={sx('position:absolute;left:0;top:0;bottom:0;border-radius:3px;transition:width .4s', { width: pc(r.ratio), background: r.left < 0 ? 'var(--bad)' : 'var(--acc)' })} />
              </span>
              <span style={css('display:block;font-size:12.5px;color:var(--mute);margin-top:6px')}>{rowDetail(L, r)}</span>
            </button>
          ))}
          {!watch.length && <div style={css(EMPTY + ';text-wrap:pretty')}>Set category limits in Budget and the busiest ones show here.</div>}
        </Section>

        <Section title="Savings goals" link="Savings →" to="savings">
          {goals.map((g) => {
            const rem = Math.max(0, g.target - g.saved), n = g.monthly > 0 ? Math.ceil(rem / g.monthly) : 0, r = g.target ? g.saved / g.target : 0
            const eta = rem <= 0 ? 'reached' : n ? 'there by ' + mLabel(addM(curYm, n), true) : 'no monthly amount yet'
            return (
              <div key={g.id} style={css('padding:12px 0 4px')}>
                <div style={css('display:flex;justify-content:space-between;align-items:flex-end;gap:10px')}><span style={css('font-size:16px')}>{g.name}</span><span style={css('font-size:27px;letter-spacing:-.02em;line-height:1')}>{Math.round(r * 100)}%</span></div>
                <div style={css('height:5px;border-radius:3px;background:var(--track);margin-top:8px')}><div style={sx('height:100%;background:var(--acc);border-radius:3px', { width: pc(r) })} /></div>
                <div style={css('font-size:12.5px;color:var(--mute);margin-top:6px')}>{f(g.saved)} of {f(g.target)} · {eta}</div>
              </div>
            )
          })}
          {!goals.length && <div style={css(EMPTY)}>No savings pots yet.</div>}
        </Section>

        <Section title="Accounts" link="All accounts →" to="accounts">
          {accts.map((a) => (
            <div key={a.id} style={css('display:flex;align-items:center;gap:12px;padding:11px 0;border-bottom:1px solid var(--line)')}>
              <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
                <span style={css('font-size:16px;font-weight:500')}>{a.name}</span>
                <span style={css('font-size:13px;color:var(--mute)')}>{(ACCOUNT_TYPES[a.type] ?? ACCOUNT_TYPES.current)[0]}</span>
              </span>
              <span style={sx('font-size:15px;font-weight:500;white-space:nowrap', { color: a.balance < 0 ? 'var(--bad)' : 'var(--ink)' })}>{f(a.balance)}</span>
            </div>
          ))}
          {!accts.length && <div style={css(EMPTY)}>No accounts yet.</div>}
        </Section>

        {us.split && (
          <section style={css('background:#0b0b0c;color:#ffffff;border-radius:28px;padding:24px;display:flex;flex-direction:column;gap:10px')}>
            <span style={css('font-size:13.5px;color:#a9a7b8')}>Between you two</span>
            <div style={css("font:500 28px/1.1 'Geist',sans-serif;letter-spacing:-.02em")}>{us.line}</div>
            <div style={css('font-size:13.5px;color:#d9d7e4')}>{us.sub}</div>
            <button onClick={() => ui.go('us')} style={css("align-self:flex-start;margin-top:6px;font:500 14.5px 'Geist',sans-serif;padding:0 18px;height:46px;border-radius:16px;border:none;background:var(--accBase);color:#0b0b0c;cursor:pointer")}>Open settle-up</button>
          </section>
        )}
      </div>
    </div>
  )
}

export const homeTab: TabDef = {
  id: 'home',
  stage: 'lav',
  kicker: (L) => dLab(L.today) + ' · day ' + L.tDay + ' of ' + dim(L.curYm),
  Body,
}
