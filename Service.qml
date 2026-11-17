import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The one sampler behind every sysmon bar item. A bar is built per monitor,
// so the readings live here, once, rather than in each widget.
//
// sample.sh streams raw counters every `interval` seconds; this turns them
// into the properties the widgets bind to and keeps a short history for the
// graphs. The heavier sources (the process list, filesystem sizes) only run
// while a panel that shows them is open.
Item {
  id: root

  // Injected by the shell for service plugins. Unused, but declared so the
  // assignment has somewhere to land.
  property var shell: null

  readonly property int interval: 2
  // Two minutes of history at the default interval.
  readonly property int historyLength: 60
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/+$/, "")

  // False until the second frame, when rates first have something to compare.
  property bool ready: false
  property double uptime: 0

  // ---- cpu
  property string cpuModel: ""
  property real cpuUsage: 0
  property real cpuUser: 0
  property real cpuSystem: 0
  property var cpuCores: []
  property var cpuHistory: []
  property var cpuTemp: null
  property var load: ({ one: 0, five: 0, fifteen: 0, tasks: 0 })

  // ---- memory
  property var memory: Model.parseMeminfo([])
  property var memoryHistory: []

  // ---- gpu
  property var gpus: []
  // The card the bar item shows: the busiest one that reports its load.
  property var gpu: null
  property var gpuHistory: []

  // ---- disks
  property var filesystems: []
  property var filesystem: null
  property real diskRead: 0
  property real diskWrite: 0
  property var diskReadHistory: []
  property var diskWriteHistory: []
  property var diskTemps: []

  // ---- processes, grouped by program
  property var topByCpu: []
  property var topByMemory: []

  // How many open panels want the process list. Counted rather than a flag
  // because the same panel can be open on more than one monitor's bar.
  property int processWatchers: 0
  function watchProcesses(on) {
    processWatchers = Math.max(0, processWatchers + (on ? 1 : -1))
  }
  onProcessWatchersChanged: if (processWatchers > 0 && !topProc.running) topProc.running = true

  function refreshFilesystems() {
    if (!dfProc.running) dfProc.running = true
  }

  // Drive temperatures are read on request only, never on the sampling
  // timer: each read sends the drive a command, and polling it made input
  // stutter on an Apple T2 laptop. The disk panel asks while it is open.
  function refreshDiskTemps() {
    if (!diskTempProc.running) diskTempProc.running = true
  }

  // ---------------------------------------------------------------- frames

  property var _lines: []
  property var _static: ({ cpuModel: "", blocks: [], gpuNames: {} })
  property var _previousCpu: null
  property var _previousDisks: null
  property double _previousUptime: 0

  function consume(line) {
    if (line === "@@end") {
      var block = Model.parseBlock(_lines)
      _lines = []
      if (block.kind === "static") applyStatic(block)
      else if (block.kind === "frame") applyFrame(block)
      return
    }
    if (line === "@@static" || line.indexOf("@@frame") === 0) _lines = []
    // A frame is a few dozen lines; anything far past that is not ours.
    if (_lines.length < 4096) _lines.push(line)
  }

  function applyStatic(block) {
    _static = Model.parseStatic(block.sections)
    cpuModel = _static.cpuModel
  }

  function applyFrame(block) {
    var sections = block.sections
    var seconds = block.uptime - _previousUptime

    var times = Model.parseCpuTimes(sections.stat || [])
    var usage = Model.cpuUsage(_previousCpu, times)
    _previousCpu = times
    if (usage.ready) {
      cpuUsage = usage.total
      cpuUser = usage.user
      cpuSystem = usage.system
      cpuCores = usage.cores
      cpuHistory = Model.pushHistory(cpuHistory, usage.total, historyLength)
    }
    load = Model.parseLoad(sections.loadavg || [])

    memory = Model.parseMeminfo(sections.meminfo || [])
    memoryHistory = Model.pushHistory(memoryHistory, memory.fraction, historyLength)

    var temps = Model.parseTemps(sections.temps || [])
    cpuTemp = temps.cpu

    var disks = Model.parseDiskstats(sections.diskstats || [], _static.blocks)
    if (_previousDisks && seconds > 0) {
      var rates = Model.diskRates(_previousDisks, disks, seconds)
      diskRead = rates.read
      diskWrite = rates.write
      diskReadHistory = Model.pushHistory(diskReadHistory, rates.read, historyLength)
      diskWriteHistory = Model.pushHistory(diskWriteHistory, rates.write, historyLength)
    }
    _previousDisks = disks

    gpus = Model.parseGpus(sections.gpus || [], _static.gpuNames, sections.nvidia || [])
    gpu = Model.primaryGpu(gpus)
    gpuHistory = Model.pushHistory(gpuHistory, gpu ? gpu.busy : 0, historyLength)

    uptime = block.uptime
    _previousUptime = block.uptime
    if (usage.ready) ready = true
  }

  Process {
    id: sampler
    command: ["bash", root.pluginDir + "/sample.sh", String(root.interval)]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.consume(line) }
    }
    // The sampler has no reason to stop; if it does, start over from a clean
    // slate so the first rates are not measured across the gap.
    onExited: {
      root._lines = []
      root._previousCpu = null
      root._previousDisks = null
      restart.start()
    }
  }

  Timer {
    id: restart
    interval: 5000
    onTriggered: sampler.running = true
  }

  // Filesystem sizes move slowly: read them now and then, and whenever a
  // disk panel opens.
  Process {
    id: dfProc
    command: ["df", "-P", "-B1", "-T"]
    environment: ({ LC_ALL: "C" })
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.filesystems = Model.parseDf(text)
        root.filesystem = Model.primaryFilesystem(root.filesystems)
      }
    }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.refreshFilesystems()
  }

  Process {
    id: diskTempProc
    command: ["bash", root.pluginDir + "/sample.sh", "--disk-temps"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.diskTemps = Model.parseTemps(text.split("\n")).disks
    }
  }

  // top's first frame measures since boot, so each run takes two a second
  // apart and the second is the one that is read.
  Process {
    id: topProc
    command: ["top", "-b", "-n", "2", "-d", "1", "-w", "200"]
    environment: ({ LC_ALL: "C" })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rows = Model.parseTop(text)
        root.topByCpu = Model.topProcesses(rows, "cpu", 5)
        root.topByMemory = Model.topProcesses(rows, "memory", 5)
      }
    }
  }

  Timer {
    interval: 3000
    running: root.processWatchers > 0
    repeat: true
    onTriggered: if (!topProc.running) topProc.running = true
  }
}
