export interface CalendarEvent {
  title: string
  /** Local calendar date the event starts on, YYYY-MM-DD. */
  date: string
  /** Local start time as minutes after midnight, or undefined for all-day events. */
  minutes?: number
}

/** Words in an event title that mark it as an exam. Matched as whole words, any case. */
export const EXAM_WORDS = ['exam', 'midterm', 'final', 'quiz']

export function isExam(title: string, words = EXAM_WORDS): boolean {
  return words.some((w) => new RegExp(`\\b${w}s?\\b`, 'i').test(title))
}

/**
 * Reads the events out of an iCalendar (.ics) feed, the format behind Google Calendar's
 * "secret address". Only one-off events: repeating ones (classes, office hours) are skipped,
 * since exams are almost never set up as repeats.
 */
export function parseIcs(text: string): CalendarEvent[] {
  // Long lines are folded onto the next line with a leading space; join them back.
  const lines = text.replace(/\r?\n[ \t]/g, '').split(/\r?\n/)
  const events: CalendarEvent[] = []
  let cur: { title?: string; start?: string; params?: string; repeats?: boolean; cancelled?: boolean } | undefined
  for (const line of lines) {
    if (line === 'BEGIN:VEVENT') cur = {}
    else if (line === 'END:VEVENT') {
      if (cur?.start && cur.title !== undefined && !cur.repeats && !cur.cancelled) {
        const when = parseStart(cur.start, cur.params ?? '')
        if (when) events.push({ title: cur.title, ...when })
      }
      cur = undefined
    } else if (cur) {
      const colon = line.indexOf(':')
      if (colon < 0) continue
      const [name, ...params] = line.slice(0, colon).split(';')
      const value = line.slice(colon + 1)
      if (name === 'SUMMARY') cur.title = unescape(value)
      else if (name === 'DTSTART') {
        cur.start = value
        cur.params = params.join(';')
      } else if (name === 'RRULE') cur.repeats = true
      else if (name === 'STATUS' && value === 'CANCELLED') cur.cancelled = true
    }
  }
  return events.sort((a, b) => a.date.localeCompare(b.date) || (a.minutes ?? -1) - (b.minutes ?? -1))
}

function parseStart(value: string, params: string): Omit<CalendarEvent, 'title'> | undefined {
  const m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})\d{2}(Z)?)?$/.exec(value)
  if (!m) return undefined
  const [, y, mo, d, h, mi, utc] = m
  if (h === undefined || params.includes('VALUE=DATE')) return { date: `${y}-${mo}-${d}` }
  if (utc) {
    // UTC time: show it in this Mac's time zone.
    const t = new Date(Date.UTC(+y, +mo - 1, +d, +h, +mi))
    const pad = (n: number) => String(n).padStart(2, '0')
    return { date: `${t.getFullYear()}-${pad(t.getMonth() + 1)}-${pad(t.getDate())}`, minutes: t.getHours() * 60 + t.getMinutes() }
  }
  // Floating or TZID time: already the wall-clock time where the event happens.
  return { date: `${y}-${mo}-${d}`, minutes: +h * 60 + +mi }
}

function unescape(s: string): string {
  return s.replace(/\\n/gi, ' ').replace(/\\([,;\\])/g, '$1')
}
