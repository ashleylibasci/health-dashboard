import { describe, expect, it } from 'vitest'
import { RecordExtractor, type HealthRecord } from '../health/records.ts'
import { buildNights, clockTime, shiftDate } from './sleep.ts'
import { weekendShift } from './weekendShift.ts'
import { lateNightCost } from './lateNight.ts'
import { dailyAverage } from './stats.ts'
import { CORE, HRV, night, rec, RHR, SLEEP } from '../test/fixture.ts'

function parse(xml: string): HealthRecord[] {
  const out: HealthRecord[] = []
  new RecordExtractor((r) => out.push(r)).pushText(xml)
  return out
}

describe('buildNights', () => {
  it('assigns an after-midnight bedtime to the previous evening', () => {
    const [n] = buildNights(parse(night('2026-10-16', '00:35', '08:50')))
    expect(n.date).toBe('2026-10-16')
    expect(n.weekday).toBe(5) // Friday evening
    expect(clockTime(n.bedtime)).toBe('12:35am')
    expect(clockTime(n.wake)).toBe('8:50am')
    expect(n.wakeDate).toBe('2026-10-17')
    expect(n.asleepMinutes).toBe(8 * 60 + 15)
  })

  it('merges iPhone and Watch recording the same sleep instead of double-counting', () => {
    const watch = night('2026-10-16', '23:30', '07:30')
    const phone = rec(SLEEP, '2026-10-17 00:00:00 -0500', '2026-10-17 07:00:00 -0500', CORE)
    const [n] = buildNights(parse(watch + phone))
    expect(n.asleepMinutes).toBe(8 * 60)
  })

  it('keeps a short wake-up inside one night but ignores naps', () => {
    const xml =
      rec(SLEEP, '2026-10-16 23:00:00 -0500', '2026-10-17 03:00:00 -0500', CORE) +
      rec(SLEEP, '2026-10-17 03:20:00 -0500', '2026-10-17 07:00:00 -0500', CORE) +
      rec(SLEEP, '2026-10-17 14:00:00 -0500', '2026-10-17 15:00:00 -0500', CORE)
    const nights = buildNights(parse(xml))
    expect(nights).toHaveLength(1)
    expect(nights[0].asleepMinutes).toBe(4 * 60 + 3 * 60 + 40)
  })
})

describe('weekendShift', () => {
  it('measures how far sleep moves on Fri/Sat nights', () => {
    let xml = ''
    // Four weeks starting Sunday 2026-09-20.
    for (let d = 0; d < 28; d++) {
      const evening = shiftDate('2026-09-20', d)
      const weekend = [5, 6].includes(new Date(`${evening}T00:00:00Z`).getUTCDay())
      xml += weekend ? night(evening, '02:00', '10:00') : night(evening, '00:00', '08:00')
    }
    const w = weekendShift(buildNights(parse(xml)))!
    expect(w.midpointShift).toBe(120)
    expect(clockTime(w.schoolNights.bedtime)).toBe('12:00am')
    expect(clockTime(w.weekendNights.wake)).toBe('10:00am')
    expect(w.schoolNights.nights).toBe(20)
    expect(w.weekendNights.nights).toBe(8)
  })

  it('waits for enough nights', () => {
    expect(weekendShift(buildNights(parse(night('2026-10-16', '00:00', '08:00'))))).toBeUndefined()
  })
})

describe('lateNightCost', () => {
  it('compares sleep, resting HR and HRV after 2am bedtimes with normal nights', () => {
    let xml = ''
    for (let d = 0; d < 20; d++) {
      const evening = shiftDate('2026-09-01', d)
      const late = d % 5 === 0 // 4 late nights
      xml += late ? night(evening, '03:00', '09:00') : night(evening, '00:00', '08:00')
      const wake = shiftDate(evening, 1)
      const dayAfterLate = (d - 1) % 5 === 0
      const rhr = late ? 70 : dayAfterLate ? 67 : 64
      const hrv = late ? 40 : 55
      xml += rec(RHR, `${wake} 09:00:00 -0500`, `${wake} 09:00:00 -0500`, String(rhr))
      xml += rec(HRV, `${wake} 07:00:00 -0500`, `${wake} 07:00:00 -0500`, String(hrv))
    }
    const records = parse(xml)
    const c = lateNightCost(
      buildNights(records),
      dailyAverage(records, RHR),
      dailyAverage(records, HRV),
    )!
    expect(c.lateNights).toBe(4)
    expect(c.sleepLost).toBe(120)
    expect(c.nextDay.restingHr).toBe(6)
    expect(c.nextDay.hrv).toBe(-15)
    expect(c.dayAfter.restingHr).toBeGreaterThan(0)
  })
})
