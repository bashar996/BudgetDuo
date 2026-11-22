// PDF statements in the app: pdf.js reads the text (in a worker), pdfText.ts finds the rows.
// pdf.js is loaded only when a PDF is opened, so it doesn't slow down the app's start.
import workerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url'
import type { PdfItem } from './pdfText'

/** The PDF is encrypted: ask for the password (`wrong` after a bad one) and try again. */
export class NeedPassword extends Error {
  constructor(public wrong: boolean) { super(wrong ? 'Wrong password' : 'Password needed'); this.name = 'NeedPassword' }
}

export async function pdfItems(data: ArrayBuffer, password?: string): Promise<PdfItem[]> {
  const pdfjs = await import('pdfjs-dist')
  pdfjs.GlobalWorkerOptions.workerSrc = workerUrl
  // pdf.js takes ownership of the bytes it's given, so pass a copy (retries need the original).
  const task = pdfjs.getDocument({ data: new Uint8Array(data.slice(0)), password: password || undefined })
  let doc
  try {
    doc = await task.promise
  } catch (e: any) {
    void task.destroy()
    if (e?.name === 'PasswordException' || e instanceof pdfjs.PasswordException)
      throw new NeedPassword(e.code === pdfjs.PasswordResponses.INCORRECT_PASSWORD)
    throw new Error('This PDF couldn’t be read' + (e?.message ? ' (' + e.message + ')' : '') + '.')
  }
  try {
    const items: PdfItem[] = []
    for (let p = 1; p <= Math.min(doc.numPages, 200); p++) {
      const page = await doc.getPage(p)
      const tc = await page.getTextContent()
      for (const it of tc.items as any[]) {
        if (typeof it.str !== 'string') continue
        const t = it.transform as number[]
        items.push({ str: it.str, x: t[4], y: t[5], w: it.width ?? 0, h: it.height || Math.abs(t[3]) || 8, page: p })
      }
      page.cleanup()
    }
    return items
  } finally {
    void task.destroy()
  }
}
