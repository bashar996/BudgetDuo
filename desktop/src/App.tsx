import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { css, sx } from './lib/css'
import { memoryBackend } from './data/backend'
import { demoData, emptyData } from './data/demo'
import {
  createHousehold, firebaseConfig, forgetConfig, parseConfig, saveConfig, firestoreBackend, joinHousehold, leaveHousehold, logOut, niceError,
  resetPassword, signIn, signUp, watchHousehold, watchHouseholdId, watchUser, type Live, type User,
} from './data/firebase'
import { makeActions, StoreCtx, type Ctx } from './data/store'
import type { Data, Who } from './data/types'
import { Shell } from './shell/Shell'
import { CURRENCIES } from './data/catalog'

const demoParam = new URLSearchParams(location.search).get('demo')

export function App() {
  const [demo, setDemo] = useState<string | null>(demoParam)
  if (demo !== null) return <DemoApp empty={demo === 'empty'} />
  if (!firebaseConfig) return <NoConfig onPreview={() => setDemo('')} />
  return <LiveApp />
}

/** Sample household in memory: nothing is saved or synced. */
function DemoApp({ empty }: { empty: boolean }) {
  const [data, setData] = useState<Data>(() => (empty ? emptyData() : demoData()))
  const ref = useRef(data)
  ref.current = data
  const ctx = useMemo<Ctx>(() => {
    const be = memoryBackend(ref.current, (d) => { ref.current = d; setData(d) })
    return { data: ref.current, act: makeActions(be, () => ref.current), uid: 'demo', householdId: 'DEMO2026', me: 'A', syncing: false, demo: true, signOut() { location.search = '' }, leave() {} }
  }, [])
  return <StoreCtx.Provider value={{ ...ctx, data }}><Shell /></StoreCtx.Provider>
}

function LiveApp() {
  const [user, setUser] = useState<User | null | undefined>(undefined)
  const [hid, setHid] = useState<string | null | undefined>(undefined)
  useEffect(() => watchUser(setUser), [])
  useEffect(() => {
    setHid(undefined)
    if (!user) return
    return watchHouseholdId(user.uid, setHid)
  }, [user])

  if (user === undefined || (user && hid === undefined)) return <Splash />
  if (!user) return <AuthScreen />
  if (!hid) return <SetupScreen uid={user.uid} />
  return <HouseholdApp key={hid} uid={user.uid} hid={hid} />
}

function HouseholdApp({ uid, hid }: { uid: string; hid: string }) {
  const [live, setLive] = useState<Live>({ data: null, missing: false, syncing: false })
  const [error, setError] = useState<string>()
  const dataRef = useRef<Data | null>(null)
  dataRef.current = live.data
  useEffect(() => watchHousehold(hid, setLive), [hid])
  const act = useMemo(() => makeActions(firestoreBackend(hid, setError), () => dataRef.current), [hid])

  if (live.missing) {
    return (
      <Frame kicker="Twofold" title={'We couldn’t open\nyour budget.'}>
        {live.error && <Note>{live.error}</Note>}
        <Btn onClick={() => leaveHousehold(uid)}>Start or join another</Btn>
        <Btn outline onClick={() => logOut()}>Sign out</Btn>
      </Frame>
    )
  }
  if (!live.data) return <Splash />
  const me = (live.data.household.memberWho[uid] ?? 'A') as Who
  const ctx: Ctx = { data: live.data, act, uid, householdId: hid, me, syncing: live.syncing, demo: false, signOut: () => logOut(), leave: () => leaveHousehold(uid) }
  return (
    <StoreCtx.Provider value={ctx}>
      <Shell />
      {error && (
        <button onClick={() => setError(undefined)} style={css('position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:80;max-width:520px;padding:14px 18px;border:none;border-radius:16px;background:#fbf9ef;color:#0b0b0c;font:500 14px Geist,sans-serif;box-shadow:0 12px 30px rgba(0,0,0,.35);cursor:pointer')}>
          Couldn’t save: {error}
        </button>
      )}
    </StoreCtx.Provider>
  )
}

// MARK: Sign-in and setup screens (black top, blob edge, lavender form)

function Splash() {
  return <div className="drag" style={css('height:100vh;display:grid;place-items:center;background:#0b0b0c;color:#b9b0ff;font:500 34px Geist,sans-serif;letter-spacing:-.03em')}>Twofold</div>
}

function Frame({ kicker, title, children }: { kicker: string; title: string; children: ReactNode }) {
  return (
    <div style={css('min-height:100vh;display:flex;flex-direction:column;background:#0b0b0c')}>
      <div className="drag" style={css('padding:72px 56px 0;color:#ffffff')}>
        <div style={css('font-size:14px;color:#a9a7b8')}>{kicker}</div>
        <h1 style={css("font:500 56px/1.02 'Geist',sans-serif;letter-spacing:-.04em;margin:10px 0 0;white-space:pre-line")}>{title}</h1>
      </div>
      <div data-stage="lav" style={css('flex:1;display:flex;flex-direction:column;margin-top:24px')}>
        <div style={css('height:84px;flex:none;background:var(--bg);-webkit-mask-image:var(--blob);mask-image:var(--blob);-webkit-mask-size:1200px 84px;mask-size:1200px 84px;-webkit-mask-repeat:repeat-x;mask-repeat:repeat-x')} />
        <div style={css('flex:1;background:var(--bg);color:#0b0b0c;padding:8px 56px 56px;margin-top:-1px')}>
          <div style={css('max-width:440px;display:flex;flex-direction:column;gap:12px')}>{children}</div>
        </div>
      </div>
    </div>
  )
}

const fieldStyle = css("box-sizing:border-box;width:100%;height:52px;padding:0 16px;border:none;border-radius:16px;background:#0b0b0c;color:#ffffff;font:500 15px 'Geist',sans-serif;outline:none")

function Input(p: { placeholder: string; value: string; onChange(v: string): void; type?: string; autoComplete?: string }) {
  return <input className="h-focus" type={p.type ?? 'text'} placeholder={p.placeholder} value={p.value} autoComplete={p.autoComplete} onChange={(e) => p.onChange(e.target.value)} style={fieldStyle} />
}

function Btn({ children, onClick, outline, disabled, type }: { children: ReactNode; onClick?: () => void; outline?: boolean; disabled?: boolean; type?: 'submit' | 'button' }) {
  return (
    <button type={type ?? 'button'} disabled={disabled} onClick={onClick} style={sx("height:56px;border-radius:20px;font:500 16px 'Geist',sans-serif;cursor:pointer", {
      border: outline ? '1.5px solid #0b0b0c' : 'none', background: outline ? 'transparent' : '#0b0b0c', color: outline ? '#0b0b0c' : '#ffffff', opacity: disabled ? 0.5 : 1,
    })}>{children}</button>
  )
}

function Chips({ items, value, set }: { items: string[]; value: string; set(v: string): void }) {
  return (
    <div style={css('display:flex;flex-wrap:wrap;gap:6px')}>
      {items.map((x) => (
        <button key={x} type="button" onClick={() => set(x)} aria-pressed={value === x} style={sx("height:44px;padding:0 16px;border-radius:22px;border:1.5px solid #0b0b0c;font:500 14px 'Geist',sans-serif;cursor:pointer", { background: value === x ? '#0b0b0c' : 'transparent', color: value === x ? '#ffffff' : '#0b0b0c' })}>{x}</button>
      ))}
    </div>
  )
}

const Note = ({ children }: { children: ReactNode }) => <div style={css('font-size:14px;color:#3a3566;text-wrap:pretty')}>{children}</div>
const Err = ({ children }: { children: ReactNode }) => <div role="alert" style={css('font-size:13.5px;font-weight:600;color:#0b0b0c')}>{children}</div>

function AuthScreen() {
  const [mode, setMode] = useState('Sign in')
  const [email, setEmail] = useState('')
  const [pw, setPw] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const creating = mode === 'Create account'
  const ok = email.includes('@') && pw.length >= 6
  const submit = async () => {
    setBusy(true); setErr('')
    try { await (creating ? signUp(email.trim(), pw) : signIn(email.trim(), pw)) } catch (e) { setErr(niceError(e)) }
    setBusy(false)
  }
  return (
    <Frame kicker="Twofold" title={'One budget,\ntwo of you.'}>
      <form onSubmit={(e) => { e.preventDefault(); if (ok) submit() }} style={css('display:flex;flex-direction:column;gap:12px')}>
        <Chips items={['Sign in', 'Create account']} value={mode} set={setMode} />
        <Note>{creating ? 'Use the same account as on your iPhone, or make one here. One of you starts the budget; the other joins with a code.' : 'Use the email and password from the iPhone app.'}</Note>
        <Input placeholder="Email" value={email} onChange={setEmail} type="email" autoComplete="email" />
        <Input placeholder={creating ? 'Password (6+ characters)' : 'Password'} value={pw} onChange={setPw} type="password" autoComplete={creating ? 'new-password' : 'current-password'} />
        {err && <Err>{err}</Err>}
        <Btn type="submit" disabled={busy || !ok}>{busy ? 'One moment…' : mode}</Btn>
        {!creating && (
          <button type="button" disabled={!email} onClick={async () => { try { await resetPassword(email.trim()); setErr('Check your inbox for a reset link.') } catch (e) { setErr(niceError(e)) } }}
            style={css("height:44px;border:none;background:none;color:#0b0b0c;font:500 14px 'Geist',sans-serif;cursor:pointer;align-self:flex-start;padding:0")}>Forgot password?</button>
        )}
        <button type="button" onClick={() => { forgetConfig(); location.reload() }}
          style={css("height:44px;border:none;background:none;color:#3a3566;font:500 13px 'Geist',sans-serif;cursor:pointer;align-self:flex-start;padding:0")}>Use different Firebase settings</button>
      </form>
    </Frame>
  )
}

function SetupScreen({ uid }: { uid: string }) {
  const [mode, setMode] = useState('Start new')
  const [me, setMe] = useState('')
  const [partner, setPartner] = useState('')
  const [currency, setCurrency] = useState('AED')
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const joining = mode === 'Join with a code'
  const ok = joining ? code.trim().length >= 6 : !!me.trim() && !!partner.trim()
  const submit = async () => {
    setBusy(true); setErr('')
    try { await (joining ? joinHousehold(uid, code) : createHousehold(uid, me.trim(), partner.trim(), currency)) } catch (e) { setErr(niceError(e)) }
    setBusy(false)
  }
  return (
    <Frame kicker="Set up" title={joining ? 'Join your\npartner.' : 'Start your\nshared budget.'}>
      <form onSubmit={(e) => { e.preventDefault(); if (ok) submit() }} style={css('display:flex;flex-direction:column;gap:12px')}>
        <Chips items={['Start new', 'Join with a code']} value={mode} set={setMode} />
        {joining ? (
          <>
            <Note>Your partner’s 8-character code is on their Home screen, or in Settings.</Note>
            <Input placeholder="Invite code" value={code} onChange={(v) => setCode(v.toUpperCase())} />
          </>
        ) : (
          <>
            <Note>It starts empty. You’ll add accounts, pay and limits next, and your partner joins with a code.</Note>
            <Input placeholder="Your name" value={me} onChange={setMe} autoComplete="given-name" />
            <Input placeholder="Your partner’s name" value={partner} onChange={setPartner} />
            <div style={css('font-size:13px;color:#3a3566;margin-top:4px')}>Currency</div>
            <Chips items={CURRENCIES} value={currency} set={setCurrency} />
          </>
        )}
        {err && <Err>{err}</Err>}
        <Btn type="submit" disabled={busy || !ok}>{busy ? 'One moment…' : joining ? 'Join budget' : 'Start budget'}</Btn>
        <button type="button" onClick={() => logOut()} style={css("height:44px;border:none;background:none;color:#0b0b0c;font:500 14px 'Geist',sans-serif;cursor:pointer;align-self:flex-start;padding:0")}>Sign out</button>
      </form>
    </Frame>
  )
}

function NoConfig({ onPreview }: { onPreview(): void }) {
  const [text, setText] = useState('')
  const [err, setErr] = useState('')
  const connect = () => {
    const c = parseConfig(text)
    if (!c) { setErr('That doesn’t look like the Firebase settings. Copy the whole firebaseConfig block, from { to }.'); return }
    saveConfig(c)
    location.reload()
  }
  return (
    <Frame kicker="Twofold" title={'Connect\nFirebase.'}>
      <Note>
        In the Firebase console: ⚙ Project settings → Your apps → your web app (or Add app → &lt;/&gt;). Copy the
        <b> firebaseConfig</b> block — everything from <b>{'{'}</b> to <b>{'}'}</b> — and paste it below. You only do this once on this Mac.
      </Note>
      <textarea value={text} onChange={(e) => { setText(e.target.value); setErr('') }} spellCheck={false} rows={9}
        placeholder={'{\n  apiKey: "AIza…",\n  authDomain: "….firebaseapp.com",\n  projectId: "…",\n  …\n}'}
        className="h-focus" style={css("box-sizing:border-box;width:100%;padding:14px 16px;border:none;border-radius:16px;background:#0b0b0c;color:#ffffff;font:500 13.5px/1.5 ui-monospace,Menlo,monospace;outline:none;resize:vertical")} />
      {err && <Err>{err}</Err>}
      <Btn disabled={!text.trim()} onClick={connect}>Connect</Btn>
      <Btn outline onClick={onPreview}>Look around with sample data</Btn>
    </Frame>
  )
}
