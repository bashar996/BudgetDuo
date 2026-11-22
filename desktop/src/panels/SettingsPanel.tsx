// Settings: the web design's tweaks made real. Household and budgeting
// choices are shared by both of you; the look is per Mac.
import { useState, type ReactNode } from 'react'
import type { Ledger } from '../data/ledger'
import type { Household } from '../data/types'
import { CURRENCIES } from '../data/catalog'
import { useStore } from '../data/store'
import { css, sx } from '../lib/css'
import { useUI } from '../shell/ui'
import { PanelFrame } from './PanelFrame'
import { ChipGroup, chips, Pair, Switch, TextField, parse } from './parts'

const ACCENTS = ['#b9b0ff', '#a9c4ff', '#ffb9a8', '#d8d3c2']
const LS = {
  get(k: string) { try { return localStorage.getItem('twofold:' + k) } catch { return null } },
  set(k: string, v: string) { try { localStorage.setItem('twofold:' + k, v) } catch { /* private mode */ } },
}

type Style = NonNullable<Household['budgetStyle']>
type Mode = NonNullable<Household['splitMode']>
type Rule = NonNullable<Household['splitRule']>

function Section({ title, note, children }: { title: string; note?: string; children: ReactNode }) {
  return (
    <section style={css('display:flex;flex-direction:column;gap:14px;padding-bottom:22px;border-bottom:1px solid var(--line)')}>
      <div>
        <div style={css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")}>{title}</div>
        {note && <div style={css('font-size:13px;color:var(--mute)')}>{note}</div>}
      </div>
      {children}
    </section>
  )
}

const outline = "font:500 14px 'Geist',sans-serif;padding:0 18px;height:46px;border-radius:16px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);cursor:pointer"

export function SettingsPanel({ L }: { L: Ledger }) {
  const { act, householdId, signOut, leave, data } = useStore()
  const { close } = useUI()
  const H = L.H
  const [d, setD] = useState({
    nameA: H.nameA, nameB: H.nameB, currency: H.currency,
    budgetStyle: (H.budgetStyle ?? 'Zero-based') as Style, rollover: !!H.rollover, cushion: String(H.cushion ?? 5000),
    coachTips: H.coachTips ?? true, splitMode: (H.splitMode ?? 'One joint pot') as Mode, splitRule: (H.splitRule ?? '50/50') as Rule,
  })
  const [err, setErr] = useState('')
  const set = <K extends keyof typeof d>(k: K, v: (typeof d)[K]) => { setErr(''); setD((x) => ({ ...x, [k]: v })) }

  // Per-Mac look, applied straight away.
  const [theme, setTheme] = useState(() => (LS.get('theme') === 'night' ? 'night' : 'paper'))
  const [accent, setAccent] = useState(() => LS.get('accent') || '#b9b0ff')
  const pickTheme = (t: string) => { setTheme(t); LS.set('theme', t); document.body.dataset.theme = t }
  const pickAccent = (c: string) => { setAccent(c); LS.set('accent', c); document.body.style.setProperty('--accBase', c) }

  const [copied, setCopied] = useState(false)
  const copy = () => {
    navigator.clipboard?.writeText(householdId).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1600) }, () => {})
  }
  const joined = data.household.members.length > 1

  const save = () => {
    const nameA = d.nameA.trim(), nameB = d.nameB.trim()
    if (!nameA || !nameB) return setErr('Give each of you a name.')
    const cushion = parse(d.cushion)
    if (isNaN(cushion) || cushion < 0) return setErr('Add a cash cushion, even if it’s 0.')
    act.updateHousehold({ nameA, nameB, currency: d.currency, budgetStyle: d.budgetStyle, rollover: d.rollover, cushion, coachTips: d.coachTips, splitMode: d.splitMode, splitRule: d.splitRule })
    close()
  }

  return (
    <PanelFrame title="Settings" err={err} onSave={save}>
      <div style={css('display:flex;flex-direction:column;gap:22px')}>
        <Section title="Household" note="Shared by both of you.">
          <Pair>
            <TextField label="First name" value={d.nameA} onChange={(v) => set('nameA', v)} />
            <TextField label="Second name" value={d.nameB} onChange={(v) => set('nameB', v)} />
          </Pair>
          <ChipGroup label="Currency" chips={chips(CURRENCIES.map((c) => [c, c] as [string, string]), d.currency, (c) => set('currency', c))} />
        </Section>

        <Section title="Budgeting">
          <ChipGroup label="Budget style" chips={chips<Style>([['Zero-based', 'Zero-based'], ['Category limits', 'Category limits'], ['50/30/20', '50/30/20']], d.budgetStyle, (v) => set('budgetStyle', v))} />
          <Switch label={d.rollover ? 'Unspent money rolls into next month' : 'Each month starts fresh'} on={d.rollover} onChange={(v) => set('rollover', v)} />
          <TextField label={'Cash cushion (' + L.cur + ')'} decimal value={d.cushion} onChange={(v) => set('cushion', v)} />
          <Switch label={d.coachTips ? 'Coach tips on Today' : 'Coach tips hidden'} on={d.coachTips} onChange={(v) => set('coachTips', v)} />
          <ChipGroup grow label="How you share money" chips={chips<Mode>([['One joint pot', 'One joint pot'], ['Split shared costs', 'Split shared costs']], d.splitMode, (v) => set('splitMode', v))} />
          {d.splitMode === 'Split shared costs' && (
            <ChipGroup grow label="Split rule" chips={chips<Rule>([['50/50', '50/50'], ['By income', 'By income']], d.splitRule, (v) => set('splitRule', v))} />
          )}
        </Section>

        <Section title="Look" note="Just on this Mac.">
          <ChipGroup grow label="Theme" chips={chips([['paper', 'Paper'], ['night', 'Night']], theme, pickTheme)} />
          <div>
            <div style={css('font-size:13px;color:var(--mute);margin-bottom:8px')}>Accent</div>
            <div style={css('display:flex;gap:10px')}>
              {ACCENTS.map((c) => (
                <button key={c} type="button" onClick={() => pickAccent(c)} aria-label={'Accent ' + c} aria-pressed={accent === c}
                  style={sx('width:44px;height:44px;border-radius:15px;cursor:pointer;box-sizing:border-box', {
                    background: c, border: 'none', boxShadow: accent === c ? '0 0 0 2px var(--bg), 0 0 0 4px var(--ink)' : 'none',
                  })} />
              ))}
            </div>
          </div>
        </Section>

        <Section title="Invite code" note="Your partner enters this code to join the same budget.">
          <div style={css('display:flex;gap:10px;align-items:center')}>
            <span style={css("flex:1;min-width:0;height:52px;box-sizing:border-box;padding:0 16px;border-radius:16px;background:var(--card);font:500 20px/52px 'Geist',sans-serif;letter-spacing:.06em;overflow:hidden;text-overflow:ellipsis;user-select:all")}>{householdId}</span>
            <button type="button" onClick={copy} style={css(outline)}>{copied ? 'Copied' : 'Copy'}</button>
          </div>
          <div style={css('font-size:13.5px')}>{joined ? L.B + ' has joined. You’re both in.' : 'Waiting for your partner to join with this code.'}</div>
        </Section>

        <section style={css('display:flex;flex-wrap:wrap;gap:10px;padding-bottom:8px')}>
          <button type="button" onClick={signOut} style={css(outline)}>Sign out</button>
          <button type="button" onClick={() => { if (confirm('Leave this budget on this Mac? Your data stays with your partner; you can rejoin with the invite code.')) leave() }}
            style={sx(outline, { borderColor: 'var(--bad)', color: 'var(--bad)' })}>Leave this budget on this Mac</button>
        </section>
      </div>
    </PanelFrame>
  )
}
