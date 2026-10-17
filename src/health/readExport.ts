import { Unzip, UnzipInflate } from 'fflate'
import { RecordExtractor, type HealthRecord } from './records.ts'

export interface ReadProgress {
  bytesRead: number
  totalBytes: number
  records: number
}

/**
 * Streams export.xml out of the Health export zip and returns the records we use.
 * The zip is read in chunks, so the 1+ GB XML never sits in memory at once.
 */
export async function readHealthExport(
  file: File,
  onProgress: (p: ReadProgress) => void = () => {},
): Promise<HealthRecord[]> {
  const records: HealthRecord[] = []
  const extractor = new RecordExtractor((r) => records.push(r))
  let found = false
  let failure: Error | undefined

  const unzip = new Unzip()
  unzip.register(UnzipInflate)
  unzip.onfile = (entry) => {
    if (entry.name !== 'export.xml' && !entry.name.endsWith('/export.xml')) return
    found = true
    entry.ondata = (err, chunk) => {
      if (err) {
        failure = err
        return
      }
      extractor.push(chunk)
    }
    entry.start()
  }

  const reader = file.stream().getReader()
  let bytesRead = 0
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    unzip.push(value)
    if (failure) throw failure
    bytesRead += value.length
    onProgress({ bytesRead, totalBytes: file.size, records: records.length })
  }
  unzip.push(new Uint8Array(0), true)
  if (failure) throw failure
  if (!found) throw new Error('No export.xml in this zip. Is it the file from Health → Export All Health Data?')

  return records
}
