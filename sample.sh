#!/bin/bash

# Streams raw system readings for the sysmon plugin, one frame per interval.
#
# Usage: sample.sh [--once] [interval-seconds]
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
# if a graphics card appears or goes away. --once sends the static frame and
# one frame, then stops; the tests use it.
#
# SYSMON_ROOT, when set, is put in front of /sys, /proc and /dev, so the
# tests can run the script against a made-up machine.
#
# Drive temperatures are deliberately not part of the stream. Reading one
# sends the drive a command, and on some machines (Apple T2 laptops, where the
# drive shares a controller with the keyboard and trackpad) asking every
# couple of seconds makes input stutter. --disk-temps reads them once, for the
# disk panel to call while it is open.

root="${SYSMON_ROOT:-}"
sys="$root/sys"
proc="$root/proc"
dev="$root/dev"

if [[ ${1:-} == --disk-temps ]]; then
  for hwmon in "$sys"/class/hwmon/hwmon*; do
    [[ -r $hwmon/name && -r $hwmon/temp1_input ]] || continue
    read -r name <"$hwmon/name" || continue
    if [[ $name == nvme || $name == drivetemp ]]; then
      read -r value <"$hwmon/temp1_input" 2>/dev/null && echo "disk $value"
    fi
  done
  exit 0
fi

once=0
if [[ ${1:-} == --once ]]; then
  once=1
  shift
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

# Sets `found` to the value of KEY= in a uevent file, or to nothing.
uevent_value() {
  local key value
  found=""
  [[ -r $1 ]] || return 0
  while IFS='=' read -r key value; do
    [[ $key == "$2" ]] && found="$value" && return 0
  done <"$1"
}

# ---------------------------------------------------------- cpu temperature

# Every sensor that reads the processor. An x86 machine has one that speaks
# for the whole package; many ARM ones have a sensor per core or cluster, so
# all of them are sent and the hottest is shown. Some machines (Apple
# Silicon, virtual machines) offer none, and then no temperature is shown.
cpu_temp_paths=()

# x86: the driver is known and so is the label of its package reading.
for hwmon in "$sys"/class/hwmon/hwmon*; do
  [[ -d $hwmon ]] || continue
  case "$(first_line "$hwmon/name")" in
    coretemp | k10temp | zenpower)
      for label in "$hwmon"/temp*_label; do
        [[ -r $label ]] || continue
        case "$(first_line "$label")" in
          "Package id 0" | Tctl | Tdie)
            cpu_temp_paths=("${label%_label}_input")
            break
            ;;
        esac
      done
      [[ ${#cpu_temp_paths[@]} -eq 0 && -r $hwmon/temp1_input ]] && cpu_temp_paths=("$hwmon/temp1_input")
      ;;
  esac
  [[ ${#cpu_temp_paths[@]} -gt 0 ]] && break
done

# Elsewhere: any sensor whose label says it sits on the processor, or whose
# device is named for it.
if [[ ${#cpu_temp_paths[@]} -eq 0 ]]; then
  for hwmon in "$sys"/class/hwmon/hwmon*; do
    [[ -d $hwmon ]] || continue
    name=$(first_line "$hwmon/name")
    name="${name,,}"
    for label in "$hwmon"/temp*_label; do
      [[ -r $label && -r ${label%_label}_input ]] || continue
      text=$(first_line "$label")
      text="${text,,}"
      [[ $text == *gpu* ]] && continue
      if [[ $text == *cpu* || $text == *"core"* ]]; then
        cpu_temp_paths+=("${label%_label}_input")
      fi
    done
    if [[ $name == *cpu* && $name != *gpu* && -r $hwmon/temp1_input ]]; then
      cpu_temp_paths+=("$hwmon/temp1_input")
    fi
    [[ ${#cpu_temp_paths[@]} -ge 32 ]] && break
  done
fi

# Last, thermal zones, by how directly their type names the processor.
if [[ ${#cpu_temp_paths[@]} -eq 0 ]]; then
  for wanted in cpu soc x86_pkg_temp acpitz; do
    for zone in "$sys"/class/thermal/thermal_zone*; do
      [[ -r $zone/type && -r $zone/temp ]] || continue
      type=$(first_line "$zone/type")
      type="${type,,}"
      [[ $type == *gpu* ]] && continue
      [[ $type == *"$wanted"* ]] && cpu_temp_paths+=("$zone/temp")
      [[ ${#cpu_temp_paths[@]} -ge 32 ]] && break
    done
    [[ ${#cpu_temp_paths[@]} -gt 0 ]] && break
  done
fi

# ------------------------------------------------------------ graphics cards

# One entry per graphics card:
#   "<card>|<device dir>|<vendor>|<hwmon dir>|<load source>"
#
# <vendor> is the PCI vendor id, or the driver's name for a card that is not
# on a PCI bus (every ARM system-on-chip). <load source> is "sysfs" when the
# driver publishes a load figure itself, "nvidia" when nvidia-smi has to be
# asked, and "clients" when the only source is the usage each program reports
# through its open handle on the card.
#
# Cards are looked for again whenever the set of them changes, not just once:
# the shell can start before a graphics driver has finished loading (a
# discrete card on a hybrid laptop routinely registers seconds later), and a
# card found late would otherwise stay missing until the next restart.
gpus=()
gpu_signature=""
watch_clients=0
clients_age=-1

# Everything the card list is built from, as one string. Globbing is a
# builtin, so checking it every frame costs no forks. The result is left in
# gpu_scan_result rather than printed, so reading it needs no subshell.
gpu_scan_result=""
gpu_scan() {
  local paths=("$sys"/class/drm/card[0-9]*/device/drm/renderD* "$sys"/class/drm/card[0-9]*/device/hwmon/hwmon*)
  gpu_scan_result="${paths[*]}"
}

discover_gpus() {
  local card device gpu_hwmon candidate vendor driver source render
  gpus=()
  watch_clients=0
  for card in "$sys"/class/drm/card[0-9]*; do
    [[ ${card##*/} =~ ^card[0-9]+$ ]] || continue
    device="$card/device"
    [[ -d $device ]] || continue
    # A card that cannot render is only a display controller (on Apple
    # Silicon the screen and the GPU are separate devices) or a boot
    # framebuffer; it has no load to report.
    render=""
    for candidate in "$device"/drm/renderD*; do
      [[ -e $candidate ]] && render="${candidate##*/}" && break
    done
    [[ -n $render ]] || continue

    uevent_value "$device/uevent" DRIVER
    driver="$found"
    vendor=$(first_line "$device/vendor")
    [[ -z $vendor ]] && vendor="${driver:-unknown}"

    gpu_hwmon=""
    for candidate in "$device"/hwmon/hwmon*; do
      [[ -d $candidate ]] && gpu_hwmon="$candidate" && break
    done

    if [[ -r $device/gpu_busy_percent ]]; then
      source=sysfs
    elif [[ $vendor == 0x10de || $driver == nvidia* ]]; then
      source=nvidia
    else
      source=clients
      watch_clients=1
    fi
    gpus+=("${card##*/}|$device|$vendor|$gpu_hwmon|$source")
  done
  clients_age=-1
}

# ------------------------------------------------- per-program graphics use
#
# Intel, Qualcomm and most other ARM drivers publish no load figure for the
# card as a whole. What the kernel does offer, to anyone, is how much time
# each program has had on the card: a few lines in /proc/<pid>/fdinfo for
# every handle a program holds open on it (Documentation/gpu/
# drm-usage-stats.rst). Adding those up gives the load.
#
# Finding the handles means looking at every open file of every process, so
# it is done once every few frames; reading the ones already found is cheap
# and done on each.

# "<card> <fdinfo path>", one per program-side client of a watched card.
drm_clients=()
readonly clients_rescan_frames=5

find_drm_clients() {
  local gpu card device source node fd info line id key i
  local nodes=() node_cards=()
  local -A seen=()
  drm_clients=()

  for gpu in "${gpus[@]}"; do
    IFS='|' read -r card device _ _ source <<<"$gpu"
    [[ $source == clients ]] || continue
    for node in "$device"/drm/card[0-9]* "$device"/drm/renderD*; do
      [[ -e $node && -e $dev/dri/${node##*/} ]] || continue
      nodes+=("$dev/dri/${node##*/}")
      node_cards+=("$card")
    done
  done
  [[ ${#nodes[@]} -gt 0 ]] || return 0

  for fd in "$proc"/[0-9]*/fd/*; do
    # Cheap test first: almost no open file is a device.
    [[ -c $fd ]] || continue
    for i in "${!nodes[@]}"; do
      [[ $fd -ef ${nodes[i]} ]] || continue
      info="${fd%/fd/*}/fdinfo/${fd##*/}"
      # Handles shared between processes, or duplicated within one, all
      # report the same client; one of each is enough.
      id=""
      if [[ -r $info ]]; then
        while IFS= read -r line; do
          if [[ $line == drm-client-id:* ]]; then
            id="${line#*:}"
            id="${id//[[:space:]]/}"
            break
          fi
        done <"$info" 2>/dev/null
      fi
      if [[ -n $id ]]; then
        key="${node_cards[i]}/$id"
        if [[ -z ${seen[$key]:-} ]]; then
          seen[$key]=1
          drm_clients+=("${node_cards[i]} $info")
        fi
      fi
      break
    done
  done
}

emit_drm_clients() {
  local entry card info line
  echo "@@section drmclients"
  for entry in "${drm_clients[@]}"; do
    card="${entry%% *}"
    info="${entry#* }"
    [[ -r $info ]] || continue
    echo "@ $card"
    while IFS= read -r line; do
      case "$line" in
        drm-client-id:* | drm-engine-* | drm-cycles-* | drm-total-cycles-*) echo "$line" ;;
      esac
    done <"$info" 2>/dev/null
  done
}

gpu_scan
gpu_signature="$gpu_scan_result"
discover_gpus

have_nvidia_smi=0
[[ -z $root ]] && command -v nvidia-smi >/dev/null 2>&1 && have_nvidia_smi=1

# ------------------------------------------------------------------- static

# The processor's name. x86 states it in /proc/cpuinfo; 64-bit ARM does not,
# so there it is the name of the machine ("Apple MacBook Air (M1, 2020)"),
# which says more than the core names lscpu would give.
cpu_model() {
  local line model=""
  if [[ -r $proc/cpuinfo ]]; then
    while IFS= read -r line; do
      if [[ $line == "model name"* ]]; then
        model="${line#*: }"
        break
      fi
    done <"$proc/cpuinfo"
  fi
  if [[ -z $model && -r $proc/device-tree/model ]]; then
    # Device tree strings end in a NUL, which read stops at.
    IFS= read -r -d '' model <"$proc/device-tree/model" 2>/dev/null
  fi
  if [[ -z $model ]]; then
    model=$(first_line "$sys/devices/virtual/dmi/id/product_name")
  fi
  printf '%s' "$model"
}

emit_static() {
  local gpu card device vendor label block
  echo "@@static"
  echo "@@section cpuinfo"
  echo "model name : $(cpu_model)"
  echo "@@section blocks"
  for block in "$sys"/block/*; do
    [[ -d $block ]] && echo "${block##*/}"
  done
  echo "@@section gpunames"
  for gpu in "${gpus[@]}"; do
    IFS='|' read -r card device vendor _ <<<"$gpu"
    uevent_value "$device/uevent" PCI_SLOT_NAME
    label=""
    if [[ -n $found && -z $root ]] && command -v lspci >/dev/null 2>&1; then
      label=$(lspci -s "$found" 2>/dev/null | head -n 1)
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

  read -r uptime _ <"$proc/uptime" || uptime=0
  echo "@@frame $uptime" || exit 0

  echo "@@section stat"
  while IFS= read -r line; do
    [[ $line == cpu* ]] && echo "$line"
  done <"$proc/stat"

  echo "@@section loadavg"
  first_line "$proc/loadavg"
  echo

  echo "@@section meminfo"
  while IFS= read -r line; do
    case "$line" in
      MemTotal:* | MemFree:* | MemAvailable:* | Buffers:* | Cached:* | SReclaimable:* | Shmem:* | SwapTotal:* | SwapFree:*)
        echo "$line"
        ;;
    esac
  done <"$proc/meminfo"

  echo "@@section diskstats"
  while IFS= read -r line; do
    echo "$line"
  done <"$proc/diskstats"

  # Each interface's counters, marked "p" when a real device stands behind
  # it (and "v" for loopback, VPNs, bridges and the like, which only carry
  # traffic a real one already counted) and with its link state.
  echo "@@section net"
  if [[ -r $proc/net/dev ]]; then
    while IFS= read -r line; do
      [[ $line == *:* ]] || continue
      name="${line%%:*}"
      name="${name//[[:space:]]/}"
      kind=v
      [[ -e $sys/class/net/$name/device ]] && kind=p
      state=$(first_line "$sys/class/net/$name/operstate")
      echo "$kind ${state:-unknown} $line"
    done <"$proc/net/dev"
  fi

  echo "@@section temps"
  for path in "${cpu_temp_paths[@]}"; do
    echo "cpu $(first_line "$path")"
  done

  echo "@@section gpus"
  for gpu in "${gpus[@]}"; do
    IFS='|' read -r card device vendor gpu_hwmon source <<<"$gpu"
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
    # i915 keeps its clock speed beside the card; xe under the first tile.
    freq=$(first_line "$device/drm/$card/gt_cur_freq_mhz")
    freq_max=$(first_line "$device/drm/$card/gt_max_freq_mhz")
    if [[ -z $freq ]]; then
      freq=$(first_line "$device/tile0/gt0/freq0/act_freq")
      freq_max=$(first_line "$device/tile0/gt0/freq0/max_freq")
    fi
    echo "$card|$vendor|awake|$busy|$vram_used|$vram_total|$temp|$power|$freq|$freq_max"
  done

  if (( watch_clients )); then
    if (( clients_age < 0 || clients_age >= clients_rescan_frames )); then
      find_drm_clients
      clients_age=0
    fi
    clients_age=$((clients_age + 1))
    emit_drm_clients
  fi

  if (( have_nvidia_smi )); then
    echo "@@section nvidia"
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
      --format=csv,noheader,nounits 2>/dev/null
  fi

  echo "@@end" || exit 0
  (( once )) && exit 0
  pause
done
