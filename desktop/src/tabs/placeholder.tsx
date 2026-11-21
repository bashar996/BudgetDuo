import type { TabDef, TabId } from '../shell/ui'

export const placeholder = (id: TabId, stage: 'cream' | 'lav'): TabDef => ({
  id, stage,
  kicker: () => id,
  Body: () => <div>{id}</div>,
})
