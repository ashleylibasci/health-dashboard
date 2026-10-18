/// <reference lib="webworker" />
import { readHealthExport, type ReadProgress } from './readExport.ts'
import { buildNights } from '../analysis/sleep.ts'
import { dailyAverage } from '../analysis/stats.ts'
import type { HealthData } from './profile.ts'

export type WorkerMessage =
  | { kind: 'progress'; progress: ReadProgress }
  | { kind: 'done'; data: HealthData; seconds: number }
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

    const round = (m: Map<string, number>): [string, number][] =>
      [...m].map(([day, v]) => [day, Math.round(v * 10) / 10])

    post({
      kind: 'done',
      seconds: (performance.now() - started) / 1000,
      data: {
        nights: buildNights(records),
        restingHr: round(dailyAverage(records, 'HKQuantityTypeIdentifierRestingHeartRate')),
        hrv: round(dailyAverage(records, 'HKQuantityTypeIdentifierHeartRateVariabilitySDNN')),
        caffeine: records
          .filter((r) => r.type === 'HKQuantityTypeIdentifierDietaryCaffeine')
          .map((r) => r.start.local.date)
          .sort(),
        importedAt: new Date().toISOString(),
      },
    })
  } catch (err) {
    post({ kind: 'error', message: err instanceof Error ? err.message : String(err) })
  }
}
