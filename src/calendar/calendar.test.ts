import { describe, expect, it } from 'vitest'
import { isExam, parseIcs } from './ics.ts'
import { examWeekLens } from '../analysis/examWeek.ts'
import { shiftDate, type Night } from '../analysis/sleep.ts'

const ics = `BEGIN:VCALENDAR\r
BEGIN:VEVENT\r
DTSTART;VALUE=DATE:20261022\r
SUMMARY:MATH 347 Midterm\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;TZID=America/Chicago:20261020T140000\r
SUMMARY:CS 225 quiz\\, room 1404\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;TZID=America/Chicago:20260901T090000\r
RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR\r
SUMMARY:MATH 347 lecture\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;VALUE=DATE:20261101\r
SUMMARY:A very long title that Google folds onto the next li\r
 ne of the file\r
END:VEVENT\r
END:VCALENDAR\r
`

describe('parseIcs', () => {
  it('reads one-off events, unfolds long lines and skips repeating ones', () => {
    const events = parseIcs(ics)
    expect(events.map((e) => e.title)).toEqual([
      'CS 225 quiz, room 1404',
      'MATH 347 Midterm',
      'A very long title that Google folds onto the next line of the file',
    ])
    expect(events[0]).toMatchObject({ date: '2026-10-20', minutes: 14 * 60 })
    expect(events[1].minutes).toBeUndefined()
  })
})

describe('isExam', () => {
  it('matches exam words as whole words', () => {
    expect(isExam('MATH 347 Midterm')).toBe(true)
    expect(isExam('Finals week study group')).toBe(true)
    expect(isExam('Final project check-in')).toBe(true)
    expect(isExam('Examine lab results')).toBe(false)
    expect(isExam('Quizlet session')).toBe(false)
  })
})

describe('examWeekLens', () => {
  it('compares the 6 nights before exams with other nights', () => {
    const nights: Night[] = []
    const exams = ['2026-09-20', '2026-10-11']
    for (let d = 0; d < 56; d++) {
      const date = shiftDate('2026-08-30', d)
      const before = exams.some((e) => d < 56 && date < e && shiftDate(date, 6) >= e)
      nights.push({ date, weekday: 0, bedtime: before ? 420 : 360, wake: 840, asleepMinutes: before ? 360 : 480, wakeDate: shiftDate(date, 1) })
    }
    const lens = examWeekLens(nights, new Map(), new Map(), exams)!
    expect(lens.exams).toBe(2)
    expect(lens.examWeeks.nights).toBe(12)
    expect(lens.examWeeks.asleepMinutes).toBe(360)
    expect(lens.normalWeeks.asleepMinutes).toBe(480)
    expect(lens.normalWeeks.nights).toBe(56 - 12 - 2)
  })
})
