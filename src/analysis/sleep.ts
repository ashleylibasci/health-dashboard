import type { HealthRecord } from '../health/records.ts'

const ASLEEP = new Set([
  'HKCategoryValueSleepAnalysisAsleep',
  'HKCategoryValueSleepAnalysisAsleepUnspecified',
  'HKCategoryValueSleepAnalysisAsleepCore',
  'HKCategoryValueSleepAnalysisAsleepDeep',
  'HKCategoryValueSleepAnalysisAsleepREM',
])

/** Asleep periods more than this far apart belong to different sleeps. */
const SESSION_GAP_MS = 2 * 60 * 60_000
/** Shorter sleeps are naps and don't count as the night's sleep. */
const MIN_NIGHT_MS = 3 * 60 * 60_000

export interface Night {
  /** The evening the night started on, e.g. a 1am bedtime on Sat belongs to "Friday". */
  date: string
  /** 0 = Sunday … 6 = Saturday, for `date`. */
  weekday: number
  /** Minutes after 6pm local time (so 12:35am = 395). Keeps bedtimes after midnight in order. */
  bedtime: number
  /** Minutes after 6pm local time on the evening of `date` (so 8:30am next day = 870). */
  wake: number
  asleepMinutes: number
  /** Local calendar date she woke up on. */
  wakeDate: string
}

interface Span {
  start: number
  end: number
  startRec: HealthRecord
  endRec: HealthRecord
}

/**
 * Turns sleep-stage samples into one main sleep per night.
 * iPhone and Watch can both record the same sleep, so overlapping samples are merged
 * rather than added up.
 */
export function buildNights(records: HealthRecord[]): Night[] {
  const asleep = records
    .filter((r) => r.type === 'HKCategoryTypeIdentifierSleepAnalysis' && ASLEEP.has(r.value))
    .sort((a, b) => a.start.ms - b.start.ms)

  // Merge overlapping or touching samples into continuous asleep spans.
  const spans: Span[] = []
  for (const r of asleep) {
    const last = spans[spans.length - 1]
    if (last && r.start.ms <= last.end) {
      if (r.end.ms > last.end) {
        last.end = r.end.ms
        last.endRec = r
      }
    } else {
      spans.push({ start: r.start.ms, end: r.end.ms, startRec: r, endRec: r })
    }
  }

  // Group spans into sleep sessions (brief wake-ups don't split a night).
  const sessions: Span[][] = []
  for (const s of spans) {
    const cur = sessions[sessions.length - 1]
    if (cur && s.start - cur[cur.length - 1].end <= SESSION_GAP_MS) cur.push(s)
    else sessions.push([s])
  }

  const byDate = new Map<string, Night>()
  for (const session of sessions) {
    const first = session[0]
    const last = session[session.length - 1]
    const asleepMs = session.reduce((sum, s) => sum + (s.end - s.start), 0)
    if (asleepMs < MIN_NIGHT_MS) continue

    const bedLocal = first.startRec.start.local
    // Bedtimes before 6pm count toward the previous evening (e.g. 1am → yesterday).
    const evening = bedLocal.minutes < 18 * 60 ? shiftDate(bedLocal.date, -1) : bedLocal.date
    const bedtime = minutesAfter6pm(bedLocal.date, bedLocal.minutes, evening)
    const wakeLocal = last.endRec.end.local
    const night: Night = {
      date: evening,
      weekday: weekdayOf(evening),
      bedtime,
      wake: minutesAfter6pm(wakeLocal.date, wakeLocal.minutes, evening),
      asleepMinutes: Math.round(asleepMs / 60_000),
      wakeDate: wakeLocal.date,
    }
    // If two qualifying sleeps share an evening, keep the longer one.
    const existing = byDate.get(evening)
    if (!existing || existing.asleepMinutes < night.asleepMinutes) byDate.set(evening, night)
  }

  return [...byDate.values()].sort((a, b) => a.date.localeCompare(b.date))
}

function minutesAfter6pm(date: string, minutes: number, evening: string): number {
  return daysBetween(evening, date) * 1440 + minutes - 18 * 60
}

export function shiftDate(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + days)
  return d.toISOString().slice(0, 10)
}

export function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000)
}

export function weekdayOf(date: string): number {
  return new Date(`${date}T00:00:00Z`).getUTCDay()
}

/** Formats minutes-after-6pm as a clock time, e.g. 395 → "12:35am". */
export function clockTime(minutesAfter6pm: number): string {
  const total = (((Math.round(minutesAfter6pm) + 18 * 60) % 1440) + 1440) % 1440
  const h = Math.floor(total / 60)
  const m = total % 60
  const h12 = h % 12 === 0 ? 12 : h % 12
  return `${h12}:${String(m).padStart(2, '0')}${h < 12 ? 'am' : 'pm'}`
}
