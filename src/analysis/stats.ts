import type { HealthRecord } from '../health/records.ts'

export function median(xs: number[]): number | undefined {
  if (xs.length === 0) return undefined
  const s = [...xs].sort((a, b) => a - b)
  const mid = Math.floor(s.length / 2)
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2
}

export function mean(xs: number[]): number | undefined {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : undefined
}

/** Averages a quantity type per local calendar day, e.g. resting heart rate by date. */
export function dailyAverage(records: HealthRecord[], type: string): Map<string, number> {
  const sums = new Map<string, { total: number; n: number }>()
  for (const r of records) {
    if (r.type !== type) continue
    const v = Number(r.value)
    if (!Number.isFinite(v)) continue
    const day = r.start.local.date
    const cur = sums.get(day) ?? { total: 0, n: 0 }
    cur.total += v
    cur.n += 1
    sums.set(day, cur)
  }
  return new Map([...sums].map(([day, { total, n }]) => [day, total / n]))
}
