import { daysBetween, type Night } from './sleep.ts'
import { median } from './stats.ts'

export interface SleepPattern {
  nights: number
  bedtime: number
  wake: number
  asleepMinutes: number
}

export interface WeekendShift {
  schoolNights: SleepPattern
  weekendNights: SleepPattern
  /**
   * How far the middle of her sleep moves on weekends, in minutes ("social jetlag").
   * Positive means later on weekends.
   */
  midpointShift: number
  weeks: number
}

const MIN_NIGHTS_EACH = 4

/**
 * Compares school nights (Sun–Thu evenings) with weekend nights (Fri–Sat evenings)
 * over the most recent `weeks` weeks of data.
 */
export function weekendShift(nights: Night[], weeks = 8): WeekendShift | undefined {
  if (nights.length === 0) return undefined
  const latest = nights[nights.length - 1].date
  const recent = nights.filter((n) => daysBetween(n.date, latest) < weeks * 7)

  const school = recent.filter((n) => n.weekday <= 4)
  const weekend = recent.filter((n) => n.weekday >= 5)
  if (school.length < MIN_NIGHTS_EACH || weekend.length < MIN_NIGHTS_EACH) return undefined

  const schoolNights = pattern(school)
  const weekendNights = pattern(weekend)
  const midpoint = (p: SleepPattern) => (p.bedtime + p.wake) / 2
  return {
    schoolNights,
    weekendNights,
    midpointShift: Math.round(midpoint(weekendNights) - midpoint(schoolNights)),
    weeks,
  }
}

function pattern(nights: Night[]): SleepPattern {
  return {
    nights: nights.length,
    bedtime: median(nights.map((n) => n.bedtime))!,
    wake: median(nights.map((n) => n.wake))!,
    asleepMinutes: median(nights.map((n) => n.asleepMinutes))!,
  }
}
