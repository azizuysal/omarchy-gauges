// Runs sample.sh against made-up machines, for hardware nobody here owns.
// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")
const Model = require("../Model.js")

const script = path.join(__dirname, "..", "sample.sh")

// Builds a fake /sys, /proc and /dev from { "relative/path": "contents" }.
// A value of { link: target } makes a symlink.
function machine(files) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "gauges-"))
  const base = {
    "proc/uptime": "100.00 400.00\n",
    "proc/stat": "cpu  10 0 10 80 0 0 0 0 0 0\ncpu0 10 0 10 80 0 0 0 0 0 0\n",
    "proc/loadavg": "0.10 0.20 0.30 1/100 999\n",
    "proc/meminfo": "MemTotal: 8000000 kB\nMemFree: 4000000 kB\nMemAvailable: 6000000 kB\n",
    "proc/diskstats": "",
    "proc/cpuinfo": "processor\t: 0\nCPU implementer\t: 0x61\n"
  }
  for (const [name, content] of Object.entries({ ...base, ...files })) {
    const target = path.join(root, name)
    fs.mkdirSync(path.dirname(target), { recursive: true })
    if (typeof content === "object") fs.symlinkSync(content.link, target)
    else fs.writeFileSync(target, content)
  }
  return root
}

function sample(root) {
  const out = execFileSync("bash", [script, "--once"], { env: { ...process.env, GAUGES_ROOT: root }, encoding: "utf8" })
  fs.rmSync(root, { recursive: true, force: true })
  const blocks = []
  let lines = []
  for (const line of out.split("\n")) {
    if (line === "@@end") { blocks.push(Model.parseBlock(lines)); lines = [] }
    else lines.push(line)
  }
  return {
    static: blocks.find(block => block.kind === "static"),
    frame: blocks.find(block => block.kind === "frame")
  }
}

// One program holding a handle on a card: its open file and what it reports.
function client(pid, fd, node, report) {
  return {
    [`dev/dri/${node}`]: { link: "/dev/null" },
    [`proc/${pid}/fd/${fd}`]: { link: "/dev/null" },
    [`proc/${pid}/fdinfo/${fd}`]: report
  }
}

test("Apple Silicon: machine name for the processor, no temperature, GPU without load", () => {
  const { static: info, frame } = sample(machine({
    "proc/device-tree/model": "Apple MacBook Air (M1, 2020)\0",
    // The display controller: a card that cannot render.
    "sys/class/drm/card0/device/uevent": "DRIVER=apple-drm\n",
    "sys/class/drm/card0/device/drm/card0/dev": "226:0\n",
    // The GPU proper.
    "sys/class/drm/card1/device/uevent": "DRIVER=asahi\nOF_COMPATIBLE_0=apple,agx-t8103\n",
    "sys/class/drm/card1/device/drm/card1/dev": "226:1\n",
    "sys/class/drm/card1/device/drm/renderD128/dev": "226:128\n",
    // The sensors Apple Silicon does have; none is the processor's.
    "sys/class/hwmon/hwmon0/name": "macsmc_hwmon\n",
    "sys/class/hwmon/hwmon0/temp1_label": "NAND Flash Temperature\n",
    "sys/class/hwmon/hwmon0/temp1_input": "35000\n",
    "sys/class/hwmon/hwmon0/temp2_label": "Battery Hotspot\n",
    "sys/class/hwmon/hwmon0/temp2_input": "30000\n",
    // A client, but the driver reports nothing about its usage.
    ...client(321, 9, "renderD128", "drm-driver:\tasahi\ndrm-client-id:\t4\n")
  }))
  const parsed = Model.parseStatic(info.sections)
  assert.equal(parsed.cpuModel, "Apple MacBook Air (M1, 2020)")
  assert.deepEqual(Object.keys(parsed.gpuNames), ["card1"])
  assert.equal(parsed.gpuNames.card1, "Apple GPU")
  assert.equal(Model.parseTemps(frame.sections.temps).cpu, null)

  const clients = Model.parseDrmClients(frame.sections.drmclients)
  const gpus = Model.parseGpus(frame.sections.gpus, parsed.gpuNames, [], Model.drmLoad(clients, clients, 2))
  assert.equal(gpus.length, 1)
  assert.equal(Model.gpuAvailable(gpus), false)
})

test("Qualcomm: hottest core sensor, GPU load from what programs report", () => {
  const { static: info, frame } = sample(machine({
    "proc/device-tree/model": "Lenovo Yoga Slim 7x\0",
    "sys/class/drm/card0/device/uevent": "DRIVER=msm_dpu\n",
    "sys/class/drm/card0/device/drm/card0/dev": "226:0\n",
    "sys/class/drm/card0/device/drm/renderD128/dev": "226:128\n",
    "sys/class/thermal/thermal_zone0/type": "cpu0-0-top-thermal\n",
    "sys/class/thermal/thermal_zone0/temp": "48000\n",
    "sys/class/thermal/thermal_zone1/type": "cpu1-0-top-thermal\n",
    "sys/class/thermal/thermal_zone1/temp": "61000\n",
    "sys/class/thermal/thermal_zone2/type": "gpuss-0-thermal\n",
    "sys/class/thermal/thermal_zone2/temp": "90000\n",
    ...client(500, 12, "renderD128",
      "drm-driver:\tmsm\ndrm-client-id:\t8\ndrm-engine-gpu:\t3000000000 ns\ndrm-cycles-gpu:\t123456\ndrm-maxfreq-gpu:\t1250000000 Hz\n"),
    // The same client, inherited by a second process.
    "proc/501/fd/3": { link: "/dev/null" },
    "proc/501/fdinfo/3": "drm-driver:\tmsm\ndrm-client-id:\t8\ndrm-engine-gpu:\t3000000000 ns\n"
  }))
  const parsed = Model.parseStatic(info.sections)
  assert.equal(parsed.cpuModel, "Lenovo Yoga Slim 7x")
  assert.equal(parsed.gpuNames.card0, "Qualcomm Adreno")
  assert.equal(Model.parseTemps(frame.sections.temps).cpu, 61)

  assert.equal(frame.sections.drmclients.filter(line => line.startsWith("@ ")).length, 1)
  const now = Model.parseDrmClients(frame.sections.drmclients)
  const earlier = Model.parseDrmClients(["@ card0", "drm-client-id: 8", "drm-engine-gpu: 2000000000 ns"])
  const gpus = Model.parseGpus(frame.sections.gpus, parsed.gpuNames, [], Model.drmLoad(earlier, now, 2))
  assert.equal(gpus[0].busy, 0.5)
  assert.equal(Model.gpuAvailable(gpus), true)
})

test("virtual machine: no sensors, no card, nothing breaks", () => {
  const { static: info, frame } = sample(machine({
    "proc/cpuinfo": "processor\t: 0\nmodel name\t: Intel(R) Celeron(R) N5105 @ 2.00GHz\n",
    // A boot framebuffer: a card with no render node.
    "sys/class/drm/card0/device/uevent": "DRIVER=simple-framebuffer\n",
    "sys/class/drm/card0/device/drm/card0/dev": "226:0\n"
  }))
  const parsed = Model.parseStatic(info.sections)
  assert.equal(parsed.cpuModel, "Intel Celeron N5105")
  assert.deepEqual({ ...parsed.gpuNames }, {})
  assert.equal(Model.parseTemps(frame.sections.temps).cpu, null)
  assert.deepEqual(frame.sections.gpus, [])
  assert.equal(frame.sections.drmclients, undefined)
  assert.equal(Model.parseCpuTimes(frame.sections.stat).cores.length, 1)
})

test("Intel laptop: package temperature, card measured through its programs", () => {
  const { frame } = sample(machine({
    "sys/class/hwmon/hwmon1/name": "coretemp\n",
    "sys/class/hwmon/hwmon1/temp1_label": "Package id 0\n",
    "sys/class/hwmon/hwmon1/temp1_input": "55000\n",
    "sys/class/hwmon/hwmon1/temp2_label": "Core 0\n",
    "sys/class/hwmon/hwmon1/temp2_input": "70000\n",
    "sys/class/drm/card1/device/vendor": "0x8086\n",
    "sys/class/drm/card1/device/uevent": "DRIVER=i915\nPCI_SLOT_NAME=0000:00:02.0\n",
    "sys/class/drm/card1/device/drm/card1/gt_cur_freq_mhz": "600\n",
    "sys/class/drm/card1/device/drm/card1/gt_max_freq_mhz": "1250\n",
    "sys/class/drm/card1/device/drm/renderD128/dev": "226:128\n",
    ...client(77, 4, "renderD128", "drm-driver:\ti915\ndrm-client-id:\t34\ndrm-engine-render:\t500 ns\n")
  }))
  assert.equal(Model.parseTemps(frame.sections.temps).cpu, 55)
  assert.deepEqual(frame.sections.gpus, ["card1|0x8086|awake||||||600|1250"])
  assert.deepEqual(frame.sections.drmclients, ["@ card1", "drm-client-id:\t34", "drm-engine-render:\t500 ns"])
})

test("T2 Mac: the security chip's network link is not counted as a connection", () => {
  const counters = " 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0"
  const { frame } = sample(machine({
    "proc/net/dev": `Inter-|   Receive\n face |bytes\nenp4s0f1u1:${counters}\nenp5s0u2:${counters}\n wlp5s0:${counters}\n`,
    "sys/class/net/enp4s0f1u1/operstate": "up\n",
    "sys/class/net/enp4s0f1u1/device/uevent": "DRIVER=cdc_ncm\n",
    "sys/class/net/enp4s0f1u1/idVendor": "05ac\n",
    "sys/class/net/enp4s0f1u1/idProduct": "8233\n",
    "sys/class/net/enp5s0u2/operstate": "up\n",
    "sys/class/net/enp5s0u2/device/uevent": "DRIVER=cdc_ncm\n",
    "sys/class/net/enp5s0u2/idVendor": "0bda\n",
    "sys/class/net/enp5s0u2/idProduct": "8156\n",
    "sys/class/net/wlp5s0/operstate": "up\n",
    "sys/class/net/wlp5s0/device/uevent": "DRIVER=brcmfmac\n",
    "sys/class/net/wlp5s0/phy80211/index": "0\n"
  }))
  const net = Model.parseNet(frame.sections.net)
  assert.equal(net.enp4s0f1u1.physical, false)
  assert.equal(net.enp5s0u2.physical, true)
  assert.equal(net.wlp5s0.physical, true)
  assert.deepEqual(Model.netRates(null, net, 2).interfaces.map(entry => entry.name), ["enp5s0u2", "wlp5s0"])
})

function processes(mode, root) {
  const out = execFileSync("bash", [path.join(__dirname, "..", "processes.sh"), mode], { env: { ...process.env, GAUGES_ROOT: root }, encoding: "utf8" })
  fs.rmSync(root, { recursive: true, force: true })
  return out
}

test("processes.sh --disk lists what each readable process has read and written", () => {
  const out = processes("--disk", machine({
    "proc/10/io": "rchar: 5\nwchar: 6\nread_bytes: 4096\nwrite_bytes: 8192\ncancelled_write_bytes: 0\n",
    "proc/10/comm": "browser\n",
    "proc/11/comm": "no-io-file\n",
    "proc/12/io": "rchar: 5\n",
    "proc/12/comm": "partial\n"
  }))
  assert.equal(out, "10 4096 8192 browser\n")
})

test("processes.sh --gpu names the holder of each client and skips sleeping cards", () => {
  const out = processes("--gpu", machine({
    "sys/class/drm/card1/device/drm/renderD128/dev": "226:128\n",
    "sys/class/drm/card1-eDP-1/status": "connected\n",
    "sys/class/drm/card2/device/power/runtime_status": "suspended\n",
    "sys/class/drm/card2/device/drm/renderD129/dev": "226:129\n",
    "dev/dri/renderD129": { link: "/dev/zero" },
    "proc/88/fd/3": { link: "/dev/zero" },
    "proc/88/fdinfo/3": "drm-client-id:\t9\ndrm-engine-gfx:\t5 ns\n",
    "proc/88/comm": "sleeper\n",
    "proc/77/comm": "player\n",
    "proc/78/fd/9": { link: "/dev/null" },
    "proc/78/fdinfo/9": "drm-client-id:\t34\ndrm-engine-render:\t500 ns\n",
    "proc/78/comm": "second-holder\n",
    ...client(77, 4, "renderD128", "pos:\t0\ndrm-driver:\ti915\ndrm-client-id:\t34\ndrm-engine-render:\t500 ns\n")
  }))
  assert.equal(out, "@ card1\ndrm-client-id:\t34\ndrm-engine-render:\t500 ns\ngauges-pid: 77\ngauges-name: player\n")
})
