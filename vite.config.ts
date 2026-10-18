import { defineConfig, loadEnv } from 'vite'

// The calendar's secret iCal address lives in .env.local as CALENDAR_ICS_URL. It has no VITE_
// prefix, so it stays on this Mac's dev server and never reaches the page or git.
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  return {
    plugins: [
      {
        name: 'calendar-feed',
        configureServer(server) {
          server.middlewares.use('/api/calendar', async (_req, res) => {
            const url = env.CALENDAR_ICS_URL
            if (!url) {
              res.statusCode = 404
              res.end('not-configured')
              return
            }
            try {
              const r = await fetch(url)
              res.statusCode = r.ok ? 200 : 502
              res.setHeader('Content-Type', 'text/calendar; charset=utf-8')
              res.setHeader('Cache-Control', 'no-store')
              res.end(r.ok ? await r.text() : `calendar-error ${r.status}`)
            } catch {
              res.statusCode = 502
              res.end('calendar-unreachable')
            }
          })
        },
      },
    ],
  }
})
