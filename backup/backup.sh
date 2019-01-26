#!/bin/sh

SCRIPTNAME=${0##*/}
DEBUG=${DEBUG:-0}
IFSORG="$IFS"

BACKUP_ROOT="${BACKUP_ROOT:-"/backup"}"

RSYNC="${RSYNC:-"auto"}"
RSYNC_OPTIONS=($(echo "${RYNC_OPTIONS:-"--verbose --delete --relative --archive"}"))

VERBOSE=0
FORCE=0
TYPE=""
INCLUDE=".include"
NO_CASCADE=0

intervals_default="hourly,daily,weekly,monthly"
INTERVALS="$intervals_default"
declare -A intervals_epoch
intervals_epoch["hourly"]="1 hour"
intervals_epoch["daily"]="1 day"
intervals_epoch["weekly"]="1 week"
intervals_epoch["monthly"]="1 month"
declare -A intervals_anchor
intervals_anchor["hourly"]="%d %b %Y %H:00:00"
intervals_anchor["daily"]="%d %b %Y"
intervals_anchor["weekly"]="01 Jan %Y"
intervals_anchor["monthly"]="01 %b %Y"

declare -a sources


help() {
  echo -e "
SYNTAX: $SCRIPTNAME [OPTIONS]\n
where [OPTIONS] can be:\n
  -s, --sources <SOURCES>  : file containing source paths to backup,
                             one per line
                             (default: 'BACKUP_ROOT/.include')
  -i, --intervals <INTERVALS>  : comma-delimited list of supported
                                 interval types (default: 'hourly,daily
                                 ,weekly,monthly')
  -t, --type <TYPE>  : initiate backup from TYPE interval, where TYPE
                       is a member of the INTERVALS set (default: first
                       item in (epoch size ordered) INTERVALS list)
  -f, --force  : force backup regardless of whether the interval type's
                 epoch has elapsed since its previous update. this
                 will thus always roll the backup set along one. this
                 has no effect on cascaded interval types
  -nc, --no-cascade  : update only the specified interval type's set
  -r, --root  : specify the root of the backup set
  -v, --verbose  : verbose mode
  -h, --help  : this help info
\nenvironment variables:\n
  BACKUP_ROOT  : as detailed above
  RSYNC  : path to the rsync binary to use (default: auto)
  RSYNC_OPTIONS  : space delimited set of options to pass to rsync.
                   modifying this is very dangerous and may compromise
                   your backup set
                   (default: --verbose --delete --relative --archive)
"
}


fnSetSources() {

  include=$(cat $INCLUDE)

  [ $DEBUG -gt 0 ] && echo -e "[debug] raw includes list:\n$include" 1>&2
  IFS=$'\n'; list=($(echo "$include")); IFS="$IFSORG"

  # process lines
  for s in "${list[@]}"; do
    # ignore comment lines
    [ -n "$(echo "$s" | sed -n '/^[\t ]*#/p')" ] && continue
    # sanitise include strings
    # strip any leading space and inline comments
    s="$(echo "$s" | sed 's/^[\t ]*\([^#]*\)#.*/\1/;s/[\t ]*$//')"
    # strip any quotes
    s="$(echo "$s" | sed 's/\"//g')"
    # include target validity
    [[ -n "$s" && -d "$s" ]] \
      && sources[${#sources[@]}]="$s" \
      || echo "[info] dropping invalid include target '$s'"
  done

  [ ${#sources[@]} -eq 0 ] && echo "[error] no valid source include paths found" && return 1

  [ $VERBOSE -eq 1 ] && echo "[info] validated ${#sources[@]} source include path$([ ${#sources[@]} -ne 1 ] && echo "s") for backup:" && for s in "${sources[@]}"; do echo "$s"; done

  return 0
}

fnSetIntervals() {
  valid=""
  IFS=','; intervals=($(echo "$INTERVALS")); IFS="$IFSORG"
  for i in "${intervals[@]}"; do
    interval="$i"
    if [ -z "$(echo "$interval" | sed -n '/'$(echo "$intervals_default" | sed 's/,/\\|/g')'/p')" ]; then
      custom=0
      if [ -n "$(echo "$interval" | sed -n '/|/p')" ]; then
        IFS='|'; parts=($(echo "$interval")); IFS="$IFSORG"
        if [ ${#parts[@]} -eq 3 ]; then
          interval="${parts[0]}"
          epoch="${parts[1]}"
          anchor="${parts[2]}"
          date -d "$epoch" 2>/dev/null 1>&2 && date "+$anchor" 2>/dev/null 1>&2
          if [ $? -eq 0 ]; then
            custom=1
            intervals_epoch["$interval"]="$epoch"
            intervals_anchor["$interval"]="$anchor"
          fi
        fi
      fi
      [ $custom -eq 0 ] && echo "[error] unsupported interval type '$i'" && return 1
    fi
    valid+=" $interval"
  done
  valid="${valid:1}"
  ordered=""
  s=""
  now="$(date "+%d %b %Y %T UTC")"
  for interval in $(echo "$valid"); do
    s+="\n$(fnEpochSeconds "$now" "${intervals_epoch["$interval"]}")\t$interval"
  done
  s="${s:2}"
  ordered="$(echo -e "$s" | sort -n -u | sed 's/^[ \t]*[0-9]\+[ \t]*\([^ \t]*\)[ \t]*$/\1/' | tr '\n' ',' | sed 's/,$//')"
  INTERVALS="$ordered"
  [ -z $TYPE ] && TYPE="${INTERVALS%%,*}"
  return 0
}

fnGetLastBackup() {
  interval="$1"
  [ -f "$BACKUP_ROOT/.$interval" ] && cat "$BACKUP_ROOT/.$interval" || echo "01 Jan 1970"
}

fnEpochSeconds() {
  dt="$1"
  epoch="$2"
  dt_seconds=$(date -d "$dt" "+%s")
  epoch_seconds=$(($(date -d "$dt + $epoch" "+%s")-$dt_seconds))
  echo $epoch_seconds
}

fnGetLastExpectedBackup() {
  interval="$1"
  epoch=${intervals_epoch["$interval"]}
  anchor=${intervals_anchor["$interval"]}

  now="$(date "+%d %b %Y %T UTC")"
  now_seconds=$(date -d "$now" "+%s")

  epoch_seconds=$(fnEpochSeconds "$now" "$epoch")
  anchor_seconds=$(date -d "$(date "+$anchor UTC")" "+%s")

  # closest previous epoch
  epoch_last_seconds=$(($now_seconds-$(echo "($now_seconds-$anchor_seconds) % $epoch_seconds" | bc)))
  epoch_last="$(date -d "@$epoch_last_seconds" "+%d %b %Y %T")"
  [ $DEBUG -gt 0 ] && echo "[debug] anchoring interval type: '$interval' to date: '$epoch_last'" 1>&2

  echo "$epoch_last"
}

fnPerformBackup() {
  interval="$1"

  dt_last_expected="$(fnGetLastExpectedBackup "$interval")"
  dt_last="$(fnGetLastBackup "$interval")"

  backup=0
  [[ $(date -d "$dt_last_expected" +%s) -gt $(date -d "$dt_last" +%s) || $FORCE -eq 1 ]] && backup=1

  # short ciruit
  if [ $backup -eq 0 ]; then
    [ $VERBOSE -eq 1 ] && \
      echo "[info] $(date "+%d %b %Y %T"), not performing a '$interval' $([ "$interval" = "$TYPE" ] && echo "sync" || echo "link") backup as epoch not ellapsed"
    return 0
  fi

  success=1
  # perform backup
  ## always backup against (hard-link to common / unchanged files in) the 'master' backup set
  if [ "$interval" = "$TYPE" ]; then
    # rebuild master
    success=0
    [ $VERBOSE -eq 1 ] && echo "[info] rebuilding 'master' backup set"
    [ -d "$BACKUP_ROOT"/master.tmp ] && rm -rf "$BACKUP_ROOT"/master.tmp ]
    [ -d "$BACKUP_ROOT"/master ] && mv "$BACKUP_ROOT"/master{,.tmp} || mkdir -p "$BACKUP_ROOT"/master.tmp
    [ ! -d "$BACKUP_ROOT"/master ] && mkdir -p "$BACKUP_ROOT"/master
    if [ $DEBUG -gt 0 ]; then
      echo '[debug] $RSYNC "${RSYNC_OPTIONS[@]}" --link-dest=$BACKUP_ROOT/master.tmp/ "${sources[@]}" $BACKUP_ROOT/master/'
      echo "[debug] $RSYNC ${RSYNC_OPTIONS[@]} --link-dest=$BACKUP_ROOT/master.tmp/ ${sources[@]} $BACKUP_ROOT/master/"
    fi
    echo
    $RSYNC "${RSYNC_OPTIONS[@]}" --link-dest="$BACKUP_ROOT"/master.tmp/ "${sources[@]}" "$BACKUP_ROOT"/master/
    [ $? -eq 0 ] && success=1
    echo
    rm -rf "$BACKUP_ROOT"/master.tmp
  fi

  if [ $success -eq 1 ]; then
    # link backup
    success=0
    [ $VERBOSE -eq 1 ] && echo "[info] performing a '$interval' link backup"
    if [ $DEBUG -gt 0 ]; then
      echo '[debug] cp -al $BACKUP_ROOT/master $BACKUP_ROOT/$interval.tmp' 1>&2
      echo "[debug] cp -al $BACKUP_ROOT/master $BACKUP_ROOT/$interval.tmp" 1>&2
    fi
    cp -al "$BACKUP_ROOT"/master "$BACKUP_ROOT/$interval".tmp
    [ $? -eq 0 ] && success=1
  fi

  if [ $success -eq 1 ]; then
    # roll the directory structure
    [ $VERBOSE -eq 1 ] && echo "[info] rolling '$interval' backup set"
    interval_sets_max=10
    [ -d "$BACKUP_ROOT/$interval.$interval_sets_max" ] && \
       rm -rf "$BACKUP_ROOT/$interval.$interval_sets_max"
    for l in $(seq $interval_sets_max -1 2); do
      source="$BACKUP_ROOT/$interval.$(($l-1))"
      target="$BACKUP_ROOT/$interval.$l"
      if [ -d "$source" ]; then
        [ $DEBUG -gt 0 ] && echo "[debug] mv $source $target" 1>&2
        mv "$source" "$target"
      fi
    done
    mv "$BACKUP_ROOT/$interval.tmp" "$BACKUP_ROOT/$interval.1"
    [ $DEBUG -gt 0 ] && echo "[debug] mv $BACKUP_ROOT/$interval.tmp $BACKUP_ROOT/$interval.1" 1>&2
    echo -e "anchor datetime: '$dt_last_expected'\nbackup datetime: '$(date "+%d %b %Y %T")'" > "$BACKUP_ROOT/$interval.1/.timestamp"
    echo $dt_last_expected > "$BACKUP_ROOT/.$interval"
    [ $VERBOSE -eq 1 ] && echo "[info] backup succeeded"
  else
    [ $VERBOSE -eq 1 ] && echo "[info] backup failed"
    NO_CASCADE=1
  fi
}

# cascading backups
fnBackup() {
  initialised=0
  IFS=','; intervals=($(echo "$INTERVALS")); IFS="$IFSORG"
  for interval in "${intervals[@]}"; do
    [[ $initialised -eq 0 && "$interval" != "$TYPE" ]] && continue
    fnPerformBackup "$interval"
    initialised=1
    [ $NO_CASCADE -ne 0 ] && break
  done
  return 0
}

# parse args
i=0
while [ -n "$1" ]; do
  arg="$(echo "$1" | sed 's/^ *-*//')"
  case "$arg" in
    "s"|"sources") shift && [ -z "$1" ] && help && exit 1; INCLUDE="$1" ;;
    "i"|"intervals") shift && [ -z "$1" ] && help && exit 1; INTERVALS="$1" ;;
    "t"|"type") shift && [ -z "$1" ] && help && exit 1; TYPE=$1 ;;
    "f"|"force") FORCE=1 ;;
    "nc"|"no-cascade") NO_CASCADE=1 ;;
    "r"|"root") shift && [ -z "$1" ] && help && exit 1; BACKUP_ROOT="$1" ;;
    "h"|"help") help && exit ;;
    "v"|"verbose") VERBOSE=1 ;;
  esac
  shift
done

[ ! -d "$BACKUP_ROOT" ] && echo "[error] invalid backup root '$BACKUP_ROOT'" && exit 1
[ -z "$INCLUDE" ] && help &&
  echo "[error] please specify an INCLUDE file" && exit 1
if [ ! -f "$INCLUDE" ]; then
  if [ -f "$BACKUP_ROOT/$INCLUDE" ]; then
    INCLUDE="$BACKUP_ROOT/$INCLUDE"
  else
    echo "[error] invalid 'include' file '$INCLUDE'" && exit 1
  fi
fi
[ "x$RSYNC" = "xauto" ] && RSYNC="$(which rsync)"
[ ! -x $RSYNC ] && echo "[error] no rsync binary found$([ -n "$RSYNC" ] && echo " at '$RSYNC'")" && exit 1

# parse includes
fnSetSources
ret=$? && [ $ret -ne 0 ] && exit $ret

# parse intervals
fnSetIntervals
ret=$? && [ $ret -ne 0 ] && exit $ret
[ -z "$(echo "$TYPE" | sed -n '/'$(echo "$INTERVALS" | sed 's/,/\\|/g')'/p')" ] && \
  echo "[error] unrecognised interval type '$TYPE'" && exit 1

# process backup
fnBackup
