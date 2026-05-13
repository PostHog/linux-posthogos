const { app, BrowserWindow, ipcMain, shell } = require('electron')
const { spawn } = require('child_process')
const path = require('path')

app.disableHardwareAcceleration()
app.commandLine.appendSwitch('disable-gpu')
app.commandLine.appendSwitch('disable-gpu-compositing')

const repoDir = '/opt/posthogos/code/posthog'

const commands = {
  install: ['konsole', ['--workdir', repoDir, '-e', 'bash', '-lc', 'sudo /usr/local/bin/calamares-online.sh; exec bash']],
  code: ['dolphin', [repoDir]],
  cursor: ['cursor', [repoDir]],
  terminal: ['konsole', ['--workdir', repoDir, '-e', 'bash', '-lc', 'pwd; exec bash']],
  'claude-code': ['konsole', ['--workdir', repoDir, '-e', 'bash', '-lc', 'claude; exec bash']],
  'codex-cli': ['konsole', ['--workdir', repoDir, '-e', 'bash', '-lc', 'codex; exec bash']],
  'claude-desktop': ['claude-desktop', []],
  'codex-desktop': ['bash', ['-lc', 'command -v codex-desktop >/dev/null 2>&1 && exec codex-desktop || exec konsole --workdir /opt/posthogos/code/posthog -e bash -lc "codex; exec bash"']],
  github: ['github-desktop', []],
  docker: ['bash', ['-lc', 'sudo systemctl start docker.service >/dev/null 2>&1 || true; exec docker-desktop']],
}

function run(command, args) {
  const child = spawn(command, args, {
    detached: true,
    stdio: 'ignore',
    env: process.env,
  })

  child.unref()
}

function createWindow() {
  const win = new BrowserWindow({
    width: 860,
    height: 600,
    minWidth: 720,
    minHeight: 500,
    backgroundColor: '#fdfdf8',
    title: 'PostHogOS',
    icon: '/usr/share/pixmaps/posthogos.svg',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  win.setMenuBarVisibility(false)
  win.loadFile(path.join(__dirname, 'index.html'))
}

ipcMain.handle('run-action', async (_event, action) => {
  if (action === 'docs') {
    await shell.openExternal('https://posthog.com/docs')
    return
  }

  const command = commands[action]
  if (!command) {
    return
  }

  run(command[0], command[1])
})

ipcMain.handle('close-window', (event) => {
  BrowserWindow.fromWebContents(event.sender)?.close()
})

app.whenReady().then(createWindow)

app.on('window-all-closed', () => {
  app.quit()
})
