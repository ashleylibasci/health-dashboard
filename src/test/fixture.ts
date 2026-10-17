/** Builds export.xml text in Apple's format, for tests. */
export function rec(
  type: string,
  start: string,
  end: string,
  value: string,
  extra = '',
): string {
  return `<Record type="${type}" sourceName="Ashley&apos;s Apple Watch" unit="${extra}" creationDate="${end}" startDate="${start}" endDate="${end}" value="${value}">\n  <MetadataEntry key="HKTimeZone" value="America/Chicago"/>\n </Record>\n`
}

export const SLEEP = 'HKCategoryTypeIdentifierSleepAnalysis'
export const CORE = 'HKCategoryValueSleepAnalysisAsleepCore'
export const RHR = 'HKQuantityTypeIdentifierRestingHeartRate'
export const HRV = 'HKQuantityTypeIdentifierHeartRateVariabilitySDNN'

export function exportXml(body: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE HealthData [
<!ATTLIST Record type CDATA #REQUIRED>
]>
<HealthData locale="en_US">
 <ExportDate value="2026-10-17 08:00:00 -0500"/>
 <Me HKCharacteristicTypeIdentifierBiologicalSex="HKBiologicalSexFemale"/>
${body}</HealthData>
`
}

/** One night of sleep from `bed` on `evening` to `wake` the next morning (times as "HH:MM"). */
export function night(evening: string, bed: string, wake: string, tz = '-0500'): string {
  const next = new Date(`${evening}T00:00:00Z`)
  next.setUTCDate(next.getUTCDate() + 1)
  const morning = next.toISOString().slice(0, 10)
  const bedDate = bed >= '18:00' ? evening : morning
  return rec(SLEEP, `${bedDate} ${bed}:00 ${tz}`, `${morning} ${wake}:00 ${tz}`, CORE)
}
