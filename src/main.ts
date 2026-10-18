import './style.css'
import HealthWorker from './health/worker.ts?worker'
import type { Summary, WorkerMessage } from './health/worker.ts'
import { clockTime, type Night } from './analysis/sleep.ts'
import type { DayEffect } from './analysis/lateNight.ts'

const app = document.querySelector<HTMLDivElement>('#app')!

const today = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' })

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
    <span class="date">${today}</span>
    <span class="avatar" aria-hidden="true">A</span>
  </header>
  <h1 class="lede" id="lede">Your body, explained. <em>Read from your Apple Watch.</em></h1>
  <section class="welcome" id="welcome">
    <label class="drop" id="drop">
      <input type="file" id="file" accept=".zip" />
      <span class="drop-button">${svg(icon.upload, 20)}Choose your Health export</span>
      <span class="muted">or drop <code>export.zip</code> anywhere on this box</span>
      <small class="muted">iPhone → Health → your photo → Export All Health Data → AirDrop to this Mac</small>
    </label>
    <div class="privacy">
      <span class="privacy-icon">${svg(icon.shield)}</span>
      <span><strong>Your data never leaves this Mac.</strong> It’s read right here in the browser and nothing is uploaded.</span>
    </div>
  </section>
  <div id="status" class="status muted" aria-live="polite"></div>
  <main id="cards"></main>
`

const lede = document.querySelector<HTMLHeadingElement>('#lede')!
const drop = document.querySelector<HTMLLabelElement>('#drop')!
const input = document.querySelector<HTMLInputElement>('#file')!
const status = document.querySelector<HTMLDivElement>('#status')!
const cards = document.querySelector<HTMLElement>('#cards')!

input.addEventListener('change', () => input.files?.[0] && load(input.files[0]))
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

function load(file: File) {
  cards.innerHTML = ''
  status.textContent = 'Reading…'
  const worker = new HealthWorker()
  worker.onmessage = (e: MessageEvent<WorkerMessage>) => {
    const m = e.data
    if (m.kind === 'progress') {
      const pct = Math.round((m.progress.bytesRead / m.progress.totalBytes) * 100)
      status.textContent = `Reading… ${pct}% · ${m.progress.records.toLocaleString()} records`
    } else if (m.kind === 'done') {
      status.textContent = `Read in ${m.seconds.toFixed(1)}s · choose another export above to refresh`
      render(m.summary)
      worker.terminate()
    } else {
      status.textContent = m.message
      worker.terminate()
    }
  }
  worker.postMessage(file)
}

function render(s: Summary) {
  lede.innerHTML = greeting(s)
  cards.innerHTML = [sleepCard(s), weekendCard(s), lateNightCard(s), caffeineCard(s), dataCard(s)].join('')
}

function greeting({ weekendShift: w }: Summary): string {
  const hour = new Date().getHours()
  const part = hour < 12 ? 'morning' : hour < 18 ? 'afternoon' : 'evening'
  const advice = w
    ? `On school nights you’re usually asleep by ${clockTime(w.schoolNights.bedtime)}.`
    : 'Here’s what your Watch has been noticing.'
  return `Good ${part}, Ashley. <em>${advice}</em>`
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
     <div class="next"><span class="badge butter">${svg(icon.calendar)}</span><span><strong>Coming next: exam-week lens</strong><br /><span class="muted">Connect your calendar to compare exam weeks with normal weeks.</span></span></div>`,
  )
}

function tile(label: string, value: string, tone: string): string {
  return `<div class="tile ${tone}"><span class="tile-label">${label}</span><span class="tile-value">${value}</span></div>`
}

function signed(v: number | undefined, unit: string): string {
  if (v === undefined) return '<span class="muted">no data</span>'
  const r = Math.round(v)
  return `${r > 0 ? '+' : r < 0 ? '−' : ''}${Math.abs(r)}${unit}`
}

function card(title: string, tone: string, body: string): string {
  return `<section class="card ${tone}"><h2>${title}</h2>${body}</section>`
}
