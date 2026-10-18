# Health Dashboard

A personal dashboard for Apple Watch data. It runs on your Mac and reads your
Health export in the browser, so nothing is uploaded anywhere.

## Run it

```sh
npm install   # first time only
npm run dev   # then open http://localhost:5173
```

Get your data: iPhone → Health → your photo (top right) → **Export All Health Data**,
then AirDrop `export.zip` to your Mac and drop it on the page. A 1.4 GB export
reads in about 8 seconds. The dashboard saves what it needs in this browser, so
it opens straight to your numbers next time. Add a new export whenever you want
fresher data, or choose **Forget my data** to clear it.

## Connect your calendar

The dashboard reads your Google Calendar through its private iCal link, with no
sign-in. In Google Calendar: gear → Settings → click your calendar → copy
**Secret address in iCal format**. Then create `.env.local` in this folder:

```sh
CALENDAR_ICS_URL=<paste the link here>
```

Restart `npm run dev`. It checks the calendar every time the page opens and every
30 minutes after that. Treat the link like a password; `.env.local` is git-ignored.

## What it shows so far

- **Weekend shift**: how far your sleep moves on Friday/Saturday nights compared
  with school nights (the "social jetlag" measure from sleep research).
- **Late-night cost**: how much sleep you lose falling asleep after 2am, and what
  happens to resting heart rate and HRV over the next two days.
- **Exams**: upcoming exams from your calendar, and how sleep, resting HR and HRV
  in the 6 nights before an exam compare with your other nights.
- **Caffeine** and **Your data**: whether caffeine logs have started, and the date range.

Coming next: the caffeine cutoff test.
See [PLAN.md](PLAN.md).

## Code map

| Path | What it does |
|---|---|
| `src/health/records.ts` | Finds the records we use in `export.xml`, scanning raw bytes |
| `src/health/readExport.ts` | Streams `export.xml` out of the zip |
| `src/health/worker.ts` | Runs the reading and analysis off the main thread |
| `src/analysis/sleep.ts` | Turns sleep-stage samples into one sleep per night |
| `src/analysis/weekendShift.ts` | School nights vs. weekend nights |
| `src/analysis/lateNight.ts` | The cost of a 2am bedtime |
| `src/health/profile.ts` | What's saved between visits, and the summary built from it |
| `src/calendar/ics.ts` | Reads the calendar feed and spots exams |
| `src/analysis/examWeek.ts` | Exam weeks vs. normal weeks |
| `vite.config.ts` | Fetches the calendar on this Mac so the link never reaches the page |
| `src/main.ts` | The page |

`npm test` runs the tests. Health data files (`*.zip`, `export.xml`) are
git-ignored so they can never be committed by accident.
