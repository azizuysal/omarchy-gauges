// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("parseBlock splits a frame into sections", () => {
  const block = Model.parseBlock(["@@frame 120.50", "@@section stat", "cpu 1 2", "@@section loadavg", "0.1 0.2 0.3 1/20 9"])
  assert.equal(block.kind, "frame")
  assert.equal(block.uptime, 120.5)
  assert.deepEqual(block.sections.stat, ["cpu 1 2"])
  assert.deepEqual(block.sections.loadavg, ["0.1 0.2 0.3 1/20 9"])
})

test("parseStatic reads the cpu model, block devices and gpu names", () => {
  const info = Model.parseStatic({
    cpuinfo: ["model name\t: Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz"],
    blocks: ["dm-0", "nvme0n1", "zram0"],
    gpunames: [
      "card1|0x8086|Intel Corporation CoffeeLake-H GT2 [UHD Graphics 630] (rev 02)",
      "card2|0x1002|Advanced Micro Devices, Inc. [AMD/ATI] Navi 12 [Radeon Pro 5600M/V520/BC-160] (rev 41)"
    ]
  })
  assert.equal(info.cpuModel, "Intel Core i9-9980HK")
  assert.deepEqual(info.blocks, ["dm-0", "nvme0n1", "zram0"])
  assert.equal(info.gpuNames.card1, "Intel UHD Graphics 630")
  assert.equal(info.gpuNames.card2, "AMD Radeon Pro 5600M")
})

test("cleanCpuModel trims AMD and Intel marketing noise", () => {
  assert.equal(Model.cleanCpuModel(" AMD Ryzen 7 7840U w/ Radeon 780M Graphics"), "AMD Ryzen 7 7840U w/ Radeon 780M Graphics")
  assert.equal(Model.cleanCpuModel("AMD Ryzen 9 5950X 16-Core Processor"), "AMD Ryzen 9 5950X")
  assert.equal(Model.cleanCpuModel("13th Gen Intel(R) Core(TM) i7-1360P"), "13th Gen Intel Core i7-1360P")
})

test("gpuName falls back when lspci gives nothing", () => {
  assert.equal(Model.gpuName("0x10de", ""), "NVIDIA")
  assert.equal(Model.gpuName("0xffff", ""), "GPU")
  assert.equal(Model.gpuName("0x10de", "NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile / Max-Q] (rev a1)"), "NVIDIA GeForce RTX 3060 Mobile")
})

test("cpuUsage measures the busy share between two readings", () => {
  const before = Model.parseCpuTimes(["cpu  100 0 100 800 0 0 0 0 0 0", "cpu0 50 0 50 400 0 0 0 0 0 0", "cpu1 50 0 50 400 0 0 0 0 0 0"])
  const after = Model.parseCpuTimes(["cpu  150 0 150 900 0 0 0 0 0 0", "cpu0 100 0 100 400 0 0 0 0 0 0", "cpu1 50 0 50 500 0 0 0 0 0 0"])
  const usage = Model.cpuUsage(before, after)
  assert.equal(usage.ready, true)
  assert.equal(usage.total, 0.5)
  assert.equal(usage.user, 0.25)
  assert.equal(usage.system, 0.25)
  assert.deepEqual(usage.cores, [1, 0])
})

test("cpuUsage is not ready without a previous reading or elapsed time", () => {
  const reading = Model.parseCpuTimes(["cpu  1 0 1 8 0 0 0 0 0 0"])
  assert.equal(Model.cpuUsage(null, reading).ready, false)
  assert.equal(Model.cpuUsage(reading, reading).ready, false)
})

test("iowait counts as idle", () => {
  const before = Model.parseCpuTimes(["cpu  0 0 0 0 0 0 0 0 0 0"])
  const after = Model.parseCpuTimes(["cpu  10 0 0 40 50 0 0 0 0 0"])
  assert.ok(Math.abs(Model.cpuUsage(before, after).total - 0.1) < 1e-9)
})

test("parseLoad reads the averages and the task count", () => {
  assert.deepEqual(Model.parseLoad(["2.69 2.27 1.93 1/2234 440979"]), { one: 2.69, five: 2.27, fifteen: 1.93, tasks: 2234 })
  assert.deepEqual(Model.parseLoad([]), { one: 0, five: 0, fifteen: 0, tasks: 0 })
})

test("parseMeminfo reports used as total minus available", () => {
  const mem = Model.parseMeminfo([
    "MemTotal:       65727180 kB",
    "MemFree:        35075236 kB",
    "MemAvailable:   48489556 kB",
    "Buffers:            4812 kB",
    "Cached:         20299900 kB",
    "SwapTotal:      131454276 kB",
    "SwapFree:       131454276 kB",
    "Shmem:           4175692 kB",
    "SReclaimable:     298080 kB"
  ])
  assert.equal(mem.total, 65727180 * 1024)
  assert.equal(mem.used, (65727180 - 48489556) * 1024)
  assert.equal(mem.swapUsed, 0)
  assert.equal(mem.swapFraction, 0)
  assert.ok(mem.fraction > 0.26 && mem.fraction < 0.27)
  // used + cache + free never exceeds the total.
  assert.ok(mem.used + mem.cache + mem.free <= mem.total)
})

test("parseMeminfo copes without MemAvailable and without swap", () => {
  const mem = Model.parseMeminfo(["MemTotal: 1000 kB", "MemFree: 200 kB", "Cached: 300 kB"])
  assert.equal(mem.available, 500 * 1024)
  assert.equal(mem.swapTotal, 0)
})

test("parseDiskstats keeps whole disks and drops partitions and virtual devices", () => {
  const lines = [
    " 259       0 nvme0n1 46663 35949 7875144 31420 707980 82502 34312512 390969 0 328940 716443",
    " 259       1 nvme0n1p1 97 3 7640 17 0 0 0 0 0 14 17",
    " 253       0 dm-0 80987 0 7497840 82899 790011 0 33975032 918402 0 335810 1003320",
    " 254       0 zram0 10 0 80 0 10 0 80 0 0 0 0",
    "   7       0 loop0 10 0 80 0 0 0 0 0 0 0 0"
  ]
  assert.deepEqual(Model.parseDiskstats(lines, ["dm-0", "nvme0n1", "zram0"]), { nvme0n1: { read: 7875144, written: 34312512 } })
  // Without the /sys/block list the partition suffix is the only clue.
  assert.deepEqual(Object.keys(Model.parseDiskstats(lines, [])), ["nvme0n1"])
})

test("diskRates converts sector deltas to bytes per second", () => {
  const rates = Model.diskRates({ sda: { read: 0, written: 0 } }, { sda: { read: 2048, written: 4096 } }, 2)
  assert.equal(rates.read, 2048 * 512 / 2)
  assert.equal(rates.write, 4096 * 512 / 2)
  assert.deepEqual(Model.diskRates(null, {}, 2), { read: 0, write: 0, disks: [] })
})

test("parseDf keeps one entry per device and skips pseudo filesystems", () => {
  const text = [
    "Filesystem               Type          1-blocks        Used     Available Capacity Mounted on",
    "dev                      devtmpfs   33483902976           0   33483902976       0% /dev",
    "/dev/mapper/omarchy_root btrfs    1999741386752 86652768256 1912946896896       5% /var/log",
    "/dev/mapper/omarchy_root btrfs    1999741386752 86652768256 1912946896896       5% /",
    "/dev/mapper/omarchy_root btrfs    1999741386752 86652768256 1912946896896       5% /home",
    "/dev/nvme0n1p3           vfat        2143166464   516976640    1626189824      25% /boot",
    "tmpfs                    tmpfs      33652318208   132562944   33519755264       1% /tmp",
    "/dev/sdb1                ext4        1000000000   500000000     500000000      50% /run/media/me/My Disk"
  ].join("\n")
  const filesystems = Model.parseDf(text)
  assert.deepEqual(filesystems.map(fs => fs.mount), ["/", "/boot", "/run/media/me/My Disk"])
  assert.equal(filesystems[2].fraction, 0.5)
  assert.equal(Model.primaryFilesystem(filesystems).mount, "/")
  assert.equal(Model.primaryFilesystem([]), null)
})

test("parseTemps converts millidegrees and drops nonsense", () => {
  assert.deepEqual(Model.parseTemps(["cpu 98000", "disk 39850", "disk ", "disk 999000"]), { cpu: 98, disks: [39.85] })
})

test("parseGpus reads awake and sleeping cards", () => {
  const names = { card1: "Intel UHD Graphics 630", card2: "AMD Radeon Pro 5600M" }
  const gpus = Model.parseGpus([
    "card1|0x8086|awake||||||1067|1250",
    "card2|0x1002|awake|58|253943808|8573157376|77000|14000000||"
  ], names, [])
  assert.equal(gpus[0].busy, null)
  assert.equal(gpus[0].freq, 1067)
  assert.equal(gpus[1].busy, 0.58)
  assert.equal(gpus[1].temp, 77)
  assert.equal(gpus[1].power, 14)
  assert.equal(gpus[1].vramTotal, 8573157376)
  assert.equal(Model.primaryGpu(gpus).id, "card2")

  const asleep = Model.parseGpus(["card2|0x1002|asleep"], names, [])
  assert.equal(asleep[0].asleep, true)
  assert.equal(Model.primaryGpu(asleep), null)
})

test("parseGpus fills NVIDIA cards from nvidia-smi", () => {
  const gpus = Model.parseGpus(["card0|0x10de|awake|||||||"], {}, ["0, GeForce RTX 4070, 37, 2048, 12282, 55, 86.40"])
  assert.equal(gpus.length, 1)
  assert.equal(gpus[0].name, "GeForce RTX 4070")
  assert.equal(gpus[0].busy, 0.37)
  assert.equal(gpus[0].vramUsed, 2048 * 1048576)
  assert.equal(gpus[0].temp, 55)
  assert.equal(gpus[0].power, 86.4)
})

test("parseTop reads the last frame and topProcesses groups by program", () => {
  const text = [
    "top - 10:00:00 up 1 day",
    "    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND",
    "      1 root      20   0   23456  12345   9876 S  99.0   0.0   0:01.00 stale",
    "",
    "top - 10:00:01 up 1 day",
    "    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND",
    "   4321 aziz      20   0   12.3g   1.5g 200000 S  40.0   2.3  10:00.00 chromium",
    "   4322 aziz      20   0   12.3g 512000 200000 S  10.0   0.7   1:00.00 chromium",
    "   9000 aziz      20   0    1.0g  50.0m  10000 R   5.0   0.1   0:10.00 Web Content",
    "      2 root      20   0       0      0      0 S   0.0   0.0   0:00.00 kthreadd"
  ].join("\n")
  const rows = Model.parseTop(text)
  assert.equal(rows.length, 4)
  assert.equal(rows[2].name, "Web Content")
  assert.equal(rows[2].memory, 50 * 1048576)

  const byCpu = Model.topProcesses(rows, "cpu", 5)
  assert.deepEqual(byCpu.map(p => [p.name, p.cpu, p.count]), [["chromium", 50, 2], ["Web Content", 5, 1]])
  const byMemory = Model.topProcesses(rows, "memory", 1)
  assert.equal(byMemory[0].name, "chromium")
  assert.equal(byMemory[0].memory, 1.5 * 1073741824 + 512000 * 1024)
})

test("bytesParts picks a unit and sensible precision", () => {
  assert.deepEqual(Model.bytesParts(0), { value: 0, decimals: 0, unit: "B" })
  assert.deepEqual(Model.bytesParts(1536), { value: 1.5, decimals: 2, unit: "KiB" })
  assert.equal(Model.bytesParts(64 * 1073741824).unit, "GiB")
  assert.equal(Model.bytesParts(64 * 1073741824).decimals, 1)
  // 1023.999 MiB rounds into the next unit rather than printing "1024 MiB".
  const edge = Model.bytesParts(1024 * 1048576 - 1)
  assert.equal(edge.unit, "GiB")
})

test("percent, durationParts, pushHistory and severity", () => {
  assert.equal(Model.percent(0.126), 13)
  assert.equal(Model.percent(7), 100)
  assert.deepEqual(Model.durationParts(93784), { days: 1, hours: 2, minutes: 3 })
  assert.deepEqual(Model.pushHistory([1, 2, 3], 4, 3), [2, 3, 4])
  assert.deepEqual(Model.pushHistory(null, 1, 3), [1])
  assert.equal(Model.severity(0.5, 0.7, 0.9), 0)
  assert.equal(Model.severity(0.75, 0.7, 0.9), 1)
  assert.equal(Model.severity(0.95, 0.7, 0.9), 2)
})

test("parseTemps keeps the hottest of several cpu sensors", () => {
  assert.equal(Model.parseTemps(["cpu 41000", "cpu 67500", "cpu 52000"]).cpu, 67.5)
})

test("gpuName names cards that are not on a PCI bus by their driver", () => {
  assert.equal(Model.gpuName("asahi", ""), "Apple GPU")
  assert.equal(Model.gpuName("msm_dpu", ""), "Qualcomm Adreno")
  assert.equal(Model.gpuName("adreno", ""), "Qualcomm Adreno")
  assert.equal(Model.gpuName("panthor", ""), "Arm Mali")
  assert.equal(Model.gpuName("some-new-driver", ""), "GPU")
})

test("drmLoad adds up what each program used on an i915 card", () => {
  const frame = (a, b, video) => Model.parseDrmClients([
    "@ card1", "drm-client-id:\t34", `drm-engine-render:\t${a} ns`, `drm-engine-video:\t${video} ns`, "drm-engine-capacity-video:\t2",
    // The same client again through a second handle: counted once.
    "@ card1", "drm-client-id:\t34", `drm-engine-render:\t${a} ns`, `drm-engine-video:\t${video} ns`,
    "@ card1", "drm-client-id:\t51", `drm-engine-render:\t${b} ns`, "drm-engine-video:\t0 ns"
  ])
  const before = frame(1e9, 5e9, 0)
  // Two seconds later: 0.4 s and 0.6 s of render, 0.8 s of video on two engines.
  const after = frame(1.4e9, 5.6e9, 0.8e9)
  assert.equal(Model.drmLoad(null, before, 2).card1, null)
  assert.ok(Math.abs(Model.drmLoad(before, after, 2).card1 - 0.5) < 1e-9)
})

test("drmLoad ignores a program first seen this frame and never goes negative", () => {
  const before = Model.parseDrmClients(["@ card0", "drm-client-id: 1", "drm-engine-gpu: 9000000000 ns"])
  const after = Model.parseDrmClients([
    "@ card0", "drm-client-id: 1", "drm-engine-gpu: 8000000000 ns",
    "@ card0", "drm-client-id: 2", "drm-engine-gpu: 70000000000 ns"
  ])
  assert.equal(Model.drmLoad(before, after, 2).card0, 0)
})

test("drmLoad reads the xe driver's cycle counters", () => {
  const frame = (cycles, total) => Model.parseDrmClients([
    "@ card0", "drm-client-id: 7", `drm-cycles-rcs: ${cycles}`, `drm-total-cycles-rcs: ${total}`
  ])
  assert.ok(Math.abs(Model.drmLoad(frame(1000, 100000), frame(26000, 200000), 2).card0 - 0.25) < 1e-9)
})

test("drmLoad is null for a driver that reports no usage", () => {
  const frame = Model.parseDrmClients(["@ card0", "drm-client-id: 3"])
  assert.equal(Model.drmLoad(frame, frame, 2).card0, null)
})

test("parseGpus takes program-reported load for cards with no figure", () => {
  const gpus = Model.parseGpus(["card1|0x8086|awake||||||1067|1250"], {}, [], { card1: 0.31 })
  assert.equal(gpus[0].busy, 0.31)
  assert.equal(Model.primaryGpu(gpus).id, "card1")
})

test("parseGpus copes with nvidia-smi fields that are not available", () => {
  const gpus = Model.parseGpus(["card0|nvidia-drm|awake|||||||"], {}, ["0, NVIDIA GB10, 96, [N/A], [N/A], 44, 31.53"])
  assert.equal(gpus.length, 1)
  assert.equal(gpus[0].busy, 0.96)
  assert.equal(gpus[0].vramUsed, null)
  assert.equal(gpus[0].vramTotal, null)
  assert.equal(gpus[0].temp, 44)
})

test("gpuAvailable is false when no card can report load", () => {
  assert.equal(Model.gpuAvailable([]), false)
  assert.equal(Model.gpuAvailable(Model.parseGpus(["card0|asahi|awake|||||||"], {}, [])), false)
  assert.equal(Model.gpuAvailable(Model.parseGpus(["card2|0x1002|asleep"], {}, [])), true)
  assert.equal(Model.gpuAvailable(Model.parseGpus(["card1|0x8086|awake|||||||"], {}, [], { card1: 0 })), true)
})

test("netRates counts real interfaces and leaves out loopback and VPNs", () => {
  const frame = (wifi, vpn) => Model.parseNet([
    "v unknown     lo:  377036    3976    0    0    0     0          0         0   377036    3976    0    0    0     0       0          0",
    `p up wlp5s0: ${wifi}  407227    0   10    0     0          0    101870 ${wifi / 2}  179454    0    0    0     0       0          0`,
    "p down enp69s0u1: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0",
    `v unknown tailscale0: ${vpn} 119 0 0 0 0 0 0 ${vpn} 206 0 0 0 0 0 0`
  ])
  assert.equal(Model.netRates(null, frame(1000, 500), 2).down, 0)
  const rates = Model.netRates(frame(1000000, 500), frame(1400000, 900000), 2)
  assert.equal(rates.down, 200000)
  assert.equal(rates.up, 100000)
  assert.deepEqual(rates.interfaces.map(entry => entry.name), ["enp69s0u1", "wlp5s0"])
  assert.equal(rates.interfaces[0].state, "down")
})

test("netRates falls back to every interface but loopback when none is real", () => {
  const frame = bytes => Model.parseNet(["v unknown lo: 5 0 0 0 0 0 0 0 5 0 0 0 0 0 0 0", `v up eth0: ${bytes} 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0`])
  assert.equal(Model.netRates(frame(0), frame(3000), 3).down, 1000)
})

test("rateCompact fits a rate in four characters", () => {
  assert.equal(Model.rateCompact(0), "0K")
  assert.equal(Model.rateCompact(89000), "87K")
  assert.equal(Model.rateCompact(1024 * 1024 * 1.25), "1.3M")
  assert.equal(Model.rateCompact(1024 * 1024 * 34), "34M")
  assert.equal(Model.rateCompact(1023 * 1024), "1.0M")
})
