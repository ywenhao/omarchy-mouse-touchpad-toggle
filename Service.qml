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

  readonly property string helperScript: pluginDir + "/bin/plugin-helper"
  readonly property string configPath: pluginDir + "/config.json"
  readonly property int maxHelperOutputChars: 65536
  readonly property int maxDevices: 64
  readonly property int maxPatterns: 32
  readonly property int maxPatternChars: 128
  readonly property int maxDeviceNameChars: 128

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
  property bool configLoaded: false
  property bool configReloadPending: false
  property bool _initialized: false

  function parseHelperJson(text) {
    var raw = String(text || "")
    if (raw.length === 0 || raw.length > maxHelperOutputChars)
      throw new Error("helper output size is invalid")
    var data = JSON.parse(raw)
    if (!data || typeof data !== "object" || Array.isArray(data))
      throw new Error("helper output is not an object")
    return data
  }

  function boundedString(value, maxLength) {
    if (typeof value !== "string" || value.length > maxLength)
      return false
    for (var i = 0; i < value.length; i++) {
      var code = value.charCodeAt(i)
      if (code < 32 || (code >= 127 && code <= 159))
        return false
    }
    return true
  }

  function boundedInteger(value, maximum) {
    return typeof value === "number" && isFinite(value)
      && Math.floor(value) === value && value >= 0 && value <= maximum
  }

  function hasOnlyKeys(value, keys) {
    var allowed = ({})
    for (var i = 0; i < keys.length; i++)
      allowed[keys[i]] = true
    for (var key in value) {
      if (!allowed[key])
        return false
    }
    return true
  }

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
    if (!stateLoaded || !configLoaded)
      return
    if (detectProc.running) {
      pendingRecheck = true
      return
    }
    detectProc.accepted = false
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
        ? [helperScript, "touchpad", "off", "--notify"]
        : [helperScript, "touchpad", "off"]
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
      ? [helperScript, "touchpad", "on", "--notify"]
      : [helperScript, "touchpad", "on"]
    applyProc.intendedDisable = false
    applyProc.running = true
  }

  function onDetectResult(text) {
    try {
      var data = parseHelperJson(text)
      var detectionKeys = [
        "schemaVersion", "type", "ok", "usb", "bluetooth",
        "other", "total", "devices"
      ]
      if (data.schemaVersion !== 1 || data.type !== "detection"
          || data.ok !== true || !hasOnlyKeys(data, detectionKeys)
          || !boundedInteger(data.usb, maxDevices)
          || !boundedInteger(data.bluetooth, maxDevices)
          || !boundedInteger(data.other, maxDevices)
          || !boundedInteger(data.total, maxDevices)
          || !Array.isArray(data.devices) || data.devices.length > maxDevices
          || data.total !== data.devices.length
          || data.total !== data.usb + data.bluetooth + data.other)
        return false
      for (var i = 0; i < data.devices.length; i++) {
        var device = data.devices[i]
        if (!device || typeof device !== "object"
            || !hasOnlyKeys(device, ["name", "bus"])
            || !boundedString(device.name, maxDeviceNameChars)
            || ["usb", "bluetooth", "other"].indexOf(device.bus) === -1)
          return false
      }
      var result = relevantFromData(data)
      var changed = result.connected !== mouseConnected || result.count !== mouseCount
      mouseConnected = result.connected
      mouseCount = result.count
      if (changed || !_initialized) {
        _initialized = true
        applyDesiredState()
      }
      return true
    } catch (e) {
      console.warn("dev.ywenhao.mouse-touchpad-toggle: failed to parse detect-mice output:", e)
      return false
    }
  }

  function loadConfig(text) {
    try {
      var data = parseHelperJson(text)
      var booleanKeys = [
        "disableOnUsbMouse", "disableOnBluetoothMouse",
        "disableOnOtherMouse", "restoreOnDisconnect", "notify"
      ]
      var configKeys = ["schemaVersion", "type", "ignoreNamePatterns"].concat(booleanKeys)
      if (data.schemaVersion !== 1 || data.type !== "config"
          || !hasOnlyKeys(data, configKeys))
        return false
      for (var i = 0; i < booleanKeys.length; i++) {
        if (typeof data[booleanKeys[i]] !== "boolean")
          return false
      }
      if (!Array.isArray(data.ignoreNamePatterns)
          || data.ignoreNamePatterns.length > maxPatterns)
        return false
      for (var j = 0; j < data.ignoreNamePatterns.length; j++) {
        if (!boundedString(data.ignoreNamePatterns[j], maxPatternChars))
          return false
      }
      disableOnUsbMouse = data.disableOnUsbMouse
      disableOnBluetoothMouse = data.disableOnBluetoothMouse
      disableOnOtherMouse = data.disableOnOtherMouse
      restoreOnDisconnect = data.restoreOnDisconnect
      notify = data.notify
      ignoreNamePatterns = data.ignoreNamePatterns.slice(0)
      return true
    } catch (e) {
      console.warn("dev.ywenhao.mouse-touchpad-toggle: invalid config.json:", e)
      return false
    }
  }

  function requestConfigReload() {
    if (configProc.running) {
      configReloadPending = true
      return
    }
    configProc.accepted = false
    configProc.running = true
  }

  function loadState(text) {
    try {
      var data = parseHelperJson(text)
      if (data.schemaVersion !== 1 || data.type !== "state"
          || !hasOnlyKeys(data, ["schemaVersion", "type", "managed", "disabled"])
          || typeof data.managed !== "boolean" || typeof data.disabled !== "boolean")
        return false
      managedDisable = data.managed
      touchpadDisabled = data.disabled
      stateLoaded = true
      if (_initialized)
        applyDesiredState()
      else if (configLoaded)
        scheduleRecheck(0)
      return true
    } catch (e) {
      console.warn("dev.ywenhao.mouse-touchpad-toggle: failed to load state:", e)
      return false
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: root.requestConfigReload()
  }

  Process {
    id: loadManagedProc
    property bool accepted: false
    command: [root.helperScript, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: loadManagedProc.accepted = root.loadState(text)
    }
    onExited: function(exitCode) {
      if (!accepted)
        stateRetryTimer.restart()
    }
  }

  Process {
    id: configProc
    property bool accepted: false
    command: [root.helperScript, "config", root.pluginDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        configProc.accepted = root.loadConfig(text)
        if (configProc.accepted) {
          root.configLoaded = true
          root._initialized = false
          if (root.stateLoaded)
            root.scheduleRecheck(0)
        }
      }
    }
    onExited: function(exitCode) {
      if (root.configReloadPending) {
        root.configReloadPending = false
        configRetryTimer.interval = 50
        configRetryTimer.restart()
      } else if (!accepted) {
        configRetryTimer.interval = 1000
        configRetryTimer.restart()
      }
    }
  }

  Process {
    id: detectProc
    property bool accepted: false
    command: [root.helperScript, "detect"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: detectProc.accepted = root.onDetectResult(text)
    }
    onExited: {
      if (root.pendingRecheck) {
        root.pendingRecheck = false
        root.scheduleRecheck(50)
      } else if (!accepted) {
        root.scheduleRecheck(1000)
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
        applyRetryTimer.restart()
      }
      root.applyDesiredState()
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

  Timer {
    id: configRetryTimer
    interval: 1000
    repeat: false
    onTriggered: root.requestConfigReload()
  }

  Timer {
    id: stateRetryTimer
    interval: 1000
    repeat: false
    onTriggered: {
      loadManagedProc.accepted = false
      if (!loadManagedProc.running)
        loadManagedProc.running = true
    }
  }

  Timer {
    id: applyRetryTimer
    interval: 1000
    repeat: false
    onTriggered: root.applyDesiredState()
  }

  // Safety net for missed udev events (Bluetooth especially).
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.scheduleRecheck(0)
  }

  Component.onCompleted: {
    requestConfigReload()
    loadManagedProc.accepted = false
    loadManagedProc.running = true
  }

  // Omarchy unloads a plugin before deleting it and has no uninstall hook.
  // Ask the helper to inspect the ownership marker, and also use the stable
  // built-in command when QML has observed plugin ownership. The latter keeps
  // the live restore working even if the plugin directory is deleted before
  // the detached helper has exec'd.
  Component.onDestruction: {
    Quickshell.execDetached([helperScript, "restore"])
    if (managedDisable)
      Quickshell.execDetached(["omarchy", "toggle", "touchpad", "on"])
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
