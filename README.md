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
reads in about 8 seconds.

## What it shows so far

- **Weekend shift**: how far your sleep moves on Friday/Saturday nights compared
  with school nights (the "social jetlag" measure from sleep research).
- **Late-night cost**: how much sleep you lose falling asleep after 2am, and what
  happens to resting heart rate and HRV over the next two days.
- **Your data**: date range, and whether caffeine logs have started arriving.

Coming next: Google Calendar + exam-week lens, then the caffeine cutoff test.
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
| `src/main.ts` | The page |

`npm test` runs the tests. Health data files (`*.zip`, `export.xml`) are
git-ignored so they can never be committed by accident.
