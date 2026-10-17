import { describe, expect, it } from 'vitest'
import { zipSync, strToU8 } from 'fflate'
import { RecordExtractor, parseHealthTime, type HealthRecord } from './records.ts'
import { readHealthExport } from './readExport.ts'
import { exportXml, rec, RHR, SLEEP, CORE } from '../test/fixture.ts'

describe('parseHealthTime', () => {
  it('keeps local wall-clock time and computes the absolute instant', () => {
    const t = parseHealthTime('2026-10-17 00:35:00 -0500')
    expect(t.local).toEqual({ date: '2026-10-17', minutes: 35, weekday: 6 })
    expect(new Date(t.ms).toISOString()).toBe('2026-10-17T05:35:00.000Z')
  })
})

describe('RecordExtractor', () => {
  const xml = exportXml(
    rec(RHR, '2026-10-16 08:00:00 -0500', '2026-10-16 08:00:00 -0500', '64', 'count/min') +
      rec('HKQuantityTypeIdentifierStepCount', '2026-10-16 09:00:00 -0500', '2026-10-16 09:10:00 -0500', '500') +
      rec(SLEEP, '2026-10-16 00:40:00 -0500', '2026-10-16 08:10:00 -0500', CORE),
  )

  it('keeps only wanted types and decodes attributes', () => {
    const out: HealthRecord[] = []
    new RecordExtractor((r) => out.push(r)).pushText(xml)
    expect(out.map((r) => r.type)).toEqual([RHR, SLEEP])
    expect(out[0]).toMatchObject({ value: '64', unit: 'count/min', source: "Ashley's Apple Watch" })
  })

  it('gives the same result however the text is split into chunks', () => {
    for (const size of [1, 7, 8, 9, 50, 333]) {
      const out: HealthRecord[] = []
      const ex = new RecordExtractor((r) => out.push(r))
      const bytes = new TextEncoder().encode(xml)
      for (let i = 0; i < bytes.length; i += size) ex.push(bytes.subarray(i, i + size))
      expect(out.map((r) => r.value)).toEqual(['64', CORE])
    }
  })
})

describe('readHealthExport', () => {
  it('reads export.xml out of the zip from the Health app', async () => {
    const xml = exportXml(rec(RHR, '2026-10-16 08:00:00 -0500', '2026-10-16 08:00:00 -0500', '64'))
    const zip = zipSync({
      'apple_health_export/export.xml': strToU8(xml),
      'apple_health_export/export_cda.xml': strToU8('<Record type="' + RHR + '" />'),
    })
    const records = await readHealthExport(new File([zip], 'export.zip'))
    expect(records).toHaveLength(1)
    expect(records[0].value).toBe('64')
  })

  it('explains when the zip is not a Health export', async () => {
    const zip = zipSync({ 'notes.txt': strToU8('hi') })
    await expect(readHealthExport(new File([zip], 'other.zip'))).rejects.toThrow(/No export.xml/)
  })
})
