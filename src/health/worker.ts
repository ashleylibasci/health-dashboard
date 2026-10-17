/// <reference lib="webworker" />
import { readHealthExport, type ReadProgress } from './readExport.ts'
import { buildNights } from '../analysis/sleep.ts'
import { dailyAverage } from '../analysis/stats.ts'
import { weekendShift, type WeekendShift } from '../analysis/weekendShift.ts'
import { lateNightCost, type LateNightCost } from '../analysis/lateNight.ts'

export interface Summary {
  nights: number
  firstNight?: string
  lastNight?: string
  caffeineLogs: number
  lastCaffeine?: string
  weekendShift?: WeekendShift
  lateNightCost?: LateNightCost
}

export type WorkerMessage =
  | { kind: 'progress'; progress: ReadProgress }
  | { kind: 'done'; summary: Summary; seconds: number }
  | { kind: 'error'; message: string }

const post = (m: WorkerMessage) => self.postMessage(m)

self.onmessage = async (e: MessageEvent<File>) => {
  const started = performance.now()
  try {
    let lastPost = 0
    const records = await readHealthExport(e.data, (progress) => {
      const now = performance.now()
      if (now - lastPost > 100) {
        lastPost = now
        post({ kind: 'progress', progress })
      }
    })

    const nights = buildNights(records)
    const restingHr = dailyAverage(records, 'HKQuantityTypeIdentifierRestingHeartRate')
    const hrv = dailyAverage(records, 'HKQuantityTypeIdentifierHeartRateVariabilitySDNN')
    const caffeine = records
      .filter((r) => r.type === 'HKQuantityTypeIdentifierDietaryCaffeine')
      .map((r) => r.start.local.date)
      .sort()

    post({
      kind: 'done',
      seconds: (performance.now() - started) / 1000,
      summary: {
        nights: nights.length,
        firstNight: nights[0]?.date,
        lastNight: nights[nights.length - 1]?.date,
        caffeineLogs: caffeine.length,
        lastCaffeine: caffeine[caffeine.length - 1],
        weekendShift: weekendShift(nights),
        lateNightCost: lateNightCost(nights, restingHr, hrv),
      },
    })
  } catch (err) {
    post({ kind: 'error', message: err instanceof Error ? err.message : String(err) })
  }
}
