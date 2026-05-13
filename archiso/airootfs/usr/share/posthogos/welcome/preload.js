const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('posthogos', {
  runAction: (action) => ipcRenderer.invoke('run-action', action),
  closeWindow: () => ipcRenderer.invoke('close-window'),
})
