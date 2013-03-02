#!/bin/bash

#read files which state the last backup up time for 'period' of backup, and decide whether the backup is required or not
#we want to perform backup to the nearest hour, day

#multiple src directories ..was looking at including from a file by creating an array of '\n' delimited entries. i'd have
#append and prepend '"'s to each path to create a string that could be used as as a parameter to rsync command to safegaurd
#against slitting directories with spaces in the name!
#--files-from doesn't work the way i want it to. ..it's files relative to the source directory

BACKUPROOT="/backup"
RSYNC="/usr/local/bin/rsync"
RSYNCOPTIONS=( "-varR" "--delete" )
#-n	: dry run
#-r	: recursive (implied by -a)
#-a	: implies -rlptgoD
#-p	: preserve permissions
#-o	: preserve owner (super-user only)
#-g	: preserve group
#-l	: copy symlinks as symlinks
#--files-from	: change the meaning of -a  ..need to append --no-R
#--no-R	: the relative path part of the source directory is not kept

VERBOSE=false
FORCE=false
PERIOD=""
INCLUDE=""
SOURCES=""
LIMIT=false

argsarray=( "$@" )

function help()
{
  echo -e "\nusage backup_ -I <sources file> -p <backup period> [OPTIONS]\n
    Be aware that forcing a sync will push the backup dirs back one!\n
\t-h	: help
\t-v	: verbose
\t-f	: force
\t-l	: limit to period specified only
\t-I	: file containing source paths to backup, one per line
\t-p	: period. either 'hourly' 'daily' 'weekly' or 'monthly' are valid periods\n"
}

if [ $# -eq 0 ]; then
  echo "no parameters provided"
  help
  exit 1
else
  #parse args
  i=0
  while [ $i -lt ${#argsarray[@]} ]; do
    case ${argsarray[$i]} in
      "-v")
        VERBOSE=true
        ;;
      "-f")
        FORCE=true
        ;;
      "-l")
        LIMIT=true
        ;;
      "-h")
        help
        exit 0
        ;;
      "-p")
        if [ $[$i+1] -lt ${#argsarray[@]} ]; then
          PERIOD=${argsarray[$[$i+1]]}
          i=$[$i+1]
        fi
        ;;
      "-I")
        if [ $[$i+1] -lt ${#argsarray[@]} ]; then
          INCLUDE=${argsarray[$[$i+1]]} 
          i=$[$i+1]
        fi
        ;;
    esac
    i=$[$i+1]
  done
fi

function getsourcelist()
{
  IFS=$'\n'
  srcs=( $(cat $INCLUDE)  )
  unset $IFS
  if [ "$VERBOSE" == "true" ]; then
    echo "source directories listed for backup:"
    echo ${srcs[@]}
  fi

  #loop to sanitise strings!  
  i=0
  while [ $i -lt ${#srcs[@]} ]; do
    valid=true
    if [ "$valid" == "true" ]; then 
      #test for comment
      if ! [ "$(echo ${srcs[$i]} | grep "#")" = "" ]; then valid=false; fi
    fi
    if [ "$valid" == "true" ]; then 
      #sanitise
      src=$(echo ${srcs[$i]} | sed 's/\"//g')
    fi
    if [ "$valid" == "true" ]; then 
      #test size
      size=$(echo $(du -c ${srcs[$i]} | tail -n 1) | sed 's/total//')
      if [ $size -le 10 ]; then valid=false; fi # assuming something is wrong here!
    fi
    if [ "$valid" == "true" ]; then
      #append
      if [ "${SOURCES[@]}" == "" ]; then
        SOURCES=( "$src" )
      else
        SOURCES=( "${SOURCES[@]}" "$src" )
      fi
    fi
    i=$[$i+1]
  done
}

if [ "$PERIOD" == "" ]; then
  echo "please specify a period type over which to apply backups"
  exit 1
fi

if [ "$INCLUDE" == "" ]; then
  echo "please specify an INCLUDE file"
  exit 1
elif ! [ -f $INCLUDE ]; then
  if [ -f $BACKUPROOT/$INCLUDE ]; then
    INCLUDE=$BACKUPROOT/$INCLUDE
  fi
fi
if ! [ -f $INCLUDE ]; then
  echo "please specify an 'include' file with the -I parameter"
  exit 1
else
  getsourcelist
fi

if ! [ -x $RSYNC ]; then
  echo "no rsync executable found at $RSYNC"
  exit 1
fi

if ! [ -d $BACKUPROOT ]; then
  echo "backup root $BACKUPROOT is not invalid"
  exit 1
fi

lastexpectedbackup=""
lastbackup=""

function getlastbackup()
{
  if [ -f $BACKUPROOT/.$1 ]; then
    lastbackup=$(cat $BACKUPROOT/.$1)
  else
    lastbackup="01 Jan 1970"
  fi
}
function getlastexpectedbackup()
{
  case $1 in 
    "hourly")
      lastexpectedbackup=$(date +"%d %b %Y %H:00:00")
      ;;
    "daily")
      lastexpectedbackup=$(date +"%d %b %Y 00:00:00")
      ;;
    "weekly")
      #use number of weeks since a specific date
      weeksecs=$[7*24*60*60]
      nearestweeksecs=$[$[$(date +%s)/$weeksecs]*$weeksecs]
      lastexpectedbackup=$(date -d "1970-01-01 00:00:00 UTC +$nearestweeksecs seconds" +"%d %b %Y 00:00:00")
      ;;
    "monthly")
      lastexpectedbackup=$(date +"01 %b %Y 00:00:00")
      ;;
  esac
}

function performbackup()
{
  TYPE=$1
  
  getlastexpectedbackup $TYPE
  getlastbackup $TYPE
  success=false
  if [[ $(date -d "$lastexpectedbackup" +%s) -gt $(date -d "$lastbackup" +%s) || "$FORCE" = "true" ]] ; then
    #perform backup!
    if [ "$TYPE" == "$PERIOD" ]; then
      #backup
      if [ "$VERBOSE" == "true" ]; then echo "performing a $TYPE sync backup"; fi
      if [ -d $BACKUPROOT/$TYPE.tmp ]; then
        rm -Rf $BACKUPROOT/$TYPE.tmp/*
      else
        mkdir -p $BACKUPROOT/$TYPE.tmp
      fi
      if ! [ -d $BACKUPROOT/$TYPE.1 ]; then mkdir -p $BACKUPROOT/$TYPE.1; fi
      if [ "$VERBOSE" == "true" ]; then
	echo '$RSYNC "${RSYNCOPTIONS[@]}" --link-dest=$BACKUPROOT/$TYPE.1 "${SOURCES[@]}" $BACKUPROOT/$TYPE.tmp/'
	echo $RSYNC "${RSYNCOPTIONS[@]}" --link-dest=$BACKUPROOT/$TYPE.1 "${SOURCES[@]}" $BACKUPROOT/$TYPE.tmp/
        $RSYNC "${RSYNCOPTIONS[@]}" --link-dest=$BACKUPROOT/$TYPE.1 "${SOURCES[@]}" $BACKUPROOT/$TYPE.tmp/
      else
        $RSYNC "${RSYNCOPTIONS[@]}" --link-dest=$BACKUPROOT/$TYPE.1 "${SOURCES[@]}" $BACKUPROOT/$TYPE.tmp/ 
	# > /dev/null
      fi
      if [[ $? -eq 0 ]]; then success=true; fi
    else
      #link
      if [ "$VERBOSE" == "true" ]; then echo "performing a $TYPE link backup"; fi
      case $TYPE in
        "daily")
          if [ -d $BACKUPROOT/hourly.1 ]; then 
            cp -al $BACKUPROOT/hourly.1 $BACKUPROOT/daily.tmp
            if [[ $? -eq 0 ]]; then success=true; fi
          fi
          ;;
        "weekly")
          if [ -d $BACKUPROOT/daily.1 ]; then
            cp -al $BACKUPROOT/daily.1 $BACKUPROOT/weekly.tmp
            if [[ $? -eq 0 ]]; then success=true; fi
          fi
          ;;
        "monthly")
          if [ -d $BACKUPROOT/weekly.1 ]; then 
            cp -al $BACKUPROOT/weekly.1 $BACKUPROOT/monthly.tmp
            if [[ $? -eq 0 ]]; then success=true; fi
          fi
          ;;
      esac      
    fi
    #if successful, reset the dir structure
    if [[ $? -eq 0 ]]; then
      if [ -d $BACKUPROOT/$TYPE.5 ]; then rm -Rf $BACKUPROOT/$TYPE.5; fi
      if [ -d $BACKUPROOT/$TYPE.4 ]; then mv $BACKUPROOT/$TYPE.4 $BACKUPROOT/$TYPE.5; fi
      if [ -d $BACKUPROOT/$TYPE.3 ]; then mv $BACKUPROOT/$TYPE.3 $BACKUPROOT/$TYPE.4; fi
      if [ -d $BACKUPROOT/$TYPE.2 ]; then mv $BACKUPROOT/$TYPE.2 $BACKUPROOT/$TYPE.3; fi
      if [ -d $BACKUPROOT/$TYPE.1 ]; then mv $BACKUPROOT/$TYPE.1 $BACKUPROOT/$TYPE.2; fi
      mv $BACKUPROOT/$TYPE.tmp $BACKUPROOT/$TYPE.1
      echo $lastexpectedbackup > $BACKUPROOT/.$TYPE
      if [ "$VERBOSE" == "true" ]; then echo "backup succeeded"; fi
    else
      if [ "$VERBOSE" == "true" ]; then echo "backup failed"; fi
      LIMIT=true
    fi
  else
    if [ "$VERBOSE" == "true" ]; then
      if [ "$TYPE" == "$PERIOD" ]; then
        echo "not performing a $TYPE sync backup"
      else
        echo "not performing a $TYPE link backup"
      fi
    fi
  fi
}

#fall-through implementation
function performhourlybackup()
{
  performbackup "hourly"
  if ! [ "$LIMIT" == "true" ]; then
    performdailybackup
  fi
}
function performdailybackup()
{
  performbackup "daily"
  if ! [ "$LIMIT" == "true" ]; then
    performweeklybackup
  fi
}
function performweeklybackup()
{
  performbackup "weekly"
  if ! [ "$LIMIT" == "true" ]; then
    performmonthlybackup
  fi
}
function performmonthlybackup()
{
  performbackup "monthly"
}

#start
case $PERIOD in
  "hourly")
    performhourlybackup    
    ;;
  "daily")
    performdailybackup
    ;;
  "weekly")    
    performweeklybackup
    ;;
  "monthly")
    performmonthlybackup
    ;;
esac

