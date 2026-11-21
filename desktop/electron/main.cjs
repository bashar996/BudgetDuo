// Twofold for Mac: a window around the web app in ../dist.
// The page is served from app://twofold/ (not file://) so Firebase can keep
// you signed in and cache data offline in IndexedDB.
const { app, BrowserWindow, protocol, net, shell, Menu } = require('electron')
const path = require('node:path')
const { pathToFileURL } = require('node:url')

protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true } },
])

const DIST = path.join(__dirname, '..', 'dist')

function createWindow() {
  const win = new BrowserWindow({
    width: 1360,
    height: 900,
    minWidth: 1040,
    minHeight: 680,
    backgroundColor: '#0b0b0c',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 22, y: 22 },
    title: 'Twofold',
    webPreferences: { contextIsolation: true, sandbox: true },
  })
  // Links to other sites open in the browser, not inside the app.
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('https://')) shell.openExternal(url)
    return { action: 'deny' }
  })
  const dev = process.env.VITE_DEV_SERVER_URL
  if (dev) win.loadURL(dev)
  else win.loadURL('app://twofold/index.html')
}

app.whenReady().then(() => {
  protocol.handle('app', (req) => {
    const { pathname } = new URL(req.url)
    const file = path.normalize(path.join(DIST, decodeURIComponent(pathname)))
    if (!file.startsWith(DIST)) return new Response('Not found', { status: 404 })
    return net.fetch(pathToFileURL(file).toString())
  })
  if (process.platform === 'darwin') Menu.setApplicationMenu(Menu.buildFromTemplate([
    { role: 'appMenu' }, { role: 'editMenu' }, { role: 'viewMenu' }, { role: 'windowMenu' },
  ]))
  createWindow()
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow() })
})

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
