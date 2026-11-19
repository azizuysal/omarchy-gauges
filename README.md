# Gauges for Omarchy

CPU, memory, GPU, disk and network readings in the Omarchy bar. Each one opens a detail
panel in the style of Omarchy's own battery and display panels, and follows
whatever theme is active.

![The five gauges in the Omarchy bar](screenshots/bar.png)

Each reading can be drawn as a graph, a gauge, a pie, a number or an icon:

![Two other mixes of styles](screenshots/styles.png)

- **CPU**: load, two minutes of history, per-core bars, temperature, load
  average, uptime, and the programs using the most processor.
- **Memory**: used and cached memory, swap, and the programs holding
  the most memory.
- **GPU**: load for each card, with video memory, temperature and power
  where the card reports them, and the processes using the graphics most.
- **Disk**: space on each volume, read and write activity, drive
  temperature, and the processes reading and writing most.
- **Network**: download and upload speed, history, the programs using the
  network most, and each interface's speed, traffic since startup and
  address (IPv6 too, if you turn it on). Optionally the address the internet sees you at, with its
  country's flag. Click an address to copy it.

Requires Omarchy 4.5 or later.

## Install

```bash
omarchy plugin add https://github.com/azizuysal/omarchy-gauges.git --enable
```

Update with `omarchy plugin update azizuysal.gauges`, remove with
`omarchy plugin remove azizuysal.gauges`.

## Use

| Action | Result |
|---|---|
| Click a reading | Open its panel; click again to close |
| Right-click | Open btop |
| Left / Right in a panel | Step through the readings |
| Tab | Move to the next bar panel |
| Esc | Close |

Drag the widget along the bar to move it, or use `omarchy bar move azizuysal.gauges --section right`.

### Settings

Set these in the shell's settings panel, or with
`omarchy bar set azizuysal.gauges <key> <value>`. They are stored with the
rest of the bar layout in `~/.config/omarchy/shell.json`.

| Key | Default | Meaning |
|---|---|---|
| `cpu` | `Graph` | How processor load is shown |
| `memory` | `Gauge` | How memory in use is shown |
| `gpu` | `Graph` | How graphics load is shown |
| `disk` | `Pie` | How space on the system disk is shown |
| `network` | `Graph` | How network traffic is shown: `Graph`, `Rates`, `Icon` or `Off` |
| `showPercentage` | `false` | Put the number beside graphs, gauges and pies |
| `showIPv6` | `false` | List each connection's IPv6 address under its IPv4 one in the network panel |
| `showPublicAddress` | `false` | Show your public address and its country's flag in the network panel |
| `warnAt` | `90` | Memory and disk turn the warning colour when this full (%) |

CPU, memory, GPU and disk each take one of these styles:

| Style | What it draws |
|---|---|
| `Graph` | The last ten readings as a bar graph. For disk this is read and write activity, since free space hardly moves. |
| `Gauge` | An upright gauge filling from the bottom. Memory's shows cache as a fainter band. |
| `Pie` | A pie of the current level |
| `Percentage` | The number alone |
| `Icon` | The icon alone |
| `Icon and percentage` | Both |
| `Off` | Leaves the reading out of the bar |

The network has speeds, not a level, so its styles are its own: `Graph`
draws recent upload above a middle line and download below it, both scaled
to the busiest moment in view; `Rates` shows the two speeds as numbers.

```bash
omarchy bar set azizuysal.gauges memory Graph
omarchy bar set azizuysal.gauges gpu Off
omarchy bar set azizuysal.gauges showPercentage true --json
```

Hovering a reading that shows no number gives its percentage. On a vertical
bar every reading is shown as its icon.

The widget can be added to the bar more than once, each copy with its own
settings, to place readings in different parts of the bar: turn the readings
a copy should not show to `Off`.

### Keybindings

`omarchy-shell gauges show <reading>` opens a panel directly, and
`omarchy-shell gauges toggle` toggles the last one. For example, in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER CTRL, M", "System monitor", "omarchy-shell gauges toggle")
```

## Naming every program on the network (optional)

Out of the box the network panel lists the TCP connections of your own
programs. To have it name every program, and count UDP too, install
[nethogs](https://github.com/raboof/nethogs):

```bash
sudo pacman -S nethogs
```

That is all the setup there is. Arch's package gives `nethogs` the
capabilities to capture packets without root, and gives them again on every
update. Know what that grants: afterwards any user on the machine can run
`nethogs` and see which programs are talking on the network. Remove it with
`sudo pacman -Rns nethogs`; the panel goes back to the shorter list.

The plugin's `nethogs-setup` script does the same install. It no longer
changes capabilities or adds pacman hooks.

**If you ran `nethogs-setup` from Gauges 1.0.0** (or any version before
1.1.0), run the new one once:

```bash
sudo ~/.config/omarchy/plugins/azizuysal.gauges/nethogs-setup
```

Those versions added a pacman hook, and later a note in `/var/lib/gauges`,
which turned out to duplicate what the package already does. The new script
removes them (only files it wrote itself) and leaves `nethogs` and its
capabilities as they are. `nethogs-setup --remove` does the same clean-up
without installing anything.

## What the bar shows

| Reading | By default | Value | Turns the warning colour |
|---|---|---|---|
| CPU | Graph | Share of processor time in use | Never |
| Memory | Gauge | Memory programs hold, not counting cache | At `warnAt` |
| GPU | Graph | Load of the busiest card that reports it | Never |
| Disk | Pie | Space used on the root filesystem | At `warnAt` |
| Network | Graph | Upload and download speed over the last minute | Never |

The GPU item is left out on a machine whose graphics report no load.

## Hardware support

CPU load, memory, disk and network come from `/proc` and work on any machine Omarchy
runs on, x86 or ARM, real or virtual. Temperature and graphics depend on what
the hardware's drivers publish:

| Machine | CPU temperature | GPU |
|---|---|---|
| Intel or AMD processor | Yes | See graphics below |
| Apple Silicon | No: the kernel exposes no processor sensor | No load figure, so no GPU item |
| Qualcomm Snapdragon | Hottest of the per-core sensors | Load |
| NVIDIA N1x, GB10 | If a processor thermal zone exists | Load, temperature and power through `nvidia-smi` |
| Virtual machine | No | Only with a virtual card that reports usage |

| Graphics | What is shown |
|---|---|
| AMD | Load, video memory, temperature, power |
| Intel (`i915`, `xe`) | Load and frequency |
| NVIDIA | Load, video memory, temperature, power, through `nvidia-smi` |
| Qualcomm Adreno, Arm Mali and other ARM graphics | Load, where the driver reports usage per program |
| Apple | Listed in the panel, without load |

**Tested on real hardware:** one Intel laptop with Intel and AMD graphics.
Everything else in these tables was written from kernel sources and is
exercised only by tests against made-up machines (`tests/sample.test.js`).
Reports from other hardware are very welcome.

- Where a driver gives no load figure for the card as a whole (Intel, and
  ARM graphics), the load is added up from the usage each program reports in
  `/proc/<pid>/fdinfo`. Only your own programs are visible, so graphics work
  done by another user's processes is not counted.
- The network panel's list of programs comes from
  [nethogs](https://github.com/raboof/nethogs) once it is installed (see
  above), and then covers every program and both TCP and UDP. Without it the
  list is limited to the TCP connections of your own programs, which misses
  UDP traffic such as video calls and much of a browser's. Either way it is
  read only while the network panel is open.
- Out of the box the plugin contacts nothing outside your machine. Turning
  on `showPublicAddress` adds the one exception: to learn the address the
  internet sees you at, it asks Cloudflare
  (`https://1.1.1.1/cdn-cgi/trace`, with `curl`) when the network panel is
  opened, at most once every ten minutes unless your connection changes.
  The reply's country code picks the flag, which makes it easy to see
  whether a VPN or exit node is in effect. Nothing is asked while the panel
  is closed or the setting is off.
- The disk and GPU panels' lists of processes cover your own programs: the
  kernel shows an ordinary user neither what another user's process reads
  and writes nor how it uses the graphics. They are read only while the
  panel is open. On NVIDIA the list comes from `nvidia-smi pmon`.
- Network speed counts interfaces with a real device behind them, so VPN
  and loopback traffic is not counted twice.
- A discrete card that is powered down is shown as asleep and left alone,
  since reading its sensors would wake it.
- On ARM the panel names the machine ("Apple MacBook Air (M1, 2020)") where
  x86 names the processor, as `/proc/cpuinfo` carries no model name there.
- Drive temperature comes from `nvme` or `drivetemp`, and is read only while
  the disk panel is open, and then every 30 seconds. Asking a drive for it
  continuously made the keyboard and trackpad stutter on an Apple T2 laptop,
  where they share a controller.

## How it works

`sample.sh` streams raw counters from `/proc` and `/sys` every two seconds
using only bash builtins, so a sample costs no process launches. `Service.qml`
runs it once for the whole shell, however many monitors show the bar, and
`Model.js` turns the counters into readings. The process list (`top`) only
runs while a CPU or memory panel is open, and drive temperature is only read
while the disk panel is open.

## Development

```bash
./dev-install --restart   # copy into ~/.config/omarchy/plugins and reload
./dev-install --remove    # take it out again
node --test tests/        # parsing, arithmetic, and made-up-machine tests
omarchy plugin validate . # manifest check
```

Translations live in `i18n/`, one JSON file per Omarchy language code;
anything missing falls back to `en.json`.

## License

MIT
