import './style.css'
import HealthWorker from './health/worker.ts?worker'
import type { WorkerMessage } from './health/worker.ts'
import { clearProfile, loadProfile, saveProfile, summarize, type HealthData, type Summary } from './health/profile.ts'
import { clockTime, daysBetween, type Night } from './analysis/sleep.ts'
import type { DayEffect } from './analysis/lateNight.ts'
import { examWeekLens } from './analysis/examWeek.ts'
import { isExam, parseIcs, type CalendarEvent } from './calendar/ics.ts'

const app = document.querySelector<HTMLDivElement>('#app')!

const icon = {
  cup: '<path d="M4 8h13v5a6 6 0 0 1-6 6h-1a6 6 0 0 1-6-6z"></path><path d="M17 9h1.5a2.5 2.5 0 0 1 0 5H17v-2h1.5a.5.5 0 0 0 0-1H17z"></path>',
  calendar: '<path d="M7 2h2v2h6V2h2v2h2a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2zM5 9v10h14V9z"></path>',
  shield: '<path d="M12 2l8 3v6c0 5-3.4 9.4-8 11-4.6-1.6-8-6-8-11V5z"></path>',
  upload: '<path d="M12 3l5 5h-3v7h-4V8H7zM5 17h14v3H5z"></path>',
}
const svg = (paths: string, size = 22) =>
  `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">${paths}</svg>`

app.innerHTML = `
  <header class="top">
    <span class="date" id="date"></span>
    <span class="avatar" aria-hidden="true">A</span>
  </header>
  <h1 class="lede" id="lede">Your body, explained. <em>Read from your Apple Watch.</em></h1>
  <input type="file" id="file" class="visually-hidden" accept=".zip" />
  <section class="welcome" id="welcome">
    <label class="drop" id="drop" for="file">
      <span class="drop-button">${svg(icon.upload, 20)}Choose your Health export</span>
      <span class="muted">or drop <code>export.zip</code> anywhere on this box</span>
      <small class="muted">iPhone → Health → your photo → Export All Health Data → AirDrop to this Mac</small>
    </label>
    <div class="privacy">
      <span class="privacy-icon">${svg(icon.shield)}</span>
      <span><strong>Your data never leaves this Mac.</strong> It’s read right here in the browser and nothing is uploaded. The dashboard remembers it until you choose Forget.</span>
    </div>
  </section>
  <div class="profile-bar" id="profile-bar" hidden>
    <span id="profile-text" class="muted"></span>
    <span class="profile-actions">
      <label class="chip" for="file">${svg(icon.upload, 16)}Update from a new export</label>
      <button type="button" class="chip quiet" id="forget">Forget my data</button>
    </span>
  </div>
  <div id="status" class="status muted" aria-live="polite"></div>
  <main id="cards"></main>
`

const lede = document.querySelector<HTMLHeadingElement>('#lede')!
const dateLine = document.querySelector<HTMLSpanElement>('#date')!
const welcome = document.querySelector<HTMLElement>('#welcome')!
const drop = document.querySelector<HTMLLabelElement>('#drop')!
const input = document.querySelector<HTMLInputElement>('#file')!
const profileBar = document.querySelector<HTMLDivElement>('#profile-bar')!
const profileText = document.querySelector<HTMLSpanElement>('#profile-text')!
const status = document.querySelector<HTMLDivElement>('#status')!
const cards = document.querySelector<HTMLElement>('#cards')!

type CalendarState =
  | { kind: 'loading' }
  | { kind: 'ready'; events: CalendarEvent[]; checkedAt: Date }
  | { kind: 'not-configured' }
  | { kind: 'error'; message: string }

let health: HealthData | undefined = loadProfile()
let calendar: CalendarState = { kind: 'loading' }

input.addEventListener('change', () => {
  if (input.files?.[0]) load(input.files[0])
  input.value = ''
})
drop.addEventListener('dragover', (e) => {
  e.preventDefault()
  drop.classList.add('over')
})
drop.addEventListener('dragleave', () => drop.classList.remove('over'))
drop.addEventListener('drop', (e) => {
  e.preventDefault()
  drop.classList.remove('over')
  const file = e.dataTransfer?.files[0]
  if (file) load(file)
})
document.querySelector('#forget')!.addEventListener('click', () => {
  if (!confirm('Forget the health data saved in this browser? Your export file isn’t touched.')) return
  clearProfile()
  health = undefined
  status.textContent = 'Forgotten. Choose an export to start again.'
  render()
})

function load(file: File) {
  status.textContent = 'Reading…'
  const worker = new HealthWorker()
  worker.onmessage = (e: MessageEvent<WorkerMessage>) => {
    const m = e.data
    if (m.kind === 'progress') {
      const pct = Math.round((m.progress.bytesRead / m.progress.totalBytes) * 100)
      status.textContent = `Reading… ${pct}% · ${m.progress.records.toLocaleString()} records`
    } else if (m.kind === 'done') {
      health = m.data
      const saved = saveProfile(m.data)
      status.textContent = saved
        ? `Read in ${m.seconds.toFixed(1)}s and saved. Next time it opens straight to your dashboard.`
        : `Read in ${m.seconds.toFixed(1)}s, but this browser wouldn’t save it, so you’ll need to choose it again next time.`
      render()
      worker.terminate()
    } else {
      status.textContent = m.message
      worker.terminate()
    }
  }
  worker.postMessage(file)
}

/** Fetches the calendar through the local dev server (see vite.config.ts). */
async function refreshCalendar() {
  try {
    const r = await fetch('/api/calendar', { cache: 'no-store' })
    const body = await r.text()
    if (r.status === 404 && body === 'not-configured') calendar = { kind: 'not-configured' }
    else if (!r.ok) calendar = { kind: 'error', message: 'Google didn’t accept the calendar address. Check the link in .env.local.' }
    else calendar = { kind: 'ready', events: parseIcs(body), checkedAt: new Date() }
  } catch {
    calendar = { kind: 'error', message: 'Couldn’t reach the dashboard’s server. Is npm run dev still running?' }
  }
  render()
}

function localToday(): string {
  const t = new Date()
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${t.getFullYear()}-${pad(t.getMonth() + 1)}-${pad(t.getDate())}`
}

function exams(): CalendarEvent[] {
  return calendar.kind === 'ready' ? calendar.events.filter((e) => isExam(e.title)) : []
}

function render() {
  dateLine.textContent = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' })
  welcome.hidden = !!health
  profileBar.hidden = !health
  if (health) {
    const when = new Date(health.importedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
    profileText.textContent = `Health data through ${health.nights.length ? shortDate(health.nights[health.nights.length - 1].date) : '—'}, from the export you added ${when}.`
  }
  const s = health ? summarize(health) : undefined
  lede.innerHTML = s ? greeting(s) : 'Your body, explained. <em>Read from your Apple Watch.</em>'
  cards.innerHTML = [
    s ? sleepCard(s) : '',
    calendarCard(),
    s ? weekendCard(s) : '',
    s ? lateNightCard(s) : '',
    s ? caffeineCard(s) : '',
    s ? dataCard(s) : '',
  ].join('')
}

function greeting({ weekendShift: w }: Summary): string {
  const hour = new Date().getHours()
  const part = hour < 12 ? 'morning' : hour < 18 ? 'afternoon' : 'evening'
  const today = localToday()
  const soon = exams().find((e) => {
    const d = daysBetween(today, e.date)
    return d >= 0 && d <= 3
  })
  let advice = w
    ? `On school nights you’re usually asleep by ${clockTime(w.schoolNights.bedtime)}.`
    : 'Here’s what your Watch has been noticing.'
  if (soon) {
    const d = daysBetween(today, soon.date)
    const when = d === 0 ? 'today' : d === 1 ? 'tomorrow' : weekdayLong(soon.date)
    advice = `${escapeHtml(soon.title)} is ${when}, so protect your sleep before it.`
  }
  return `Good ${part}, Ashley. <em>${advice}</em>`
}

function calendarCard(): string {
  if (calendar.kind === 'loading') return card('Exams', 'white', '<p class="muted">Checking your calendar…</p>')
  if (calendar.kind === 'not-configured') {
    return card(
      'Connect your calendar',
      'white',
      `<p>Paste your calendar’s private link into the dashboard once, and it checks for exams every time it opens and every 30 minutes after that. No sign-in needed.</p>
       <ol class="steps">
         <li>Open <strong>calendar.google.com</strong> on this Mac → the gear → <strong>Settings</strong>.</li>
         <li>On the left, click the calendar your exams are in, then scroll to <strong>Secret address in iCal format</strong> and copy it.</li>
         <li>In the <code>health-dashboard</code> folder, make a file named <code>.env.local</code> with one line:<br /><code>CALENDAR_ICS_URL=</code> followed by the link.</li>
         <li>Stop <code>npm run dev</code> (Control-C) and start it again.</li>
       </ol>
       <p class="note">Treat that link like a password: anyone with it can read the calendar. <code>.env.local</code> is kept out of git, and the link stays on this Mac.</p>`,
    )
  }
  if (calendar.kind === 'error') return card('Exams', 'white', `<p>${calendar.message}</p>`)

  const today = localToday()
  const upcoming = exams().filter((e) => {
    const d = daysBetween(today, e.date)
    return d >= 0 && d <= 21
  })
  const list = upcoming.length
    ? `<ul class="list">${upcoming
        .slice(0, 5)
        .map((e) => {
          const d = daysBetween(today, e.date)
          const tag = d === 0 ? 'Today' : d === 1 ? 'Tomorrow' : `In ${d} days`
          return `<li><span>${escapeHtml(e.title)}<br /><span class="muted">${shortDate(e.date)}${e.minutes !== undefined ? ` · ${clockOfDay(e.minutes)}` : ''}</span></span><span class="pill ${d <= 3 ? 'peach' : 'blue'}">${tag}</span></li>`
        })
        .join('')}</ul>`
    : '<p class="muted">No exams in the next 3 weeks.</p>'

  const lens = health
    ? examWeekLens(health.nights, new Map(health.restingHr), new Map(health.hrv), exams().map((e) => e.date))
    : undefined
  const lensBody = lens
    ? `<h4>Exam weeks vs. normal weeks</h4>
       <table>
         <tr><th></th><th>Exam weeks</th><th>Normal</th></tr>
         <tr><td>Sleep</td><td>${hm(lens.examWeeks.asleepMinutes)}</td><td>${hm(lens.normalWeeks.asleepMinutes)}</td></tr>
         <tr><td>Asleep at</td><td>${clockTime(lens.examWeeks.bedtime)}</td><td>${clockTime(lens.normalWeeks.bedtime)}</td></tr>
         <tr><td>Resting HR</td><td>${num(lens.examWeeks.restingHr, ' bpm')}</td><td>${num(lens.normalWeeks.restingHr, ' bpm')}</td></tr>
         <tr><td>HRV</td><td>${num(lens.examWeeks.hrv, ' ms')}</td><td>${num(lens.normalWeeks.hrv, ' ms')}</td></tr>
       </table>
       <p class="note">“Exam week” means the 6 nights before each exam. Based on ${lens.exams} exams on your calendar in the last year, ${lens.examWeeks.nights} exam-week nights vs. ${lens.normalWeeks.nights} other nights.</p>`
    : health
      ? '<p class="note">The exam-week comparison appears once your calendar has past exams that overlap your Health data (at least 5 nights in exam weeks).</p>'
      : ''
  const checked = calendar.checkedAt.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
  return card(
    'Exams',
    'white',
    `${list}${lensBody}<p class="note">Calendar checked at ${checked}. Events with exam, midterm, final or quiz in the title count.</p>`,
  )
}

const hm = (minutes: number) => `${Math.floor(minutes / 60)}h ${Math.round(minutes % 60)}m`
const shortDate = (date: string) =>
  new Date(`${date}T00:00:00Z`).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' })
const weekday = (date: string) =>
  new Date(`${date}T00:00:00Z`).toLocaleDateString('en-US', { weekday: 'short', timeZone: 'UTC' })

/** The week chart spans 8pm to 12pm the next day, in minutes after 6pm. */
const CHART_START = 2 * 60
const CHART_SPAN = 16 * 60

function sleepCard({ lastWeek }: Summary): string {
  if (lastWeek.length === 0) return card('Sleep', 'blue', '<p class="muted">No sleep found in this export yet.</p>')
  const avg = lastWeek.reduce((sum, n) => sum + n.asleepMinutes, 0) / lastWeek.length
  const bedtimes = [...lastWeek].map((n) => n.bedtime).sort((a, b) => a - b)
  const typicalBed = bedtimes[Math.floor(bedtimes.length / 2)]
  const bar = (n: Night) => {
    const pct = (m: number) => Math.min(100, Math.max(0, ((m - CHART_START) / CHART_SPAN) * 100))
    const left = pct(n.bedtime)
    const width = Math.max(1, pct(n.wake) - left)
    const weekend = n.weekday >= 5 ? ' weekend' : ''
    return `<div class="night"><span>${weekday(n.date)}</span><div class="track"><div class="bar${weekend}" style="left:${left}%;width:${width}%"></div></div></div>`
  }
  return card(
    'Sleep',
    'blue',
    `<div class="tiles">
       ${tile('Average', hm(avg), 'blue')}
       ${tile('Asleep at', clockTime(typicalBed), 'blue')}
       ${tile('Nights', String(lastWeek.length), 'green')}
     </div>
     <div class="week" role="img" aria-label="Bedtime and wake time for your last ${lastWeek.length} nights">
       ${lastWeek.map(bar).join('')}
       <div class="axis"><span>8pm</span><span>12am</span><span>4am</span><span>8am</span><span>12pm</span></div>
     </div>
     <p class="note"><span class="key"></span>School nights <span class="key weekend"></span>Fri &amp; Sat · your last ${lastWeek.length} nights, ending ${shortDate(lastWeek[lastWeek.length - 1].date)}.</p>`,
  )
}

function weekendCard({ weekendShift: w }: Summary): string {
  if (!w) return card('Weekend shift', 'peach', '<p class="muted">Needs at least 4 school nights and 4 weekend nights in the last 8 weeks.</p>')
  const shift = Math.abs(w.midpointShift)
  const direction = w.midpointShift >= 0 ? 'later' : 'earlier'
  const verdict =
    shift < 60 ? 'Your body clock barely moves on weekends. That’s ideal.'
    : shift < 120 ? 'A small weekend shift. Monday mornings may feel a little harder.'
    : 'Like flying a time zone or two every weekend. That’s why Monday mornings feel early.'
  return card(
    'Weekend shift',
    'peach',
    `<p class="big">${hm(shift)} ${direction}</p>
     <p>${verdict}</p>
     <table>
       <tr><th></th><th>School nights</th><th>Weekends</th></tr>
       <tr><td>Asleep</td><td>${clockTime(w.schoolNights.bedtime)}</td><td>${clockTime(w.weekendNights.bedtime)}</td></tr>
       <tr><td>Awake</td><td>${clockTime(w.schoolNights.wake)}</td><td>${clockTime(w.weekendNights.wake)}</td></tr>
       <tr><td>Sleep</td><td>${hm(w.schoolNights.asleepMinutes)}</td><td>${hm(w.weekendNights.asleepMinutes)}</td></tr>
     </table>
     <p class="note">Your typical (median) night over the last ${w.weeks} weeks · ${w.schoolNights.nights} school nights, ${w.weekendNights.nights} weekend nights. Sleep researchers call this shift “social jetlag.”</p>`,
  )
}

function lateNightCard({ lateNightCost: c, recentLate }: Summary): string {
  if (!c) return card('Late-night cost', 'white', '<p class="muted">Needs at least 3 nights asleep after 2am in the last 6 months.</p>')
  const effect = (label: string, d: DayEffect, tone: string) =>
    `<div class="tile ${tone}"><span class="tile-label">${label}</span><span class="tile-value">${signed(d.restingHr, ' bpm')}</span><span class="muted">HRV ${signed(d.hrv, ' ms')}</span></div>`
  const recent = recentLate.length
    ? `<ul class="list">${recentLate
        .map((n) => `<li><span>${shortDate(n.date)} · ${clockTime(n.bedtime)}</span><span class="pill ${n.weekday >= 5 ? 'peach' : 'blue'}">${n.weekday >= 5 ? 'Weekend' : 'School night'}</span></li>`)
        .join('')}</ul>`
    : ''
  return card(
    'Late-night cost',
    'white',
    `<h3 class="serif">What a <em>2am night</em> costs you</h3>
     <div class="tiles">
       <div class="tile peach"><span class="tile-label">That night</span><span class="tile-value">−${hm(Math.max(0, c.sleepLost))}</span><span class="muted">sleep</span></div>
       ${effect('Next day', c.nextDay, 'peach')}
       ${effect('Day after', c.dayAfter, 'butter')}
     </div>
     <p class="note">Higher resting heart rate and lower HRV (heart rate variability) both mean your body is less recovered.
     Based on ${c.lateNights} late nights vs. ${c.normalNights} normal nights in the last ${c.days} days.</p>
     ${recent ? `<h4>Recent late nights</h4>${recent}` : ''}`,
  )
}

function caffeineCard(s: Summary): string {
  const body = s.caffeineLogs
    ? `<p class="big">${s.caffeineLogs} logs</p><p>Latest on ${shortDate(s.lastCaffeine!)}. The caffeine cutoff test needs 2–3 weeks of logs to compare your latest coffee with that night’s sleep.</p>`
    : '<p>No caffeine logs yet. Tap the Latte shortcut on your Watch (130 mg each) to start the caffeine cutoff test.</p>'
  return card('Caffeine', 'butter', `<span class="badge butter">${svg(icon.cup)}</span>${body}`)
}

function dataCard(s: Summary): string {
  return card(
    'Your data',
    'white',
    `<p><strong>${s.nights.toLocaleString()} nights</strong> of sleep, ${s.firstNight ? shortDate(s.firstNight) : '—'} to ${s.lastNight ? shortDate(s.lastNight) : '—'}.</p>
     <p class="note">Saved in this browser on this Mac. Add a new export any time to bring it up to date.</p>`,
  )
}

function tile(label: string, value: string, tone: string): string {
  return `<div class="tile ${tone}"><span class="tile-label">${label}</span><span class="tile-value">${value}</span></div>`
}

function num(v: number | undefined, unit: string): string {
  return v === undefined ? '<span class="muted">no data</span>' : `${Math.round(v)}${unit}`
}

function clockOfDay(minutes: number): string {
  const h = Math.floor(minutes / 60)
  const h12 = h % 12 === 0 ? 12 : h % 12
  return `${h12}:${String(minutes % 60).padStart(2, '0')}${h < 12 ? 'am' : 'pm'}`
}

function weekdayLong(date: string): string {
  return new Date(`${date}T00:00:00Z`).toLocaleDateString('en-US', { weekday: 'long', timeZone: 'UTC' })
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`)
}

function signed(v: number | undefined, unit: string): string {
  if (v === undefined) return '<span class="muted">no data</span>'
  const r = Math.round(v)
  return `${r > 0 ? '+' : r < 0 ? '−' : ''}${Math.abs(r)}${unit}`
}

function card(title: string, tone: string, body: string): string {
  return `<section class="card ${tone}"><h2>${title}</h2>${body}</section>`
}

// Start-up runs last, once every helper above is defined.
const CALENDAR_EVERY_MS = 30 * 60_000
setInterval(refreshCalendar, CALENDAR_EVERY_MS)
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible') return
  const last = calendar.kind === 'ready' ? calendar.checkedAt.getTime() : 0
  if (Date.now() - last > 5 * 60_000) refreshCalendar()
  else render() // the date line may have rolled over
})
render()
refreshCalendar()
