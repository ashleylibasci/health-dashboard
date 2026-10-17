import { daysBetween, shiftDate, type Night } from './sleep.ts'
import { mean } from './stats.ts'

/** Going to sleep at or after 2am (8 hours after 6pm) counts as a late night. */
export const LATE_BEDTIME = 8 * 60
const MIN_LATE_NIGHTS = 3

export interface DayEffect {
  /** Change in resting heart rate vs. normal, in bpm. Positive = higher (more strain). */
  restingHr?: number
  /** Change in HRV vs. normal, in ms. Negative = lower (less recovered). */
  hrv?: number
}

export interface LateNightCost {
  lateNights: number
  normalNights: number
  /** Minutes of sleep lost on a late night compared with a normal night. */
  sleepLost: number
  /** The day she wakes up after the late night. */
  nextDay: DayEffect
  /** The day after that. */
  dayAfter: DayEffect
  days: number
}

/**
 * What a late night costs: that night's sleep, and resting HR / HRV on the next two days,
 * each compared with nights she went to bed before 2am.
 */
export function lateNightCost(
  nights: Night[],
  restingHr: Map<string, number>,
  hrv: Map<string, number>,
  days = 180,
): LateNightCost | undefined {
  if (nights.length === 0) return undefined
  const latest = nights[nights.length - 1].date
  const recent = nights.filter((n) => daysBetween(n.date, latest) < days)
  const late = recent.filter((n) => n.bedtime >= LATE_BEDTIME)
  // The night after a late night is still recovery, so it isn't a fair "normal".
  const lateDates = new Set(late.map((n) => n.date))
  const normal = recent.filter(
    (n) => n.bedtime < LATE_BEDTIME && !lateDates.has(shiftDate(n.date, -1)),
  )
  if (late.length < MIN_LATE_NIGHTS || normal.length < MIN_LATE_NIGHTS) return undefined

  const avgSleep = (ns: Night[]) => mean(ns.map((n) => n.asleepMinutes))!
  return {
    lateNights: late.length,
    normalNights: normal.length,
    sleepLost: Math.round(avgSleep(normal) - avgSleep(late)),
    nextDay: effect(late, normal, restingHr, hrv, 0),
    dayAfter: effect(late, normal, restingHr, hrv, 1),
    days,
  }
}

function effect(
  late: Night[],
  normal: Night[],
  restingHr: Map<string, number>,
  hrv: Map<string, number>,
  offset: number,
): DayEffect {
  const diff = (series: Map<string, number>) => {
    const values = (ns: Night[]) =>
      ns.map((n) => series.get(shiftDate(n.wakeDate, offset))).filter((v): v is number => v !== undefined)
    const l = mean(values(late))
    const n = mean(values(normal))
    return l === undefined || n === undefined ? undefined : Math.round((l - n) * 10) / 10
  }
  return { restingHr: diff(restingHr), hrv: diff(hrv) }
}
