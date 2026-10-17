// The Health record types the dashboard uses. Everything else in the export is skipped.
export const WANTED_TYPES = new Set([
  'HKCategoryTypeIdentifierSleepAnalysis',
  'HKQuantityTypeIdentifierRestingHeartRate',
  'HKQuantityTypeIdentifierHeartRateVariabilitySDNN',
  'HKQuantityTypeIdentifierDietaryCaffeine',
  'HKQuantityTypeIdentifierAppleSleepingWristTemperature',
  'HKQuantityTypeIdentifierVO2Max',
  'HKCategoryTypeIdentifierMenstrualFlow',
])

export interface HealthRecord {
  type: string
  source: string
  /** Numeric value for quantities, or the category string for categories (e.g. sleep stage). */
  value: string
  unit?: string
  start: HealthTime
  end: HealthTime
}

/**
 * A timestamp as it appears in the export: "2026-10-16 23:41:05 -0500".
 * `ms` is the absolute instant; `local` keeps the wall-clock time where it was recorded,
 * so a 1am bedtime in Champaign stays 1am even when the export is read elsewhere.
 */
export interface HealthTime {
  ms: number
  local: { date: string; minutes: number; weekday: number }
}

const TIME_RE = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})$/

export function parseHealthTime(s: string): HealthTime {
  const m = TIME_RE.exec(s)
  if (!m) throw new Error(`Unrecognized Health date: ${s}`)
  const [, y, mo, d, h, mi, sec, sign, oh, om] = m
  const wallMs = Date.UTC(+y, +mo - 1, +d, +h, +mi, +sec)
  const offsetMin = (sign === '-' ? -1 : 1) * (+oh * 60 + +om)
  return {
    ms: wallMs - offsetMin * 60_000,
    local: {
      date: `${y}-${mo}-${d}`,
      minutes: +h * 60 + +mi,
      weekday: new Date(wallMs).getUTCDay(),
    },
  }
}

const ATTR_RE = /(\w+)="([^"]*)"/g

function decodeEntities(s: string): string {
  if (!s.includes('&')) return s
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
}

const encoder = new TextEncoder()
const decoder = new TextDecoder()
const LT = 60 // <
const GT = 62 // >
const QUOTE = 34 // "
const RECORD = encoder.encode('<Record ')
const TYPE_ATTR = encoder.encode('type="')

function bytesAt(data: Uint8Array, at: number, expected: Uint8Array): boolean {
  if (at + expected.length > data.length) return false
  for (let i = 0; i < expected.length; i++) if (data[at + i] !== expected[i]) return false
  return true
}

/**
 * Pulls <Record .../> elements out of export.xml as it streams in.
 * Works on raw bytes: only the few percent of records we keep are ever decoded to text,
 * which is most of what makes a 1+ GB export fast to read.
 * Feed it chunks in order; it keeps any partial tag between calls.
 */
export class RecordExtractor {
  private leftover = new Uint8Array(0)
  private onRecord: (r: HealthRecord) => void
  private wanted: Set<string>
  private wantedBytes: Uint8Array[]
  /** Bytes needed after "<" to decide whether a record is one we want. */
  private lookahead: number

  constructor(onRecord: (r: HealthRecord) => void, wanted: Set<string> = WANTED_TYPES) {
    this.onRecord = onRecord
    this.wanted = wanted
    this.wantedBytes = [...wanted].map((t) => encoder.encode(t))
    this.lookahead = RECORD.length + TYPE_ATTR.length + Math.max(...this.wantedBytes.map((b) => b.length)) + 1
  }

  pushText(text: string): void {
    this.push(encoder.encode(text))
  }

  push(chunk: Uint8Array): void {
    let data = chunk
    if (this.leftover.length) {
      data = new Uint8Array(this.leftover.length + chunk.length)
      data.set(this.leftover)
      data.set(chunk, this.leftover.length)
    }

    let pos = 0
    for (;;) {
      const open = data.indexOf(LT, pos)
      if (open === -1) {
        pos = data.length
        break
      }
      // Too close to the end to tell what this tag is: wait for the next chunk.
      if (open + this.lookahead > data.length) {
        pos = open
        break
      }
      if (!bytesAt(data, open, RECORD)) {
        pos = open + 1
        continue
      }
      // Apple writes type first, so most records (steps, heart rate…) are skipped
      // after reading just their type.
      const typeAt = open + RECORD.length
      if (bytesAt(data, typeAt, TYPE_ATTR) && !this.isWantedAt(data, typeAt + TYPE_ATTR.length)) {
        pos = typeAt
        continue
      }
      const close = data.indexOf(GT, open)
      if (close === -1) {
        pos = open
        break
      }
      this.handleTag(decoder.decode(data.subarray(open, close)))
      pos = close + 1
    }
    this.leftover = data.slice(pos)
  }

  private isWantedAt(data: Uint8Array, at: number): boolean {
    for (const type of this.wantedBytes) {
      if (bytesAt(data, at, type) && data[at + type.length] === QUOTE) return true
    }
    return false
  }

  private handleTag(tag: string): void {
    const typeAt = tag.indexOf('type="')
    if (typeAt === -1) return
    const type = tag.slice(typeAt + 6, tag.indexOf('"', typeAt + 6))
    if (!this.wanted.has(type)) return

    const attrs: Record<string, string> = {}
    for (const [, k, v] of tag.matchAll(ATTR_RE)) attrs[k] = v
    if (!attrs.startDate || !attrs.endDate) return

    this.onRecord({
      type,
      source: decodeEntities(attrs.sourceName ?? ''),
      value: attrs.value ?? '',
      unit: attrs.unit,
      start: parseHealthTime(attrs.startDate),
      end: parseHealthTime(attrs.endDate),
    })
  }
}
