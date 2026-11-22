// Budget (cream): left to assign, the three category groups, optional 50/30/20 check.
// Design: Tandem Budget.dc.html, template `is.budget` and `bud` in renderVals().
import type { TabDef } from '../shell/ui'
import { useUI } from '../shell/ui'
import type { Ledger } from '../data/ledger'
import { GROUPS } from '../data/catalog'
import { css, sx } from '../lib/css'
import { mLabel } from '../lib/dates'
import { pc, sum } from '../lib/money'

const LAV = 'var(--accBase)', RED = '#ff8f85'
const style = (L: Ledger) => L.H.budgetStyle ?? 'Zero-based'

function note(L: Ledger) {
  const { f, income, leftAssign } = L
  const zero = style(L) === 'Zero-based'
  if (!income) return 'Set your monthly pay under Us two, then give every bit of it a job here.'
  if (leftAssign < 0) return 'You’ve planned ' + f(-leftAssign) + ' more than comes in. Trimming one or two categories will bring it back.'
  if (zero) return leftAssign === 0 ? 'Every bit of income has a job. That’s the whole method.' : 'Give the remaining ' + f(leftAssign) + ' a job — a category or a goal — so nothing drifts.'
  return ''
}

function Body({ L }: { L: Ledger }) {
  const ui = useUI()
  const { f, rows, income } = L
  const gSum = (gs: string[]) => sum(rows.filter((r) => gs.includes(r.g)), (r) => r.limit)
  const bands: [string, number, number, string][] = [
    ['Needs', gSum(['needs']), 0.5, 'var(--ink)'],
    ['Wants', gSum(['wants', 'personal']), 0.3, 'var(--a)'],
    ['Savings', L.goalsMo, 0.2, 'var(--acc)'],
  ]
  const paceL = pc(L.pace), paceO = L.isCur ? 0.6 : 0

  return (
    <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),1fr));gap:30px 40px;align-items:start')}>
      <div style={css('grid-column:1/-1;display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:10px 20px')}>
        <span style={css('flex:1;min-width:220px;font-size:13px;color:var(--mute);text-wrap:pretty')}>Pick a category to rename it, change its limit, move money in or delete it. The tick on each bar marks today.</span>
        <button onClick={() => ui.open({ kind: 'cat' })} style={css("flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 16px;height:44px;border-radius:22px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);cursor:pointer")}>+ New category</button>
      </div>

      {style(L) === '50/30/20' && (
        <section style={css('grid-column:1/-1;background:var(--card);border-radius:28px;padding:24px;display:flex;flex-direction:column;gap:16px')}>
          <span style={css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")}>50 / 30 / 20 check</span>
          {bands.map(([name, amt, guide, color]) => (
            <div key={name} style={css('display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px 12px')}>
              <span style={css('font-weight:500')}>{name} <span style={css('color:var(--mute)')}>· {Math.round((amt / (income || 1)) * 100)}% of income, guide is {guide * 100}%</span></span>
              <span style={css('font-weight:500')}>{f(amt)}</span>
              <span style={css('grid-column:1/-1;position:relative;height:10px;border-radius:5px;background:var(--soft)')}>
                <span style={sx('position:absolute;left:0;top:0;bottom:0;border-radius:5px', { width: pc(income ? amt / income : 0), background: color })} />
                <span style={sx('position:absolute;top:-4px;bottom:-4px;width:2px;background:var(--ink)', { left: pc(guide) })} />
              </span>
            </div>
          ))}
        </section>
      )}

      {GROUPS.map(([g, name]) => {
        const rs = rows.filter((r) => r.g === g)
        return (
          <section key={g}>
            <div style={css('display:flex;justify-content:space-between;align-items:baseline;gap:10px')}>
              <span style={css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")}>{name}</span>
              <span style={css('font-size:13px;color:var(--mute)')}>{f(sum(rs, (r) => r.sp)) + ' of ' + f(sum(rs, (r) => r.avail))}</span>
            </div>
            {rs.map((r) => {
              const over = r.left < 0
              const leftTxt = over ? f(-r.left) + ' over' : f(r.left) + ' left'
              const carry = Math.abs(r.carry) >= 1 ? 'rolled ' + (r.carry > 0 ? '+' : '') + f(r.carry) : ''
              return (
                <button key={r.id} onClick={() => ui.open({ kind: 'budget', cat: r.id })} style={css('display:block;width:100%;padding:14px 0 4px;background:none;border:none;font:inherit;color:inherit;cursor:pointer;text-align:left')}>
                  <span style={css('display:flex;justify-content:space-between;align-items:flex-end;gap:10px')}>
                    <span style={css('font-size:16px')}>{r.name} <span style={css('font-size:12px;color:var(--mute)')}>{carry}</span></span>
                    <span style={sx('font-size:27px;letter-spacing:-.02em;line-height:1', { color: over ? 'var(--bad)' : 'var(--ink)' })}>{Math.round(r.ratio * 100) + '%'}</span>
                  </span>
                  <span style={css('display:block;position:relative;height:5px;border-radius:3px;background:var(--track);margin-top:8px')}>
                    <span style={sx('position:absolute;left:0;top:0;bottom:0;border-radius:3px;transition:width .4s', { width: pc(r.ratio), background: over ? 'var(--bad)' : 'var(--acc)' })} />
                    <span style={sx('position:absolute;top:-4px;bottom:-4px;width:2px;border-radius:1px;background:var(--ink)', { left: paceL, opacity: paceO })} />
                  </span>
                  <span style={css('display:block;font-size:12.5px;color:var(--mute);margin-top:6px')}>{f(r.sp) + ' of ' + f(r.avail) + ' · ' + leftTxt}</span>
                </button>
              )
            })}
          </section>
        )
      })}
    </div>
  )
}

export const budgetTab: TabDef = {
  id: 'budget',
  stage: 'cream',
  kicker: (L) => style(L) + ' budget',
  hero: (L) => {
    const zero = style(L) === 'Zero-based'
    return {
      label: (zero ? 'Left to assign' : 'Unbudgeted') + ' · ' + mLabel(L.ym),
      cur: true,
      num: L.num(L.leftAssign),
      fg: L.leftAssign < 0 ? RED : LAV,
      sub: note(L),
      stats: [['Monthly income', L.f(L.income)], ['In categories', L.f(L.tLimit)], ['To goals', L.f(L.goalsMo)]],
    }
  },
  Body,
}
