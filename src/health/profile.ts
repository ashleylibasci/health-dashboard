import type { Night } from '../analysis/sleep.ts'
import { weekendShift, type WeekendShift } from '../analysis/weekendShift.ts'
import { lateNightCost, LATE_BEDTIME, type LateNightCost } from '../analysis/lateNight.ts'

/**
 * The small, already-digested slice of a Health export the dashboard keeps between visits:
 * one entry per night and per day, never the raw records. It lives in this browser's
 * storage on this Mac, like the rest of the data.
 */
export interface HealthData {
  nights: Night[]
  /** [date, average resting HR] pairs. */
  restingHr: [string, number][]
  /** [date, average HRV] pairs. */
  hrv: [string, number][]
  /** Local dates of each caffeine log, sorted. */
  caffeine: string[]
  /** When the export was read, ISO time. */
  importedAt: string
}

export interface Summary {
  nights: number
  firstNight?: string
  lastNight?: string
  caffeineLogs: number
  lastCaffeine?: string
  weekendShift?: WeekendShift
  lateNightCost?: LateNightCost
  /** The most recent 7 nights, oldest first. */
  lastWeek: Night[]
  /** The 3 most recent nights asleep after 2am, newest first. */
  recentLate: Night[]
}

export function summarize(d: HealthData): Summary {
  const { nights, caffeine } = d
  return {
    nights: nights.length,
    firstNight: nights[0]?.date,
    lastNight: nights[nights.length - 1]?.date,
    caffeineLogs: caffeine.length,
    lastCaffeine: caffeine[caffeine.length - 1],
    weekendShift: weekendShift(nights),
    lateNightCost: lateNightCost(nights, new Map(d.restingHr), new Map(d.hrv)),
    lastWeek: nights.slice(-7),
    recentLate: nights.filter((n) => n.bedtime >= LATE_BEDTIME).slice(-3).reverse(),
  }
}

const KEY = 'health-dashboard:profile:v1'

export function saveProfile(d: HealthData): boolean {
  try {
    localStorage.setItem(KEY, JSON.stringify(d))
    return true
  } catch {
    return false
  }
}

export function loadProfile(): HealthData | undefined {
  try {
    const raw = localStorage.getItem(KEY)
    return raw ? (JSON.parse(raw) as HealthData) : undefined
  } catch {
    return undefined
  }
}

export function clearProfile(): void {
  try {
    localStorage.removeItem(KEY)
  } catch {
    // Nothing stored, or storage is blocked; either way there's nothing left to forget.
  }
}
