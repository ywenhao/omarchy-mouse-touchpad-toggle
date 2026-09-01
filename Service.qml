import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // Injected by omarchy-shell when the service is mounted.
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginDir: {
    if (manifest && manifest.__sourceDir)
      return String(manifest.__sourceDir).replace(/\/$/, "")
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle"
  }

  readonly property string detectScript: pluginDir + "/bin/detect-mice"
  readonly property string applyScript: pluginDir + "/bin/apply-touchpad"
  readonly property string configPath: pluginDir + "/config.json"
  readonly property string managedFlagFile: Quickshell.env("HOME")
    + "/.local/state/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle/managed"

  property bool disableOnUsbMouse: true
  property bool disableOnBluetoothMouse: true
  property bool disableOnOtherMouse: false
  property bool restoreOnDisconnect: true
  property bool notify: false
  property var ignoreNamePatterns: []

  property bool mouseConnected: false
  property int mouseCount: 0
  property bool touchpadDisabled: false
  property bool managedDisable: false
  property bool applying: false
  property bool pendingRecheck: false
  property bool stateLoaded: false
  property bool _initialized: false

  function matchesAny(name, patterns) {
    if (!patterns || !patterns.length)
      return false
    var lower = String(name || "").toLowerCase()
    for (var i = 0; i < patterns.length; i++) {
      var pattern = String(patterns[i] || "").toLowerCase()
      if (pattern.length > 0 && lower.indexOf(pattern) !== -1)
        return true
    }
    return false
  }

  function busAllowed(bus) {
    if (bus === "usb")
      return disableOnUsbMouse
    if (bus === "bluetooth")
      return disableOnBluetoothMouse
    return disableOnOtherMouse
  }

  function relevantFromData(data) {
    var devices = (data && data.devices) || []
    var kept = []
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i] || {}
      var name = String(device.name || "")
      var bus = String(device.bus || "other")
      if (matchesAny(name, ignoreNamePatterns))
        continue
      if (!busAllowed(bus))
        continue
      kept.push(device)
    }
    return { connected: kept.length > 0, count: kept.length, devices: kept }
  }

  function scheduleRecheck(delayMs) {
    recheckTimer.interval = delayMs === undefined ? 150 : delayMs
    recheckTimer.restart()
  }

  function recheck() {
    if (detectProc.running) {
      pendingRecheck = true
      return
    }
    detectProc.running = true
  }

  function applyDesiredState() {
    if (applying || !stateLoaded)
      return

    var wantDisabled = mouseConnected

    if (wantDisabled) {
      // Preserve a touchpad that was already disabled by the user. Ownership
      // is claimed only when this plugin actually changes the state.
      if (touchpadDisabled)
        return

      applying = true
      applyProc.command = notify
        ? [applyScript, "off", "--notify"]
        : [applyScript, "off"]
      applyProc.intendedDisable = true
      applyProc.running = true
      return
    }

    if (!restoreOnDisconnect) {
      // Keep the disabled state and ownership so disabling or removing the
      // plugin can still restore what it changed.
      return
    }

    if (!managedDisable)
      return

    applying = true
    applyProc.command = notify
      ? [applyScript, "on", "--notify"]
      : [applyScript, "on"]
    applyProc.intendedDisable = false
    applyProc.running = true
  }

  function onDetectResult(text) {
    try {
      var data = JSON.parse(String(text || "").trim() || "{}")
      var result = relevantFromData(data)
      var changed = result.connected !== mouseConnected || result.count !== mouseCount
      mouseConnected = result.connected
      mouseCount = result.count
      if (changed || !_initialized) {
        _initialized = true
        applyDesiredState()
      }
    } catch (e) {
      console.warn("dev.ywenhao.mouse-touchpad-toggle: failed to parse detect-mice output:", e)
    }
  }

  function loadConfig(text) {
    try {
      var data = JSON.parse(String(text || "").trim() || "{}")
      if (typeof data.disableOnUsbMouse === "boolean")
        disableOnUsbMouse = data.disableOnUsbMouse
      if (typeof data.disableOnBluetoothMouse === "boolean")
        disableOnBluetoothMouse = data.disableOnBluetoothMouse
      if (typeof data.disableOnOtherMouse === "boolean")
        disableOnOtherMouse = data.disableOnOtherMouse
      if (typeof data.restoreOnDisconnect === "boolean")
        restoreOnDisconnect = data.restoreOnDisconnect
      if (typeof data.notify === "boolean")
        notify = data.notify
      if (Array.isArray(data.ignoreNamePatterns))
        ignoreNamePatterns = data.ignoreNamePatterns
    } catch (e) {
      console.warn("dev.ywenhao.mouse-touchpad-toggle: invalid config.json:", e)
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.loadConfig(text())
      root.scheduleRecheck(0)
    }
    onFileChanged: reload()
  }

  Process {
    id: loadManagedProc
    command: [
      "bash", "-c",
      "mkdir -p \"$HOME/.local/state/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle\"; "
        + "managed=0; disabled=0; "
        + "[[ -f \"$HOME/.local/state/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle/managed\" ]] && managed=1; "
        + "[[ -f \"$HOME/.local/state/omarchy/toggles/hypr/touchpad-disabled-name\" ]] && disabled=1; "
        + "printf '%s %s\\n' \"$managed\" \"$disabled\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var state = String(text || "").trim().split(/\s+/)
        root.managedDisable = state[0] === "1"
        root.touchpadDisabled = state[1] === "1"
        root.stateLoaded = true
        if (root._initialized)
          root.applyDesiredState()
        else
          root.scheduleRecheck(0)
      }
    }
    onExited: function(exitCode) {
      if (!root.stateLoaded) {
        root.stateLoaded = true
        root.scheduleRecheck(0)
      }
    }
  }

  Process {
    id: detectProc
    command: [root.detectScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onDetectResult(text)
    }
    onExited: {
      if (root.pendingRecheck) {
        root.pendingRecheck = false
        root.scheduleRecheck(50)
      }
    }
  }

  Process {
    id: applyProc
    property bool intendedDisable: false
    onExited: function(exitCode) {
      root.applying = false
      if (exitCode === 0) {
        root.touchpadDisabled = intendedDisable
        root.managedDisable = intendedDisable
      } else {
        console.warn("dev.ywenhao.mouse-touchpad-toggle: apply-touchpad exited with", exitCode)
      }
      if (root.pendingRecheck) {
        root.pendingRecheck = false
        root.scheduleRecheck(50)
      }
    }
  }

  // Event-driven: input udev add/remove/change triggers a debounced recheck.
  Process {
    id: udevMonitor
    command: [
      "setpriv", "--pdeathsig", "TERM",
      "udevadm", "monitor", "--udev", "--subsystem-match=input", "--property"
    ]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line || "")
        if (text.indexOf("ACTION=") === 0
            || text.indexOf("UDEV ") === 0
            || text.indexOf("add@") !== -1
            || text.indexOf("remove@") !== -1
            || text.indexOf("change@") !== -1) {
          root.scheduleRecheck(200)
        }
      }
    }
    onExited: udevRestartTimer.restart()
  }

  Timer {
    id: udevRestartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!udevMonitor.running)
        udevMonitor.running = true
    }
  }

  Timer {
    id: recheckTimer
    interval: 150
    repeat: false
    onTriggered: root.recheck()
  }

  // Safety net for missed udev events (Bluetooth especially).
  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.scheduleRecheck(0)
  }

  Component.onCompleted: {
    loadManagedProc.running = true
  }

  // Omarchy unloads a plugin before deleting it and does not run uninstall.sh.
  // Restore only when our ownership marker proves this plugin disabled the
  // touchpad. The detached command is independent of files about to be removed.
  Component.onDestruction: {
    Quickshell.execDetached([
      "bash", "-c",
      "managed=\"$HOME/.local/state/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle/managed\"; "
        + "[[ -f \"$managed\" ]] || exit 0; "
        + "omarchy toggle touchpad on >/dev/null 2>&1 || true; "
        + "rm -f \"$HOME/.local/state/omarchy/toggles/hypr/touchpad-disabled-name\" \"$managed\""
    ])
  }

  IpcHandler {
    target: "mouse-touchpad-toggle"

    function status(): string {
      return JSON.stringify({
        mouseConnected: root.mouseConnected,
        mouseCount: root.mouseCount,
        touchpadDisabled: root.touchpadDisabled,
        managedDisable: root.managedDisable,
        disableOnUsbMouse: root.disableOnUsbMouse,
        disableOnBluetoothMouse: root.disableOnBluetoothMouse,
        restoreOnDisconnect: root.restoreOnDisconnect,
        notify: root.notify
      })
    }

    function refresh(): void {
      root.scheduleRecheck(0)
    }
  }
}
