#!/bin/sh

SCRIPTNAME=${0##*/}

BACKUP_ROOT="${BACKUP_ROOT:-"/backup"}"

RSYNC="${RSYNC:-"auto"}"
RSYNC_OPTIONS=(${RYNC_OPTIONS:-"--verbose --delete --relative --archive"})

VERBOSE=false
FORCE=false
PERIOD=""
INCLUDE=""
SOURCES=""
NO_CASCADE=false

lastexpectedbackup=""
lastbackup=""

help() {
  echo -e "
SYNTAX: $SCRIPTNAME -I <SOURCES> [OPTIONS]\n
where:\n
  -i, --include <SOURCES>  : file containing source paths to backup,
                             one per line
\nand [OPTIONS] can be:\n
  -p, --period <PERIOD>  :  PERIOD can be either 'hourly', 'daily',
                            'weekly' or 'monthly'
  -f, --force  : force backups regardless of whether the period type's
                 epoch has elapsed since its previous update. this
                 will thus always roll the backup set along one
  -nc, --no-cascade  : limit modifications to the specified period
                       type set only
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

fnGetSourceList() {
  IFS=$'\n'
  srcs=( $(cat $INCLUDE)  )
  unset $IFS
  if [ "$VERBOSE" = "true" ]; then
    echo "[info] source directories listed for backup:"
    echo ${srcs[@]}
  fi

  # loop to sanitise strings!
  i=0
  while [ $i -lt ${#srcs[@]} ]; do
    valid=true
    if [ "$valid" = "true" ]; then
      # test for comment
      if ! [ "$(echo ${srcs[$i]} | grep "#")" = "" ]; then valid=false; fi
    fi
    if [ "$valid" = "true" ]; then
      # sanitise
      src=$(echo ${srcs[$i]} | sed 's/\"//g')
    fi
    if [ "$valid" = "true" ]; then
      # test size
      size=$(echo $(du -c ${srcs[$i]} | tail -n 1) | sed 's/total//')
      if [ $size -le 10 ]; then valid=false; fi # assuming something is wrong here!
    fi
    if [ "$valid" = "true" ]; then
      # append
      if [[ "${#SOURCES[@]}" -eq 0 || "x$SOURCES" == "x" ]]; then
        SOURCES=("$src")
      else
        SOURCES=("${SOURCES[@]}" "$src")
      fi
    fi
    i=$[$i+1]
  done
}

fnGetLastBackup() {
  if [ -f $BACKUP_ROOT/.$1 ]; then
    lastbackup=$(cat $BACKUP_ROOT/.$1)
  else
    lastbackup="01 Jan 1970"
  fi
}

fnGetLastExpectedBackup() {
  case $1 in
    "hourly")
      lastexpectedbackup=$(date +"%d %b %Y %H:00:00")
      ;;
    "daily")
      lastexpectedbackup=$(date +"%d %b %Y 00:00:00")
      ;;
    "weekly")
      # use number of weeks since a specific date
      weeksecs=$[7*24*60*60]
      nearestweeksecs=$[$[$(date +%s)/$weeksecs]*$weeksecs]
      lastexpectedbackup=$(date -d "1970-01-01 00:00:00 UTC +$nearestweeksecs seconds" +"%d %b %Y 00:00:00")
      ;;
    "monthly")
      lastexpectedbackup=$(date +"01 %b %Y 00:00:00")
      ;;
  esac
}

fnPerformBackup() {
  TYPE=$1

  fnGetLastExpectedBackup $TYPE
  fnGetLastBackup $TYPE
  success=false
  if [[ $(date -d "$lastexpectedbackup" +%s) -gt $(date -d "$lastbackup" +%s) || "$FORCE" = "true" ]] ; then
    # perform backup
    if [ "$TYPE" = "$PERIOD" ]; then
      # backup
      if [ "$VERBOSE" = "true" ]; then echo "[info] performing a $TYPE sync backup"; fi
      if [ -d $BACKUP_ROOT/$TYPE.tmp ]; then
        rm -Rf $BACKUP_ROOT/$TYPE.tmp/*
      else
        mkdir -p $BACKUP_ROOT/$TYPE.tmp
      fi
      # always backup against (hard-linking to) the 'master' copy
      if ! [ -d $BACKUP_ROOT/master ]; then mkdir -p $BACKUP_ROOT/master; fi
      # refresh master
      $RSYNC "${RSYNC_OPTIONS[@]}" "${SOURCES[@]}" $BACKUP_ROOT/master
      if [ "$VERBOSE" = "true" ]; then
        echo '$RSYNC "${RSYNC_OPTIONS[@]}" --link-dest=$BACKUP_ROOT/master "${SOURCES[@]}" $BACKUP_ROOT/$TYPE.tmp/'
        echo $RSYNC "${RSYNC_OPTIONS[@]}" --link-dest=$BACKUP_ROOT/master "${SOURCES[@]}" $BACKUP_ROOT/$TYPE.tmp/
        $RSYNC "${RSYNC_OPTIONS[@]}" --link-dest=$BACKUP_ROOT/master "${SOURCES[@]}" $BACKUP_ROOT/$TYPE.tmp/
      else
        $RSYNC "${RSYNC_OPTIONS[@]}" --link-dest=$BACKUP_ROOT/master "${SOURCES[@]}" $BACKUP_ROOT/$TYPE.tmp/ # > /dev/null
      fi
      if [[ $? -eq 0 ]]; then success=true; fi
    else
      # link
      if [ "$VERBOSE" = "true" ]; then echo "[info] performing a $TYPE link backup"; fi
      case $TYPE in
        "daily")
          if [ -d $BACKUP_ROOT/hourly.1 ]; then
            cp -al $BACKUP_ROOT/hourly.1 $BACKUP_ROOT/daily.tmp
            if [[ $? -eq 0 ]]; then success=true; fi
          fi
          ;;
        "weekly")
          if [ -d $BACKUP_ROOT/daily.1 ]; then
            cp -al $BACKUP_ROOT/daily.1 $BACKUP_ROOT/weekly.tmp
            if [[ $? -eq 0 ]]; then success=true; fi
          fi
          ;;
        "monthly")
          if [ -d $BACKUP_ROOT/weekly.1 ]; then
            cp -al $BACKUP_ROOT/weekly.1 $BACKUP_ROOT/monthly.tmp
            if [[ $? -eq 0 ]]; then success=true; fi
          fi
          ;;
      esac
    fi
    # if successful, reset the dir structure
    if [[ $? -eq 0 ]]; then
      if [ -d $BACKUP_ROOT/$TYPE.10 ]; then rm -Rf $BACKUP_ROOT/$TYPE.10; fi
      if [ -d $BACKUP_ROOT/$TYPE.9 ]; then mv $BACKUP_ROOT/$TYPE.9 $BACKUP_ROOT/$TYPE.10; fi
      if [ -d $BACKUP_ROOT/$TYPE.8 ]; then mv $BACKUP_ROOT/$TYPE.8 $BACKUP_ROOT/$TYPE.9; fi
      if [ -d $BACKUP_ROOT/$TYPE.7 ]; then mv $BACKUP_ROOT/$TYPE.7 $BACKUP_ROOT/$TYPE.8; fi
      if [ -d $BACKUP_ROOT/$TYPE.6 ]; then mv $BACKUP_ROOT/$TYPE.6 $BACKUP_ROOT/$TYPE.7; fi
      if [ -d $BACKUP_ROOT/$TYPE.5 ]; then mv $BACKUP_ROOT/$TYPE.5 $BACKUP_ROOT/$TYPE.6; fi
      if [ -d $BACKUP_ROOT/$TYPE.4 ]; then mv $BACKUP_ROOT/$TYPE.4 $BACKUP_ROOT/$TYPE.5; fi
      if [ -d $BACKUP_ROOT/$TYPE.3 ]; then mv $BACKUP_ROOT/$TYPE.3 $BACKUP_ROOT/$TYPE.4; fi
      if [ -d $BACKUP_ROOT/$TYPE.2 ]; then mv $BACKUP_ROOT/$TYPE.2 $BACKUP_ROOT/$TYPE.3; fi
      if [ -d $BACKUP_ROOT/$TYPE.1 ]; then mv $BACKUP_ROOT/$TYPE.1 $BACKUP_ROOT/$TYPE.2; fi
      mv $BACKUP_ROOT/$TYPE.tmp $BACKUP_ROOT/$TYPE.1
      echo $lastexpectedbackup > $BACKUP_ROOT/.$TYPE
      if [ "$VERBOSE" = "true" ]; then echo "[info] backup succeeded"; fi
    else
      if [ "$VERBOSE" = "true" ]; then echo "[info] backup failed"; fi
      NO_CASCADE=true
    fi
  else
    if [ "$VERBOSE" = "true" ]; then
      if [ "$TYPE" = "$PERIOD" ]; then
        echo "[info] $(date), not performing a $TYPE sync backup"
      else
        echo "[info] $(date), not performing a $TYPE link backup"
      fi
    fi
  fi
}

# fall-through implementation
fnPerformHourlyBackup() {
  fnPerformBackup "hourly"
  [ "$NO_CASCADE" != "true" ] && fnPerformDailyBackup
}

function fnPerformDailyBackup() {
  fnPerformBackup "daily"
  [ "$NO_CASCADE" != "true" ] && fnPerformWeeklyBackup
}

fnPerformWeeklyBackup() {
  fnPerformBackup "weekly"
  [ "$NO_CASCADE" != "true" ] && fnPerformMonthlyBackup
}

function fnPerformMonthlyBackup() {
  fnPerformBackup "monthly"
}


# parse args
[ $# -eq 0 ] && help && echo "[error] no parameters provided"

i=0
while [ -n "$1" ]; do
  arg="$(echo "$1" | sed 's/^ *-*//')"
  case "$arg" in
    "i"|"include") shift && [ -z "$1" ] && help && exit 1; INCLUDE=$1 ;;
    "p"|"period") shift && [ -z "$1" ] && help && exit 1; PERIOD=$1 ;;
    "f"|"force") FORCE=true ;;
    "nc"|"no-cascade") NO_CASCADE=true ;;
    "r"|"root") shift && [ -z "$1" ] && help && exit 1; BACKUP_ROOT="$1" ;;
    "h"|"help") help && exit ;;
    "v"|"verbose") VERBOSE=true ;;
  esac
  shift
done

[ ! -d $BACKUP_ROOT ] && echo "[error] invalid backup root '$BACKUP_ROOT'" && exit 1
[ -z "$PERIOD" ] && help &&
  echo "[error] please specify a period type over which to apply backups" && exit 1
[ -z "$INCLUDE" ] && help &&
  echo "[error] please specify an INCLUDE file" && exit 1
if [ ! -f "$INCLUDE" ]; then
  [ -f $BACKUP_ROOT/$INCLUDE ] && INCLUDE="$BACKUP_ROOT/$INCLUDE" ||
    echo "[error] invalid 'include' file '$INCLUDE'" && exit 1
fi
[ "x$RSYNC" = "xauto" ] && RSYNC="$(which rsync)"
[ ! -x $RSYNC ] && echo "[error] no rsync binary found$([ -n "$RSYNC" ] && echo " at '$RSYNC'")" && exit 1

# create source lits
fnGetSourceList

# process backup
case "$PERIOD" in
  "hourly") fnPerformHourlyBackup ;;
  "daily") fnPerformDailyBackup ;;
  "weekly") fnPerformWeeklyBackup ;;
  "monthly") fnPerformMonthlyBackup ;;
esac
