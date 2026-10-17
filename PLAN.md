# Health Dashboard — Plan

A personal dashboard that reads Ashley's Apple Health export and Google Calendar
in the browser on her Mac. No server, no uploads, no cost.

## Decisions so far

| Topic | Decision |
|---|---|
| Hosting | Static site run locally (`npm run dev`), data never leaves the Mac |
| Health data | Apple Health export `.zip`, parsed in the browser |
| Calendar | Google Calendar, **read-only** OAuth (`calendar.readonly`), fetched each time the dashboard opens |
| Caffeine | Logged on the Watch via a Shortcut → Apple Health. Default drink: Nespresso double-shot latte, **130 mg** |
| Stress | Watch Mindfulness app → State of Mind, end-of-day reminder |
| Exam detection | Calendar events whose title contains exam, midterm, final, or quiz (editable list) |

## v1 features

1. **Caffeine cutoff test**: latest coffee time vs. that night's sleep (needs 2–3 weeks of logs)
2. **Exam-week lens**: sleep, resting HR and HRV in exam weeks vs. normal weeks (needs calendar)
3. **Late-night study cost**: next-day and two-day effect of going to bed after 2am
4. **Weekend shift / going-out**: weekday vs. weekend bedtime gap, and recovery after nights out

Plus the core cards: Recovery (with the reason), Fitness Age, Sleep Regularity, Cycle Overlay.

## Build order

1. ~~Scaffold (Vite + TypeScript)~~ done
2. ~~Health export parser~~ done (1.4 GB in ~8s)
3. ~~Weekend shift + late-night study cost~~ done
4. Google Calendar connect + exam-week lens
5. Caffeine cutoff test (once logs exist)
6. Core cards and explainer text

## One-time Google Calendar setup (about 10 minutes, free)

1. Go to console.cloud.google.com and create a project called "Health Dashboard".
2. **APIs & Services → Library**: enable **Google Calendar API**.
3. **OAuth consent screen**: choose External, leave it in **Testing**, and add your own Gmail as a test user.
4. **Credentials → Create credentials → OAuth client ID**: choose Web application and add `http://localhost:5173` as an authorized JavaScript origin.
5. Copy the Client ID into the dashboard's `.env.local` file. It is not a secret, but it stays out of git anyway.

The dashboard asks for read-only calendar access. Each time it opens, you click
**Connect calendar** once. Access lasts an hour and nothing is stored.
