import type { TabDef, TabId } from '../shell/ui'
import { homeTab } from './home'
import { activityTab } from './activity'
import { budgetTab } from './budget'
import { billsTab } from './bills'
import { accountsTab } from './accounts'
import { savingsTab } from './savings'
import { goalsTab } from './goals'
import { reportsTab } from './reports'
import { planTab } from './plan'
import { usTab } from './us'

/** One file per tab; see shell/ui.tsx for the TabDef shape. */
export const TAB_DEFS: Record<TabId, TabDef> = {
  home: homeTab, activity: activityTab, budget: budgetTab, bills: billsTab, accounts: accountsTab,
  savings: savingsTab, goals: goalsTab, reports: reportsTab, plan: planTab, us: usTab,
}
