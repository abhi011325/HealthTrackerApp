import Dexie, { type Table } from 'dexie'

/** One row per calendar day. `synced` false = not yet pushed to the database. */
export interface Weight { date: string; kg: number; evening: boolean; loggedAt: string; updatedAt: string; deleted: boolean; synced: 0 | 1 }
export interface Gap { date: string; reason: string; updatedAt: string; deleted: boolean; synced: 0 | 1 }
export interface Reason { name: string; lastUsed: string; updatedAt: string; deleted: boolean; synced: 0 | 1 }
export interface Meta { key: string; value: string }

class HealthDB extends Dexie {
  weights!: Table<Weight, string>
  gaps!: Table<Gap, string>
  reasons!: Table<Reason, string>
  meta!: Table<Meta, string>
  constructor() {
    super('healthtracker')
    this.version(1).stores({ weights: 'date, synced', gaps: 'date, synced', reasons: 'name, synced, lastUsed', meta: 'key' })
  }
}
export const db = new HealthDB()

export async function getMeta(key: string) { return (await db.meta.get(key))?.value }
export async function setMeta(key: string, value: string) { await db.meta.put({ key, value }) }
export async function clearAllLocal() { await Promise.all([db.weights.clear(), db.gaps.clear(), db.reasons.clear(), db.meta.clear()]) }
