// Low-level writes, so the actions in store.tsx work the same against
// Firestore (real use) and an in-memory household (the ?demo preview).
import type { Data, Household } from './types'

export type Col = 'tx' | 'accounts' | 'bills' | 'goals' | 'debts' | 'planned' | 'events'
export const DELETE = { __op: 'delete' } as const
export const inc = (by: number) => ({ __op: 'inc', by }) as const

export type Op =
  | { kind: 'put'; col: Col; id: string; value: Record<string, unknown> }
  | { kind: 'del'; col: Col; id: string }
  /** Field paths may be dotted ("budgets.groceries"). */
  | { kind: 'patch'; col: Col | 'household'; id?: string; fields: Record<string, unknown> }

export interface Backend {
  newId(col: Col): string
  commit(ops: Op[]): void
}

/** Maps a collection to the key it lives under in Data. */
export const dataKey: Record<Col, keyof Omit<Data, 'household'>> = {
  tx: 'tx', accounts: 'accounts', bills: 'bills', goals: 'goals', debts: 'debts', planned: 'planned', events: 'trips',
}

function setPath(obj: Record<string, any>, path: string, v: unknown) {
  const keys = path.split('.')
  let o = obj
  for (let i = 0; i < keys.length - 1; i++) { o[keys[i]] = { ...(o[keys[i]] ?? {}) }; o = o[keys[i]] }
  const last = keys[keys.length - 1]
  if (v && typeof v === 'object' && '__op' in (v as any)) {
    const op = v as any
    if (op.__op === 'delete') delete o[last]
    else if (op.__op === 'inc') o[last] = (o[last] ?? 0) + op.by
  } else o[last] = v
}

/** In-memory household for previews and screenshots. */
export function memoryBackend(initial: Data, onChange: (d: Data) => void): Backend {
  let data = initial
  let n = 1000
  return {
    newId: (col) => col[0] + n++,
    commit(ops) {
      const next: Data = { ...data }
      for (const op of ops) {
        if (op.kind === 'patch' && op.col === 'household') {
          const h: Record<string, any> = { ...next.household }
          for (const [k, v] of Object.entries(op.fields)) setPath(h, k, v)
          next.household = h as Household
          continue
        }
        const key = dataKey[op.col as Col]
        const list = [...(next[key] as any[])]
        if (op.kind === 'put') {
          const i = list.findIndex((x) => x.id === op.id)
          const v = { ...op.value, id: op.id }
          if (i >= 0) list[i] = v; else list.push(v)
        } else if (op.kind === 'del') {
          const i = list.findIndex((x) => x.id === op.id)
          if (i >= 0) list.splice(i, 1)
        } else {
          const i = list.findIndex((x) => x.id === op.id)
          if (i >= 0) { const x = { ...list[i] }; for (const [k, v] of Object.entries(op.fields)) setPath(x, k, v); list[i] = x }
        }
        ;(next as any)[key] = list
      }
      data = next
      onChange(data)
    },
  }
}
