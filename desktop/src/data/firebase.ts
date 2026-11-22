// Firebase: sign-in, the household pointer and live listeners.
// The web config comes from src/firebase.config.json (see README; git-ignored).
import { initializeApp, type FirebaseApp } from 'firebase/app'
import {
  createUserWithEmailAndPassword, getAuth, onAuthStateChanged, sendPasswordResetEmail,
  signInWithEmailAndPassword, signOut, type Auth, type User,
} from 'firebase/auth'
import {
  arrayUnion, collection, deleteField, doc, type DocumentData, type Firestore, increment,
  initializeFirestore, onSnapshot, persistentLocalCache, persistentSingleTabManager, setDoc,
  Timestamp, updateDoc, writeBatch, FirestoreError,
} from 'firebase/firestore'
import type { Backend, Col, Op } from './backend'
import type { Data, Household, Who } from './types'

const found = import.meta.glob('../firebase.config.json', { eager: true, import: 'default' }) as Record<string, Record<string, string>>
export const firebaseConfig = Object.values(found)[0] as Record<string, string> | undefined

let app: FirebaseApp | undefined, auth: Auth | undefined, db: Firestore | undefined

export function fb() {
  if (!firebaseConfig) throw new Error('Missing src/firebase.config.json')
  if (!app) {
    app = initializeApp(firebaseConfig)
    auth = getAuth(app)
    // Keeps a full copy on this Mac: works offline, syncs when back online.
    db = initializeFirestore(app, {
      localCache: persistentLocalCache({ tabManager: persistentSingleTabManager({}) }),
      ignoreUndefinedProperties: true,
    })
  }
  return { auth: auth!, db: db! }
}

// MARK: Account

export const watchUser = (cb: (u: User | null) => void) => onAuthStateChanged(fb().auth, cb)
export const signIn = (email: string, pw: string) => signInWithEmailAndPassword(fb().auth, email, pw)
export const signUp = (email: string, pw: string) => createUserWithEmailAndPassword(fb().auth, email, pw)
export const resetPassword = (email: string) => sendPasswordResetEmail(fb().auth, email)
export const logOut = () => signOut(fb().auth)

export function niceError(e: unknown): string {
  const code = (e as { code?: string })?.code ?? ''
  const map: Record<string, string> = {
    'auth/invalid-credential': 'Wrong email or password.',
    'auth/wrong-password': 'Wrong email or password.',
    'auth/user-not-found': 'No account with that email.',
    'auth/email-already-in-use': 'There’s already an account with that email. Sign in instead.',
    'auth/weak-password': 'Use at least 6 characters.',
    'auth/invalid-email': 'That email doesn’t look right.',
    'auth/network-request-failed': 'No connection. Check the internet and try again.',
  }
  return map[code] ?? (e instanceof Error ? e.message : String(e))
}

/** users/{uid}.householdId; `undefined` until the server has answered. */
export function watchHouseholdId(uid: string, cb: (id: string | null | undefined) => void) {
  return onSnapshot(doc(fb().db, 'users', uid), { includeMetadataChanges: true }, (s) => {
    const id = s.data()?.householdId as string | undefined
    if (id) cb(id)
    else if (!s.metadata.fromCache) cb(null)
  }, () => cb(null))
}

/** 8 characters without look-alikes (no 0/O, 1/I/L). Same as the iPhone app. */
export function makeCode() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'
  return Array.from({ length: 8 }, () => chars[Math.floor(Math.random() * chars.length)]).join('')
}

export async function createHousehold(uid: string, me: string, partner: string, currency: string) {
  const { db } = fb()
  const code = makeCode()
  const hh: Household = {
    nameA: me, nameB: partner, currency, members: [uid], memberWho: { [uid]: 'A' },
    budgets: {}, incomes: [{ who: 'A', amt: 0, day: 1 }, { who: 'B', amt: 0, day: 1 }],
    checks: {}, roundSwept: {}, custom: [], strat: 'avalanche', extra: 0,
  }
  const b = writeBatch(db)
  b.set(doc(db, 'households', code), hh)
  b.set(doc(db, 'users', uid), { householdId: code })
  await b.commit()
}

export async function joinHousehold(uid: string, raw: string) {
  const { db } = fb()
  const code = raw.toUpperCase().replace(/[\s-]/g, '')
  if (code.length < 6) throw new Error('That code looks too short.')
  try {
    await updateDoc(doc(db, 'households', code), { members: arrayUnion(uid), ['memberWho.' + uid]: 'B' })
  } catch (e) {
    const c = (e as FirestoreError).code
    if (c === 'permission-denied' || c === 'not-found') throw new Error('No budget found for that code, or it already has two people.')
    throw e
  }
  await setDoc(doc(db, 'users', uid), { householdId: code })
}

export const leaveHousehold = (uid: string) => setDoc(doc(fb().db, 'users', uid), { householdId: '' })

// MARK: Live data

const COLS: [Col, keyof Data][] = [
  ['tx', 'tx'], ['accounts', 'accounts'], ['bills', 'bills'], ['goals', 'goals'],
  ['debts', 'debts'], ['planned', 'planned'], ['events', 'trips'],
]

/** Firestore Timestamps → Dates, document ID → id. */
function clean(id: string, d: DocumentData) {
  const o: Record<string, unknown> = { ...d, id }
  for (const [k, v] of Object.entries(o)) if (v instanceof Timestamp) o[k] = v.toDate()
  return o
}

export interface Live { data: Data | null; missing: boolean; syncing: boolean; error?: string }

export function watchHousehold(hid: string, cb: (l: Live) => void) {
  const { db } = fb()
  const root = doc(db, 'households', hid)
  const state: Partial<Data> = {}
  const pending: Record<string, boolean> = {}
  let missing = false, error: string | undefined
  const emit = () => {
    const ready = state.household && COLS.every(([, k]) => state[k])
    cb({ data: ready ? (state as Data) : null, missing, syncing: Object.values(pending).some(Boolean), error })
  }
  const unsubs = [
    onSnapshot(root, { includeMetadataChanges: true }, (s) => {
      if (!s.exists()) { if (!s.metadata.fromCache) { missing = true; emit() } return }
      missing = false
      state.household = s.data() as Household
      pending.hh = s.metadata.hasPendingWrites
      emit()
    }, (e) => { missing = true; error = e.message; emit() }),
    ...COLS.map(([col, key]) => onSnapshot(collection(root, col), { includeMetadataChanges: true }, (s) => {
      ;(state as any)[key] = s.docs.map((d) => clean(d.id, d.data()))
      pending[col] = s.metadata.hasPendingWrites
      emit()
    }, (e) => { error = e.message; emit() })),
  ]
  return () => unsubs.forEach((u) => u())
}

/** Writes go to the local cache at once and reach the server when online. */
export function firestoreBackend(hid: string, onError: (msg: string) => void): Backend {
  const { db } = fb()
  const root = doc(db, 'households', hid)
  const conv = (fields: Record<string, unknown>) => {
    const o: Record<string, unknown> = {}
    for (const [k, v] of Object.entries(fields)) {
      const op = v as { __op?: string; by?: number }
      o[k] = op && typeof op === 'object' && op.__op === 'delete' ? deleteField() : op && typeof op === 'object' && op.__op === 'inc' ? increment(op.by!) : v
    }
    return o
  }
  return {
    newId: (col) => doc(collection(root, col)).id,
    commit(ops: Op[]) {
      const b = writeBatch(db)
      for (const op of ops) {
        if (op.kind === 'put') { const { id: _id, ...rest } = op.value as any; b.set(doc(root, op.col, op.id), { ...rest, id: op.id }) }
        else if (op.kind === 'del') b.delete(doc(root, op.col, op.id))
        else if (op.col === 'household') b.update(root, conv(op.fields))
        else b.update(doc(root, op.col, op.id!), conv(op.fields))
      }
      b.commit().catch((e) => onError(e.message))
    },
  }
}

export type { User, Who }
