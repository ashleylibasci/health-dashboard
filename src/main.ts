import './style.css'
import HealthWorker from './health/worker.ts?worker'
import type { Summary, WorkerMessage } from './health/worker.ts'
import { clockTime } from './analysis/sleep.ts'
import type { DayEffect } from './analysis/lateNight.ts'

const app = document.querySelector<HTMLDivElement>('#app')!

app.innerHTML = `
  <header>
    <h1>Health Dashboard</h1>
    <p class="muted">Your data stays on this Mac. Nothing is uploaded.</p>
  </header>
  <label class="drop" id="drop">
    <input type="file" id="file" accept=".zip" hidden />
    <strong>Drop your Health export here</strong>
    <span class="muted">or click to choose <code>export.zip</code></span>
    <small class="muted">iPhone → Health → your photo → Export All Health Data → AirDrop to this Mac</small>
  </label>
  <div id="status" class="muted" aria-live="polite"></div>
  <main id="cards"></main>
`

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
      status.textContent = `Read in ${m.seconds.toFixed(1)}s`
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
  cards.innerHTML = [weekendCard(s), lateNightCard(s), dataCard(s)].join('')
}

const hm = (minutes: number) => `${Math.floor(minutes / 60)}h ${Math.round(minutes % 60)}m`

function weekendCard({ weekendShift: w }: Summary): string {
  if (!w) return card('Weekend shift', '<p class="muted">Needs at least 4 school nights and 4 weekend nights in the last 8 weeks.</p>')
  const shift = Math.abs(w.midpointShift)
  const direction = w.midpointShift >= 0 ? 'later' : 'earlier'
  const verdict =
    shift < 60 ? 'Your body clock barely moves on weekends. That’s ideal.'
    : shift < 120 ? 'A small weekend shift. Monday mornings may feel a little harder.'
    : 'Like flying a time zone or two every weekend. Mondays will feel it.'
  return card(
    'Weekend shift',
    `<p class="big">${hm(shift)} ${direction}</p>
     <p>${verdict}</p>
     <table>
       <tr><th></th><th>School nights</th><th>Weekends</th></tr>
       <tr><td>Asleep at</td><td>${clockTime(w.schoolNights.bedtime)}</td><td>${clockTime(w.weekendNights.bedtime)}</td></tr>
       <tr><td>Wake at</td><td>${clockTime(w.schoolNights.wake)}</td><td>${clockTime(w.weekendNights.wake)}</td></tr>
       <tr><td>Sleep</td><td>${hm(w.schoolNights.asleepMinutes)}</td><td>${hm(w.weekendNights.asleepMinutes)}</td></tr>
     </table>
     <p class="muted">Typical (median) night over the last ${w.weeks} weeks · ${w.schoolNights.nights} school nights, ${w.weekendNights.nights} weekend nights.</p>`,
  )
}

function lateNightCard({ lateNightCost: c }: Summary): string {
  if (!c) return card('Late-night cost', '<p class="muted">Needs at least 3 nights asleep after 2am in the last 6 months.</p>')
  const row = (label: string, d: DayEffect) =>
    `<tr><td>${label}</td><td>${signed(d.restingHr, ' bpm')}</td><td>${signed(d.hrv, ' ms')}</td></tr>`
  return card(
    'Late-night cost',
    `<p class="big">−${hm(Math.max(0, c.sleepLost))} sleep</p>
     <p>Falling asleep after 2am costs you this much sleep compared with a normal night. Here’s how your body looks afterward:</p>
     <table>
       <tr><th></th><th>Resting HR</th><th>HRV</th></tr>
       ${row('Next day', c.nextDay)}
       ${row('Day after', c.dayAfter)}
     </table>
     <p class="muted">Higher resting HR and lower HRV both mean your body is less recovered.
     Based on ${c.lateNights} late nights vs. ${c.normalNights} normal nights in the last ${c.days} days.
     A late night can be studying or going out; the exam-week lens will tell them apart.</p>`,
  )
}

function dataCard(s: Summary): string {
  const caffeine = s.caffeineLogs
    ? `${s.caffeineLogs} caffeine logs, latest ${s.lastCaffeine}.`
    : 'No caffeine logs yet. Use the Latte shortcut on your Watch to start the caffeine cutoff test.'
  return card(
    'Your data',
    `<p>${s.nights.toLocaleString()} nights of sleep, ${s.firstNight ?? '—'} to ${s.lastNight ?? '—'}.</p><p>${caffeine}</p>`,
  )
}

function signed(v: number | undefined, unit: string): string {
  if (v === undefined) return '<span class="muted">no data</span>'
  return `${v > 0 ? '+' : ''}${v}${unit}`
}

function card(title: string, body: string): string {
  return `<section class="card"><h2>${title}</h2>${body}</section>`
}
