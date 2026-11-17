# Sysmon for Omarchy

CPU, memory, GPU and disk readings in the Omarchy bar. Each one opens a detail
panel in the style of Omarchy's own battery and display panels, and follows
whatever theme is active.

- **CPU**: load, two minutes of history, per-core bars, temperature, load
  average, uptime, and the programs using the most processor.
- **Memory**: used and cached memory, history, swap, and the programs holding
  the most memory.
- **GPU**: load for each card, with video memory, temperature and power
  where the card reports them.
- **Disk**: space on each volume, read and write activity, and drive
  temperature.

Requires Omarchy 4.5 or later.

## Install

```bash
omarchy plugin add https://github.com/OWNER/omarchy-sysmon.git --enable
```

Update with `omarchy plugin update azizuysal.sysmon`, remove with
`omarchy plugin remove azizuysal.sysmon`.

## Use

| Action | Result |
|---|---|
| Click a reading | Open its panel; click again to close |
| Right-click | Open btop |
| Left / Right in a panel | Step through the readings |
| Tab | Move to the next bar panel |
| Esc | Close |

Drag the widget along the bar to move it, or use `omarchy bar move azizuysal.sysmon --section right`.

### Settings

Set these with `omarchy bar set azizuysal.sysmon <key> <value>` or in the
shell's settings panel.

| Key | Default | Meaning |
|---|---|---|
| `items` | all | Which readings to show: any of `cpu`, `memory`, `gpu`, `disk` |
| `display` | `Graphs` | How readings are shown: `Graphs` (a history graph for CPU and GPU, an upright gauge for memory, a pie for disk), `Percentages` (icon and number), or `Icons` |

```bash
omarchy bar set azizuysal.sysmon items '["cpu","memory"]' --json
```

The widget can be added to the bar more than once, each copy with its own
`items`, to place readings in different parts of the bar.

### Keybindings

`omarchy-shell sysmon show <reading>` opens a panel directly, and
`omarchy-shell sysmon toggle` toggles the last one. For example, in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER CTRL, M", "System monitor", "omarchy-shell sysmon toggle")
```

## What the bar shows

| Reading | Drawn as | Value | Turns the warning colour |
|---|---|---|---|
| CPU | History graph | Share of processor time in use | Never |
| Memory | Upright gauge | Memory programs hold, with cache fainter above it | At 90% |
| GPU | History graph | Load of the busiest card that reports it | Never |
| Disk | Pie | Space used on the root filesystem | At 90% |

The GPU item is left out on a machine whose graphics report no load.

## Hardware support

CPU load, memory and disk come from `/proc` and work on any machine Omarchy
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
