import { daysBetween, shiftDate, type Night } from './sleep.ts'
import { mean, median } from './stats.ts'

/** The nights in the run-up to an exam: the 6 evenings before exam day. */
const RUN_UP_DAYS = 6
const MIN_NIGHTS_EACH = 5

export interface WeekLook {
  nights: number
  asleepMinutes: number
  bedtime: number
  restingHr?: number
  hrv?: number
}

export interface ExamWeekLens {
  exams: number
  examWeeks: WeekLook
  normalWeeks: WeekLook
  days: number
}

/**
 * Sleep, resting HR and HRV in the week before each exam, compared with the rest of her nights.
 * The night after an exam is left out of "normal", since that's often catch-up sleep.
 */
export function examWeekLens(
  nights: Night[],
  restingHr: Map<string, number>,
  hrv: Map<string, number>,
  examDates: string[],
  days = 365,
): ExamWeekLens | undefined {
  if (nights.length === 0) return undefined
  const latest = nights[nights.length - 1].date
  const recent = nights.filter((n) => daysBetween(n.date, latest) < days)
  const exams = [...new Set(examDates)].filter((d) => {
    const since = daysBetween(latest, d)
    return since <= 1 && since > -days
  })

  const runUp = new Set<string>()
  const recovery = new Set<string>()
  for (const e of exams) {
    for (let k = 1; k <= RUN_UP_DAYS; k++) runUp.add(shiftDate(e, -k))
    recovery.add(e)
  }
  const exam = recent.filter((n) => runUp.has(n.date))
  const normal = recent.filter((n) => !runUp.has(n.date) && !recovery.has(n.date))
  if (exam.length < MIN_NIGHTS_EACH || normal.length < MIN_NIGHTS_EACH) return undefined

  const look = (ns: Night[]): WeekLook => {
    const series = (m: Map<string, number>) => {
      const v = mean(ns.map((n) => m.get(n.wakeDate)).filter((x): x is number => x !== undefined))
      return v === undefined ? undefined : Math.round(v * 10) / 10
    }
    return {
      nights: ns.length,
      asleepMinutes: median(ns.map((n) => n.asleepMinutes))!,
      bedtime: median(ns.map((n) => n.bedtime))!,
      restingHr: series(restingHr),
      hrv: series(hrv),
    }
  }
  return { exams: exams.length, examWeeks: look(exam), normalWeeks: look(normal), days }
}
