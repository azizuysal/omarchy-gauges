#!/bin/bash

# Which processes are using the disk or the graphics cards, for the lists in
# those panels. Run once per refresh, and only while such a panel is open.
#
# Usage: processes.sh --disk
#        processes.sh --gpu
#
# --disk prints "<pid> <bytes read> <bytes written> <name>" for every process
# whose /proc/<pid>/io can be read, which for an ordinary user is their own.
# The counts are totals since the process started; the caller compares two
# runs.
#
# --gpu prints, for every program holding a graphics card open, what the
# driver reports about it in /proc/<pid>/fdinfo, in the same shape as
# sample.sh's "drmclients" section, followed by "gauges-pid:" and
# "gauges-name:" lines saying whose it is. Again only your own programs can
# be read. Cards that are powered down are left alone.
#
# Only bash builtins are used, as in sample.sh, and GAUGES_ROOT stands in for
# / the same way, for the tests.

root="${GAUGES_ROOT:-}"
proc="$root/proc"
sys="$root/sys"
dev="$root/dev"

first_line() {
  value=""
  [[ -r $1 ]] && read -r value <"$1" 2>/dev/null
}

if [[ ${1:-} == --disk ]]; then
  for io in "$proc"/[0-9]*/io; do
    [[ -r $io ]] || continue
    read_bytes=""
    write_bytes=""
    while read -r key amount; do
      case "$key" in
        read_bytes:) read_bytes=$amount ;;
        write_bytes:) write_bytes=$amount ;;
      esac
    done <"$io" 2>/dev/null
    [[ -n $read_bytes && -n $write_bytes ]] || continue
    pid="${io%/io}"
    first_line "$pid/comm"
    [[ -n $value ]] && echo "${pid##*/} $read_bytes $write_bytes $value"
  done
  exit 0
fi

if [[ ${1:-} == --gpu ]]; then
  nodes=()
  node_cards=()
  for card in "$sys"/class/drm/card[0-9]*; do
    name="${card##*/}"
    # card1-eDP-1 and the like are a card's outputs, not cards.
    [[ $name == *-* || ! -e $card/device ]] && continue
    first_line "$card/device/power/runtime_status"
    [[ $value == suspended ]] && continue
    for node in "$card"/device/drm/card[0-9]* "$card"/device/drm/renderD*; do
      [[ -e $node && -e $dev/dri/${node##*/} ]] || continue
      nodes+=("$dev/dri/${node##*/}")
      node_cards+=("$name")
    done
  done
  [[ ${#nodes[@]} -gt 0 ]] || exit 0

  declare -A seen=()
  for fd in "$proc"/[0-9]*/fd/*; do
    # Cheap test first: almost no open file is a device.
    [[ -c $fd ]] || continue
    for i in "${!nodes[@]}"; do
      [[ $fd -ef ${nodes[i]} ]] || continue
      pid="${fd%/fd/*}"
      info="$pid/fdinfo/${fd##*/}"
      [[ -r $info ]] || continue
      lines=()
      id=""
      while IFS= read -r line; do
        case "$line" in
          drm-client-id:*)
            id="${line#*:}"
            id="${id//[[:space:]]/}"
            lines+=("$line")
            ;;
          drm-engine-* | drm-cycles-* | drm-total-cycles-*) lines+=("$line") ;;
        esac
      done <"$info" 2>/dev/null
      # One program can hold a client through several handles, and hand it
      # to another; the first holder found speaks for it.
      [[ -n $id && -z ${seen[${node_cards[i]}/$id]:-} ]] || continue
      seen[${node_cards[i]}/$id]=1
      first_line "$pid/comm"
      echo "@ ${node_cards[i]}"
      printf '%s\n' "${lines[@]}"
      echo "gauges-pid: ${pid##*/}"
      echo "gauges-name: $value"
    done
  done
  exit 0
fi

echo "Usage: $0 --disk | --gpu" >&2
exit 2
