# Sysmon for Omarchy

CPU, memory, GPU and disk readings in the Omarchy bar. Each one opens a detail
panel in the style of Omarchy's own battery and display panels, and follows
whatever theme is active.

- **CPU**: load, two minutes of history, per-core bars, temperature, load
  average, uptime, and the programs using the most processor.
- **Memory**: used and cached memory, history, swap, and the programs holding
  the most memory.
- **GPU**: load, video memory, temperature and power for each card.
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
| `showValues` | `true` | Show the percentage beside each icon |

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

| Reading | Value | Turns the warning colour |
|---|---|---|
| CPU | Share of processor time in use | Never |
| Memory | Memory programs hold, not counting cache | At 90% |
| GPU | Load of the busiest card that reports it | Never |
| Disk | Space used on the root filesystem | At 90% |

## Hardware support

- **AMD graphics**: load, video memory, temperature and power.
- **Intel graphics**: frequency only. The kernel publishes no load figure
  without elevated privileges.
- **NVIDIA graphics**: read through `nvidia-smi` when it is installed. This
  path has not been tested on real hardware yet; reports are welcome.
- A discrete card that is powered down is shown as asleep and left alone,
  since reading its sensors would wake it.
- CPU temperature comes from `coretemp`, `k10temp`, `zenpower` or a thermal
  zone; drive temperature from `nvme` or `drivetemp`.
- Drive temperature is read only while the disk panel is open, and then every
  30 seconds. Asking a drive for it continuously made the keyboard and
  trackpad stutter on an Apple T2 laptop, where they share a controller.

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
node --test tests/        # parsing and arithmetic tests
omarchy plugin validate . # manifest check
```

Translations live in `i18n/`, one JSON file per Omarchy language code;
anything missing falls back to `en.json`.

## License

MIT
