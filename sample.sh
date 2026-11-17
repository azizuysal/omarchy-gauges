#!/bin/bash

# Streams raw system readings for the sysmon plugin, one frame per interval.
#
# Usage: sample.sh [interval-seconds]
#        sample.sh --disk-temps
#
# Everything on the hot path is a bash builtin, so a frame costs no forks
# (nvidia-smi excepted, on machines that have it). The script only gathers;
# all arithmetic lives in Model.js, where it can be tested.
#
# Output is line based. A frame looks like:
#
#   @@frame <uptime-seconds>
#   @@section <name>
#   ...raw lines...
#   @@end
#
# A "@@static" frame with facts that rarely change is sent first, and again
# if a graphics card appears or goes away.
#
# Drive temperatures are deliberately not part of the stream. Reading one
# sends the drive a command, and on some machines (Apple T2 laptops, where the
# drive shares a controller with the keyboard and trackpad) asking every
# couple of seconds makes input stutter. --disk-temps reads them once, for the
# disk panel to call while it is open.

if [[ ${1:-} == --disk-temps ]]; then
  for hwmon in /sys/class/hwmon/hwmon*; do
    [[ -r $hwmon/name && -r $hwmon/temp1_input ]] || continue
    read -r name <"$hwmon/name" || continue
    if [[ $name == nvme || $name == drivetemp ]]; then
      read -r value <"$hwmon/temp1_input" 2>/dev/null && echo "disk $value"
    fi
  done
  exit 0
fi

interval="${1:-2}"
[[ $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || interval=2

export LC_ALL=C

# A read that times out on a descriptor nobody writes to sleeps without
# spawning sleep(1) on every frame.
exec {idle_fd}<> <(:) 2>/dev/null || idle_fd=""
pause() {
  if [[ -n $idle_fd ]]; then
    read -r -t "$interval" -u "$idle_fd" _ || true
  else
    sleep "$interval"
  fi
}

# Prints a file's first line, or nothing when it cannot be read.
first_line() {
  local value=""
  [[ -r $1 ]] && read -r value <"$1" 2>/dev/null
  printf '%s' "$value"
}

# ---------------------------------------------------------------- discovery

cpu_temp_path=""
cpu_temp_fallback=""

for hwmon in /sys/class/hwmon/hwmon*; do
  [[ -d $hwmon ]] || continue
  name=$(first_line "$hwmon/name")
  case "$name" in
    coretemp | k10temp | zenpower | cpu_thermal | cpu-thermal)
      # Prefer the package or control reading over a single core's.
      for label in "$hwmon"/temp*_label; do
        [[ -r $label ]] || continue
        text=$(first_line "$label")
        case "$text" in
          "Package id 0" | Tctl | Tdie)
            cpu_temp_path="${label%_label}_input"
            break
            ;;
        esac
      done
      [[ -z $cpu_temp_path && -r $hwmon/temp1_input ]] && cpu_temp_path="$hwmon/temp1_input"
      ;;
  esac
done

if [[ -z $cpu_temp_path ]]; then
  for zone in /sys/class/thermal/thermal_zone*; do
    [[ -r $zone/type && -r $zone/temp ]] || continue
    case "$(first_line "$zone/type")" in
      x86_pkg_temp | cpu-thermal | cpu_thermal | soc_thermal | acpitz)
        cpu_temp_fallback="$zone/temp"
        [[ $(first_line "$zone/type") != acpitz ]] && break
        ;;
    esac
  done
  cpu_temp_path="$cpu_temp_fallback"
fi

# One entry per graphics card: "<card>|<device dir>|<vendor>|<hwmon dir>".
#
# Cards are looked for again whenever the set of them changes, not just once:
# the shell can start before a graphics driver has finished loading (a
# discrete card on a hybrid laptop routinely registers seconds later), and a
# card found late would otherwise stay missing until the next restart.
gpus=()
gpu_signature=""

# Everything the card list is built from, as one string. Globbing is a
# builtin, so checking it every frame costs no forks.
# The result is left in gpu_scan_result rather than printed, so reading it
# needs no subshell.
gpu_scan_result=""
gpu_scan() {
  local paths=(/sys/class/drm/card[0-9]*/device/vendor /sys/class/drm/card[0-9]*/device/hwmon/hwmon*)
  gpu_scan_result="${paths[*]}"
}

discover_gpus() {
  local card device gpu_hwmon candidate
  gpus=()
  for card in /sys/class/drm/card[0-9]*; do
    [[ ${card##*/} =~ ^card[0-9]+$ ]] || continue
    device="$card/device"
    [[ -r $device/vendor ]] || continue
    gpu_hwmon=""
    for candidate in "$device"/hwmon/hwmon*; do
      [[ -d $candidate ]] && gpu_hwmon="$candidate" && break
    done
    gpus+=("${card##*/}|$device|$(first_line "$device/vendor")|$gpu_hwmon")
  done
}

gpu_scan
gpu_signature="$gpu_scan_result"
discover_gpus

have_nvidia_smi=0
command -v nvidia-smi >/dev/null 2>&1 && have_nvidia_smi=1

# ------------------------------------------------------------------- static

emit_static() {
  echo "@@static"
  echo "@@section cpuinfo"
  if [[ -r /proc/cpuinfo ]]; then
    while IFS= read -r line; do
      if [[ $line == "model name"* || $line == "Hardware"* || $line == "Model"* ]]; then
        echo "$line"
        break
      fi
    done </proc/cpuinfo
  fi
  echo "@@section blocks"
  for block in /sys/block/*; do
    [[ -d $block ]] && echo "${block##*/}"
  done
  echo "@@section gpunames"
  for gpu in "${gpus[@]}"; do
    IFS='|' read -r card device vendor _ <<<"$gpu"
    slot=""
    if [[ -r $device/uevent ]]; then
      while IFS='=' read -r key value; do
        [[ $key == PCI_SLOT_NAME ]] && slot="$value"
      done <"$device/uevent"
    fi
    label=""
    if [[ -n $slot ]] && command -v lspci >/dev/null 2>&1; then
      label=$(lspci -s "$slot" 2>/dev/null | head -n 1)
      label="${label#*: }"
    fi
    echo "$card|$vendor|$label"
  done
  echo "@@end"
}

emit_static

# --------------------------------------------------------------------- loop

while :; do
  gpu_scan
  if [[ $gpu_scan_result != "$gpu_signature" ]]; then
    gpu_signature="$gpu_scan_result"
    discover_gpus
    emit_static || exit 0
  fi

  read -r uptime _ </proc/uptime || uptime=0
  echo "@@frame $uptime" || exit 0

  echo "@@section stat"
  while IFS= read -r line; do
    [[ $line == cpu* ]] && echo "$line"
  done </proc/stat

  echo "@@section loadavg"
  first_line /proc/loadavg
  echo

  echo "@@section meminfo"
  while IFS= read -r line; do
    case "$line" in
      MemTotal:* | MemFree:* | MemAvailable:* | Buffers:* | Cached:* | SReclaimable:* | Shmem:* | SwapTotal:* | SwapFree:*)
        echo "$line"
        ;;
    esac
  done </proc/meminfo

  echo "@@section diskstats"
  while IFS= read -r line; do
    echo "$line"
  done </proc/diskstats

  echo "@@section temps"
  [[ -n $cpu_temp_path ]] && echo "cpu $(first_line "$cpu_temp_path")"

  echo "@@section gpus"
  for gpu in "${gpus[@]}"; do
    IFS='|' read -r card device vendor gpu_hwmon <<<"$gpu"
    status=$(first_line "$device/power/runtime_status")
    # Reading a sleeping discrete card's sensors wakes it, which costs
    # battery, so a suspended card is reported asleep and left alone.
    if [[ $status == suspended || $status == suspending ]]; then
      echo "$card|$vendor|asleep"
      continue
    fi
    busy=$(first_line "$device/gpu_busy_percent")
    vram_used=$(first_line "$device/mem_info_vram_used")
    vram_total=$(first_line "$device/mem_info_vram_total")
    temp=""
    power=""
    if [[ -n $gpu_hwmon ]]; then
      temp=$(first_line "$gpu_hwmon/temp1_input")
      power=$(first_line "$gpu_hwmon/power1_average")
      [[ -z $power ]] && power=$(first_line "$gpu_hwmon/power1_input")
    fi
    freq=$(first_line "$device/drm/$card/gt_cur_freq_mhz")
    [[ -z $freq ]] && freq=$(first_line "/sys/class/drm/$card/gt_cur_freq_mhz")
    freq_max=$(first_line "/sys/class/drm/$card/gt_max_freq_mhz")
    echo "$card|$vendor|awake|$busy|$vram_used|$vram_total|$temp|$power|$freq|$freq_max"
  done

  if (( have_nvidia_smi )); then
    echo "@@section nvidia"
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
      --format=csv,noheader,nounits 2>/dev/null
  fi

  echo "@@end" || exit 0
  pause
done
