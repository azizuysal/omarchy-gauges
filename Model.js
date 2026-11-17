// Pure parsing and arithmetic for the sysmon plugin. Nothing here touches QML,
// so the whole file runs under node for tests (see tests/model.test.js).

var SECTOR_BYTES = 512
// Who makes a card, by PCI vendor id or, for cards that are not on a PCI bus
// (every ARM system-on-chip), by the name of its kernel driver.
var VENDORS = {
  "0x1002": "AMD", "0x8086": "Intel", "0x10de": "NVIDIA",
  "0x1af4": "Virtual", "0x15ad": "VMware", "0x1234": "Virtual",
  "asahi": "Apple",
  "msm": "Qualcomm", "msm_dpu": "Qualcomm", "msm-mdss": "Qualcomm", "msm_mdp": "Qualcomm", "adreno": "Qualcomm",
  "nvidia": "NVIDIA", "nvidia-drm": "NVIDIA", "nvidia_drm": "NVIDIA",
  "panfrost": "Arm", "panthor": "Arm",
  "v3d": "Broadcom", "vc4": "Broadcom", "vc4-drm": "Broadcom",
  "virtio_gpu": "Virtual", "virtio-gpu": "Virtual", "virtio-pci": "Virtual"
}
// What to call a card when nothing gives it a model name.
var VENDOR_CARDS = {
  "Apple": "Apple GPU", "Qualcomm": "Qualcomm Adreno", "Arm": "Arm Mali",
  "Broadcom": "Broadcom VideoCore", "Virtual": "Virtual GPU"
}
// Filesystems that are not storage a person thinks of as a disk.
var PSEUDO_FILESYSTEMS = [
  "tmpfs", "devtmpfs", "efivarfs", "overlay", "squashfs", "ramfs", "proc", "sysfs",
  "cgroup", "cgroup2", "devpts", "securityfs", "debugfs", "tracefs", "configfs",
  "fusectl", "pstore", "bpf", "autofs", "mqueue", "hugetlbfs", "binfmt_misc",
  "nsfs", "fuse.portal", "fuse.gvfsd-fuse", "iso9660"
]

function num(value) {
  if (value === undefined || value === null || value === "") return null
  var n = Number(value)
  return isFinite(n) ? n : null
}

function clamp01(value) {
  if (!(value > 0)) return 0
  return value > 1 ? 1 : value
}

// ------------------------------------------------------------------ framing

// Splits the lines between a "@@static"/"@@frame" marker and its "@@end"
// into named sections.
function parseBlock(lines) {
  var block = { kind: "", uptime: 0, sections: {} }
  var current = null
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "@@static") { block.kind = "static"; continue }
    if (line.indexOf("@@frame") === 0) {
      block.kind = "frame"
      block.uptime = num(line.slice(8)) || 0
      continue
    }
    if (line.indexOf("@@section ") === 0) {
      current = line.slice(10).trim()
      block.sections[current] = []
      continue
    }
    if (current !== null) block.sections[current].push(line)
  }
  return block
}

function parseStatic(sections) {
  var info = { cpuModel: "", blocks: [], gpuNames: {} }
  var cpuinfo = sections.cpuinfo || []
  if (cpuinfo.length > 0) {
    var colon = cpuinfo[0].indexOf(":")
    info.cpuModel = cleanCpuModel(colon >= 0 ? cpuinfo[0].slice(colon + 1) : cpuinfo[0])
  }
  info.blocks = (sections.blocks || []).filter(function(name) { return name !== "" })
  var names = sections.gpunames || []
  for (var i = 0; i < names.length; i++) {
    var parts = names[i].split("|")
    if (parts.length < 2 || parts[0] === "") continue
    info.gpuNames[parts[0]] = gpuName(parts[1], parts.slice(2).join("|"))
  }
  return info
}

// "Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz" reads better as
// "Intel Core i9-9980HK".
function cleanCpuModel(raw) {
  return String(raw || "")
    .replace(/\((R|TM|r|tm)\)/g, "")
    .replace(/\s+CPU\b/, "")
    .replace(/\s+@.*$/, "")
    .replace(/\s+\d+-Core Processor\s*$/, "")
    .replace(/\s+Processor\s*$/, "")
    .replace(/\s+with Radeon.*$/, "")
    .replace(/\s+/g, " ")
    .trim()
}

// lspci describes a card as "Vendor Corp Codename [Marketing Name/Other] (rev xx)".
// The marketing name is the part worth showing.
function gpuName(vendorId, label) {
  var vendor = VENDORS[String(vendorId).toLowerCase()] || ""
  var text = String(label || "").replace(/\s*\(rev [0-9a-f]+\)\s*$/i, "")
  var brackets = text.match(/\[([^\]]+)\]/g)
  var model = ""
  if (brackets && brackets.length > 0) {
    model = brackets[brackets.length - 1].slice(1, -1).split("/")[0].trim()
    // "[AMD/ATI]" is the vendor again, not a model.
    if (/^(AMD|ATI|Intel|NVIDIA)$/i.test(model)) model = ""
  }
  if (model === "") {
    model = text.replace(/^.*(Corporation|Inc\.|Devices, Inc\.|Corp\.)\s*/i, "").replace(/\[[^\]]*\]/g, "").trim()
  }
  if (model === "") return VENDOR_CARDS[vendor] || vendor || "GPU"
  if (vendor !== "" && model.toLowerCase().indexOf(vendor.toLowerCase()) !== 0) return vendor + " " + model
  return model
}

// ---------------------------------------------------------------------- cpu

// Jiffy counters for the whole machine and each core.
function parseCpuTimes(lines) {
  var times = { total: null, cores: [] }
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].trim().split(/\s+/)
    if (fields.length < 5 || fields[0].indexOf("cpu") !== 0) continue
    var sum = 0
    // user nice system idle iowait irq softirq steal; guest time is already
    // counted inside user.
    for (var f = 1; f <= 8 && f < fields.length; f++) sum += Number(fields[f]) || 0
    var entry = {
      total: sum,
      idle: (Number(fields[4]) || 0) + (Number(fields[5]) || 0),
      user: (Number(fields[1]) || 0) + (Number(fields[2]) || 0),
      system: (Number(fields[3]) || 0) + (Number(fields[6]) || 0) + (Number(fields[7]) || 0)
    }
    if (fields[0] === "cpu") times.total = entry
    else times.cores.push(entry)
  }
  return times
}

function usageBetween(previous, current) {
  if (!previous || !current) return null
  var span = current.total - previous.total
  if (!(span > 0)) return null
  return {
    busy: clamp01(1 - (current.idle - previous.idle) / span),
    user: clamp01((current.user - previous.user) / span),
    system: clamp01((current.system - previous.system) / span)
  }
}

// Share of time spent busy between two readings, overall and per core.
function cpuUsage(previous, current) {
  var usage = { total: 0, user: 0, system: 0, cores: [], ready: false }
  if (!previous || !current) return usage
  var overall = usageBetween(previous.total, current.total)
  if (!overall) return usage
  usage.total = overall.busy
  usage.user = overall.user
  usage.system = overall.system
  usage.ready = true
  for (var i = 0; i < current.cores.length; i++) {
    var core = usageBetween(previous.cores[i], current.cores[i])
    usage.cores.push(core ? core.busy : 0)
  }
  return usage
}

function parseLoad(lines) {
  var fields = String(lines && lines[0] || "").trim().split(/\s+/)
  var tasks = String(fields[3] || "").split("/")
  return {
    one: num(fields[0]) || 0,
    five: num(fields[1]) || 0,
    fifteen: num(fields[2]) || 0,
    tasks: num(tasks[1]) || 0
  }
}

// ------------------------------------------------------------------- memory

function parseMeminfo(lines) {
  var kb = {}
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^(\w+):\s+(\d+)/)
    if (match) kb[match[1]] = Number(match[2]) * 1024
  }
  var total = kb.MemTotal || 0
  var free = kb.MemFree || 0
  // Older kernels have no MemAvailable; free plus cache is the usual stand-in.
  var cache = Math.max(0, (kb.Buffers || 0) + (kb.Cached || 0) + (kb.SReclaimable || 0) - (kb.Shmem || 0))
  var available = kb.MemAvailable !== undefined ? kb.MemAvailable : Math.min(total, free + cache)
  var used = Math.max(0, total - available)
  var swapTotal = kb.SwapTotal || 0
  var swapUsed = Math.max(0, swapTotal - (kb.SwapFree || 0))
  return {
    total: total,
    used: used,
    available: available,
    free: free,
    // Cache the kernel would give back; never more than what is not in use.
    cache: Math.max(0, Math.min(cache, total - used - free)),
    shared: kb.Shmem || 0,
    swapTotal: swapTotal,
    swapUsed: swapUsed,
    fraction: total > 0 ? clamp01(used / total) : 0,
    swapFraction: swapTotal > 0 ? clamp01(swapUsed / swapTotal) : 0
  }
}

// -------------------------------------------------------------------- disks

function isPhysicalDisk(name) {
  return !/^(loop|ram|zram|dm-|md|sr|fd|nbd)/.test(name)
}

// Whether a name looks like a partition: "nvme0n1p2", "mmcblk0p1", "sda3".
function looksLikePartition(name) {
  return /^(nvme|mmcblk)\w*p\d+$/.test(name) || /^(sd|vd|hd|xvd)[a-z]+\d+$/.test(name)
}

// Sector counters for whole disks. `blocks` is the list of /sys/block names,
// which is what tells a disk from one of its partitions.
function parseDiskstats(lines, blocks) {
  var known = {}
  var haveBlocks = blocks && blocks.length > 0
  for (var b = 0; haveBlocks && b < blocks.length; b++) known[blocks[b]] = true
  var disks = {}
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].trim().split(/\s+/)
    if (fields.length < 10) continue
    var name = fields[2]
    if (!isPhysicalDisk(name)) continue
    if (haveBlocks ? !known[name] : looksLikePartition(name)) continue
    disks[name] = { read: Number(fields[5]) || 0, written: Number(fields[9]) || 0 }
  }
  return disks
}

// Bytes per second read and written between two readings.
function diskRates(previous, current, seconds) {
  var rates = { read: 0, write: 0, disks: [] }
  if (!previous || !current || !(seconds > 0)) return rates
  var names = Object.keys(current).sort()
  for (var i = 0; i < names.length; i++) {
    var before = previous[names[i]]
    var after = current[names[i]]
    if (!before) continue
    var read = Math.max(0, after.read - before.read) * SECTOR_BYTES / seconds
    var write = Math.max(0, after.written - before.written) * SECTOR_BYTES / seconds
    rates.read += read
    rates.write += write
    rates.disks.push({ name: names[i], read: read, write: write })
  }
  return rates
}

// ------------------------------------------------------------------ network

// Byte counters per interface, from sample.sh's "net" section: each line is
// "<p|v> <link state> <wifi|wired> <line of /proc/net/dev>".
function parseNet(lines) {
  var interfaces = {}
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^([pv])\s+(\S+)\s+(wifi|wired)\s+([^:]+):\s*(.*)$/)
    if (!match) continue
    var fields = match[5].trim().split(/\s+/)
    if (fields.length < 9) continue
    var received = num(fields[0])
    var sent = num(fields[8])
    if (received === null || sent === null) continue
    interfaces[match[4].trim()] = {
      physical: match[1] === "p",
      state: match[2],
      wireless: match[3] === "wifi",
      received: received,
      sent: sent
    }
  }
  return interfaces
}

// Bytes a second down and up, in total and per interface. Only interfaces
// with a real device behind them count toward the total: a VPN's traffic
// already went through one of those, and loopback never left the machine.
// A machine with no such interface (a container) counts everything but
// loopback instead.
function netRates(previous, current, seconds) {
  var rates = { down: 0, up: 0, interfaces: [] }
  if (!current) return rates
  var names = Object.keys(current).sort()
  var anyPhysical = names.some(function(name) { return current[name].physical })
  for (var i = 0; i < names.length; i++) {
    var name = names[i]
    var now = current[name]
    if (anyPhysical ? !now.physical : name === "lo") continue
    var then = previous ? previous[name] : null
    var down = 0
    var up = 0
    if (then && seconds > 0) {
      down = Math.max(0, now.received - then.received) / seconds
      up = Math.max(0, now.sent - then.sent) / seconds
    }
    rates.down += down
    rates.up += up
    rates.interfaces.push({
      name: name, state: now.state, wireless: now.wireless, down: down, up: up,
      received: now.received, sent: now.sent
    })
  }
  return rates
}

// Which programs the traffic belongs to, from `ss -tinpHO`: one line per TCP
// connection with the bytes it has carried and, for connections of the
// user's own programs, who holds it. That is all an unprivileged user can
// see: UDP (which includes QUIC, so much of a browser's traffic) carries no
// byte counts, and other users' connections carry no name.
//
// Returns { "<local> <remote>": { name, sent, received } }.
function parseSockets(text) {
  var sockets = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var owner = line.match(/users:\(\("([^"]*)"/)
    if (!owner) continue
    var fields = line.trim().split(/\s+/)
    if (fields.length < 5) continue
    var local = fields[3]
    var remote = fields[4]
    // Traffic to this machine itself never touches the network.
    if (/^(127\.|\[::1\]|\[::ffff:127\.)/.test(remote)) continue
    var sent = line.match(/\bbytes_acked:(\d+)/)
    var received = line.match(/\bbytes_received:(\d+)/)
    sockets[local + " " + remote] = {
      name: owner[1],
      sent: sent ? Number(sent[1]) : 0,
      received: received ? Number(received[1]) : 0
    }
  }
  return sockets
}

// Bytes a second down and up per program between two readings, busiest
// first. A connection opened since the last reading did all its work in
// between, so all of it counts.
function socketRates(previous, current, seconds, limit) {
  if (!previous || !current || !(seconds > 0)) return []
  var programs = {}
  for (var key in current) {
    var now = current[key]
    var then = previous[key]
    var down = Math.max(0, now.received - (then ? then.received : 0))
    var up = Math.max(0, now.sent - (then ? then.sent : 0))
    if (down === 0 && up === 0) continue
    if (!programs[now.name]) programs[now.name] = { name: now.name, down: 0, up: 0 }
    programs[now.name].down += down / seconds
    programs[now.name].up += up / seconds
  }
  var rows = Object.keys(programs).map(function(name) { return programs[name] })
  rows.sort(function(a, b) { return (b.down + b.up) - (a.down + a.up) || (a.name < b.name ? -1 : 1) })
  return limit > 0 ? rows.slice(0, limit) : rows
}

// The same list from nethogs, where it is installed and allowed to capture
// packets: it sees every program's traffic, UDP included. Its trace mode
// prints, per refresh, lines of
//   "<command line>/<pid>/<uid>\t<sent kB/s>\t<received kB/s>"
// and two catch-all lines, "unknown TCP/0/0" and "unknown UDP/0/0", for
// packets it could not tie to a program.
function parseNethogs(lines, limit) {
  var programs = {}
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].split("\t")
    if (fields.length < 3) continue
    var up = num(fields[fields.length - 2])
    var down = num(fields[fields.length - 1])
    var owner = fields.slice(0, fields.length - 2).join("\t").match(/^(.*)\/(\d+)\/(\d+)$/)
    if (!owner || up === null || down === null) continue
    if (up <= 0 && down <= 0) continue
    var unknown = owner[2] === "0" && /^unknown (TCP|UDP)$/.test(owner[1])
    // The program is the first word of the command line, without its folder.
    var name = unknown ? owner[1] : owner[1].split(/\s+/)[0].replace(/^.*\//, "")
    if (name === "") continue
    if (!programs[name]) programs[name] = { name: name, down: 0, up: 0, unknown: unknown }
    programs[name].down += down * 1024
    programs[name].up += up * 1024
  }
  var rows = Object.keys(programs).map(function(name) { return programs[name] })
  rows.sort(function(a, b) { return (b.down + b.up) - (a.down + a.up) || (a.name < b.name ? -1 : 1) })
  return limit > 0 ? rows.slice(0, limit) : rows
}

// A rate in at most four characters, for the bar: "0K", "87K", "1.2M", "34M".
function rateCompact(bytesPerSecond) {
  var value = Math.max(0, bytesPerSecond || 0) / 1024
  var units = ["K", "M", "G", "T"]
  var unit = 0
  while (value >= 999.5 && unit < units.length - 1) { value /= 1024; unit++ }
  var text = value < 9.95 && unit > 0 ? value.toFixed(1) : String(Math.round(value))
  return text + units[unit]
}

// `df -P -B1 -T` output as one entry per real device. A btrfs device mounted
// several times over (subvolumes) is one disk, shown at its shortest mount.
function parseDf(text) {
  var lines = String(text || "").split("\n")
  var byDevice = {}
  for (var i = 1; i < lines.length; i++) {
    var fields = lines[i].trim().split(/\s+/)
    if (fields.length < 7) continue
    var type = fields[1]
    var mount = fields.slice(6).join(" ")
    if (PSEUDO_FILESYSTEMS.indexOf(type) !== -1) continue
    if (fields[0].indexOf("/") !== 0 && type.indexOf("fuse") !== 0 && type !== "zfs") continue
    var total = Number(fields[2]) || 0
    if (!(total > 0)) continue
    var used = Number(fields[3]) || 0
    var available = Number(fields[4]) || 0
    var entry = {
      device: fields[0],
      type: type,
      mount: mount,
      total: total,
      used: used,
      available: available,
      // What df calls capacity: used out of what an ordinary user can reach.
      fraction: used + available > 0 ? clamp01(used / (used + available)) : 0
    }
    var existing = byDevice[entry.device]
    if (!existing || mount.length < existing.mount.length) byDevice[entry.device] = entry
  }
  return Object.keys(byDevice).map(function(key) { return byDevice[key] }).sort(function(a, b) {
    if (a.mount === "/") return -1
    if (b.mount === "/") return 1
    return a.mount < b.mount ? -1 : a.mount > b.mount ? 1 : 0
  })
}

// The filesystem the bar item speaks for: the root one, or the first.
function primaryFilesystem(filesystems) {
  for (var i = 0; i < filesystems.length; i++) if (filesystems[i].mount === "/") return filesystems[i]
  return filesystems.length > 0 ? filesystems[0] : null
}

// ------------------------------------------------------------- temperatures

function parseTemps(lines) {
  var temps = { cpu: null, disks: [] }
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].trim().split(/\s+/)
    var value = num(fields[1])
    if (value === null) continue
    // sysfs reports millidegrees.
    var celsius = value / 1000
    if (celsius <= -40 || celsius > 150) continue
    // A machine with a sensor per core sends them all; the hottest is the one
    // worth showing.
    if (fields[0] === "cpu") temps.cpu = temps.cpu === null ? celsius : Math.max(temps.cpu, celsius)
    else if (fields[0] === "disk") temps.disks.push(celsius)
  }
  return temps
}

// --------------------------------------------------------------------- gpus

// Cards with no load figure of their own are measured by what each program
// reports having used: lines from /proc/<pid>/fdinfo, grouped under an
// "@ <card>" marker per program (Documentation/gpu/drm-usage-stats.rst).
//
// Returns { card: { clientId: { engine: {...}, cycles: {...}, total: {...},
// capacity: {...} } } }, each keyed by engine name.
function parseDrmClients(lines) {
  var cards = {}
  var card = null
  var client = null
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("@ ") === 0) {
      card = line.slice(2).trim()
      client = null
      if (!cards[card]) cards[card] = {}
      continue
    }
    if (card === null) continue
    var match = line.match(/^(drm-[a-z0-9-]+):\s*(\d+)/)
    if (!match) continue
    var key = match[1]
    var value = Number(match[2])
    if (key === "drm-client-id") {
      // A program can hold several handles on the same client, and several
      // programs can share one; they all report the same counters.
      if (!cards[card][value]) cards[card][value] = { engine: {}, cycles: {}, total: {}, capacity: {} }
      client = cards[card][value]
      continue
    }
    if (client === null) continue
    var kind = null
    var name = ""
    if (key.indexOf("drm-engine-capacity-") === 0) { kind = "capacity"; name = key.slice(20) }
    else if (key.indexOf("drm-engine-") === 0) { kind = "engine"; name = key.slice(11) }
    else if (key.indexOf("drm-total-cycles-") === 0) { kind = "total"; name = key.slice(17) }
    else if (key.indexOf("drm-cycles-") === 0) { kind = "cycles"; name = key.slice(11) }
    if (kind === null || name === "") continue
    // Counters can briefly read lower than before; keep the larger.
    if (!(client[kind][name] >= value)) client[kind][name] = value
  }
  return cards
}

// Each card's load between two readings, 0 to 1, or null where it cannot be
// told (first reading, or a driver that reports no usage). A card is as busy
// as its busiest engine: the 3D engine sitting idle while video decodes is
// still a busy card.
function drmLoad(previous, current, seconds) {
  var load = {}
  for (var card in current) {
    load[card] = null
    var before = previous ? previous[card] : null
    if (!before || !(seconds > 0)) continue
    var spent = {}     // engine -> nanoseconds used, all programs together
    var cycles = {}    // engine -> cycles used, all programs together
    var elapsed = {}   // engine -> cycles the engine's clock advanced
    var capacity = {}
    for (var id in current[card]) {
      var now = current[card][id]
      var then = before[id]
      var name
      for (name in now.capacity) capacity[name] = Math.max(capacity[name] || 1, now.capacity[name])
      // A program first seen now has no earlier reading to compare with.
      if (!then) continue
      for (name in now.engine) {
        if (then.engine[name] === undefined) continue
        spent[name] = (spent[name] || 0) + Math.max(0, now.engine[name] - then.engine[name])
      }
      for (name in now.total) {
        if (then.total[name] === undefined || then.cycles[name] === undefined || now.cycles[name] === undefined) continue
        cycles[name] = (cycles[name] || 0) + Math.max(0, now.cycles[name] - then.cycles[name])
        elapsed[name] = Math.max(elapsed[name] || 0, now.total[name] - then.total[name])
      }
    }
    var busiest = null
    var engine
    for (engine in spent) {
      var share = spent[engine] / (seconds * 1e9 * (capacity[engine] || 1))
      if (busiest === null || share > busiest) busiest = share
    }
    for (engine in cycles) {
      if (!(elapsed[engine] > 0)) continue
      var part = cycles[engine] / (elapsed[engine] * (capacity[engine] || 1))
      if (busiest === null || part > busiest) busiest = part
    }
    load[card] = busiest === null ? null : clamp01(busiest)
  }
  return load
}

// `clientLoad` is drmLoad's result, used for cards that give no figure.
function parseGpus(lines, names, nvidiaLines, clientLoad) {
  var gpus = []
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("|")
    if (f.length < 3 || f[0] === "") continue
    var vendorId = String(f[1]).toLowerCase()
    var busy = num(f[3])
    if (busy === null && clientLoad && typeof clientLoad[f[0]] === "number") busy = clientLoad[f[0]] * 100
    var temp = num(f[6])
    var power = num(f[7])
    var freq = num(f[8])
    var freqMax = num(f[9])
    gpus.push({
      id: f[0],
      vendor: VENDORS[vendorId] || "",
      name: (names && names[f[0]]) || VENDORS[vendorId] || "GPU",
      asleep: f[2] === "asleep",
      busy: busy === null ? null : clamp01(busy / 100),
      vramUsed: num(f[4]),
      vramTotal: num(f[5]),
      temp: temp === null ? null : temp / 1000,
      // hwmon reports microwatts.
      power: power === null ? null : power / 1000000,
      freq: freq,
      freqMax: freqMax
    })
  }

  // The proprietary NVIDIA driver publishes nothing in sysfs; nvidia-smi is
  // the only source, matched to NVIDIA cards in the order both list them.
  var nvidiaCards = gpus.filter(function(gpu) { return gpu.vendor === "NVIDIA" })
  var rows = nvidiaLines || []
  for (var n = 0; n < rows.length; n++) {
    var cols = rows[n].split(",").map(function(col) { return col.trim() })
    if (cols.length < 7) continue
    var target = nvidiaCards[n]
    if (!target) {
      target = { id: "nvidia" + cols[0], vendor: "NVIDIA", asleep: false, freq: null, freqMax: null }
      gpus.push(target)
    }
    if (target.asleep) continue
    var load = num(cols[2])
    var usedMb = num(cols[3])
    var totalMb = num(cols[4])
    target.name = cols[1] || target.name || "NVIDIA"
    target.busy = load === null ? null : clamp01(load / 100)
    target.vramUsed = usedMb === null ? null : usedMb * 1048576
    target.vramTotal = totalMb === null ? null : totalMb * 1048576
    target.temp = num(cols[5])
    target.power = num(cols[6])
  }
  return gpus
}

// The card the bar item speaks for: the busiest one that reports load.
function primaryGpu(gpus) {
  var best = null
  for (var i = 0; i < gpus.length; i++) {
    var gpu = gpus[i]
    if (gpu.asleep || gpu.busy === null) continue
    if (!best || gpu.busy > best.busy) best = gpu
  }
  return best
}

// Whether the bar has anything to show for graphics: some card that reports
// its load, or would if it were awake. A machine whose only card says
// nothing (Apple Silicon, a plain virtual machine) gets no GPU item.
function gpuAvailable(gpus) {
  for (var i = 0; i < gpus.length; i++) {
    if (gpus[i].asleep || gpus[i].busy !== null) return true
  }
  return false
}

// ---------------------------------------------------------------- processes

function parseSize(text) {
  var match = String(text || "").match(/^([0-9.]+)([kmgtp]?)$/i)
  if (!match) return 0
  var scale = { "": 1024, k: 1024, m: 1048576, g: 1073741824, t: 1099511627776, p: 1125899906842624 }
  return Number(match[1]) * scale[match[2].toLowerCase()]
}

// Rows of the last frame of `top -b`. The first frame of a run measures
// since boot rather than the last moment, so only the last one is used.
function parseTop(text) {
  var lines = String(text || "").split("\n")
  var header = -1
  for (var i = lines.length - 1; i >= 0; i--) {
    if (/^\s*PID\s+USER\b/.test(lines[i])) { header = i; break }
  }
  if (header < 0) return []
  var rows = []
  for (var r = header + 1; r < lines.length; r++) {
    var fields = lines[r].trim().split(/\s+/)
    if (fields.length < 12 || !/^\d+$/.test(fields[0])) continue
    rows.push({
      pid: Number(fields[0]),
      cpu: Number(fields[8]) || 0,
      memory: parseSize(fields[5]),
      name: fields.slice(11).join(" ")
    })
  }
  return rows
}

// Adds a program's processes together, the way a person counts "the browser"
// as one thing, and returns the heaviest by cpu or by memory.
function topProcesses(rows, key, limit) {
  var groups = {}
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var group = groups[row.name]
    if (!group) group = groups[row.name] = { name: row.name, cpu: 0, memory: 0, count: 0 }
    group.cpu += row.cpu
    group.memory += row.memory
    group.count += 1
  }
  var list = Object.keys(groups).map(function(name) { return groups[name] })
  list.sort(function(a, b) { return b[key] - a[key] || (a.name < b.name ? -1 : 1) })
  return list.slice(0, limit).filter(function(entry) { return entry[key] > 0 })
}

// --------------------------------------------------------------- formatting

// A byte count as a number and an IEC unit, e.g. { value: 62.7, decimals: 1, unit: "GiB" }.
function bytesParts(bytes) {
  var units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
  var value = Math.max(0, Number(bytes) || 0)
  var unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit++
  }
  var decimals = unit === 0 || value >= 100 ? 0 : value >= 10 ? 1 : 2
  // Rounding 1023.99 up must not print "1024 MiB".
  if (Number(value.toFixed(decimals)) >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit++
    decimals = 2
  }
  return { value: value, decimals: decimals, unit: units[unit] }
}

function percent(fraction) {
  return Math.round(clamp01(fraction) * 100)
}

// Uptime as its two largest units: { days, hours, minutes }, the caller
// picking which to print.
function durationParts(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  return {
    days: Math.floor(total / 86400),
    hours: Math.floor((total % 86400) / 3600),
    minutes: Math.floor((total % 3600) / 60)
  }
}

// A new history with `value` appended, kept to `limit` entries. A new array
// each time, so QML bindings on it re-evaluate.
function pushHistory(history, value, limit) {
  var next = (history || []).slice(-(limit - 1))
  next.push(value)
  return next
}

// A level from 0 (calm) to 2 (critical), for colouring a reading.
function severity(fraction, warn, critical) {
  if (fraction >= critical) return 2
  return fraction >= warn ? 1 : 0
}

if (typeof module !== "undefined") {
  module.exports = {
    parseBlock: parseBlock,
    parseStatic: parseStatic,
    cleanCpuModel: cleanCpuModel,
    gpuName: gpuName,
    parseCpuTimes: parseCpuTimes,
    cpuUsage: cpuUsage,
    parseLoad: parseLoad,
    parseMeminfo: parseMeminfo,
    parseDiskstats: parseDiskstats,
    diskRates: diskRates,
    parseNet: parseNet,
    netRates: netRates,
    rateCompact: rateCompact,
    parseNethogs: parseNethogs,
    parseSockets: parseSockets,
    socketRates: socketRates,
    parseDf: parseDf,
    primaryFilesystem: primaryFilesystem,
    parseTemps: parseTemps,
    parseGpus: parseGpus,
    primaryGpu: primaryGpu,
    parseDrmClients: parseDrmClients,
    drmLoad: drmLoad,
    gpuAvailable: gpuAvailable,
    parseTop: parseTop,
    topProcesses: topProcesses,
    bytesParts: bytesParts,
    percent: percent,
    durationParts: durationParts,
    pushHistory: pushHistory,
    severity: severity
  }
}
