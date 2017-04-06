#!/bin/bash

# Rotates rsync-based backup snapshots
# Idea: http://www.mikerubel.org/computers/rsync_snapshots/

# Usage: rotate-snapshots -l level -n num source_snapshot
# Examples:
#   rotate-snapshots -l daily -n 7 $HOME/backups/snapshot
#   rotate-snapshots -l weekly -n 4 $HOME/backups/daily[.6]
#   rotate-snapshots -l monthly -n 99 $HOME/backups/weekly[.3]

PATH=/bin:/usr/bin

# Configuration
LEVEL='daily'
NUM=7

DEBUG=

LOG_FACILITY="user"
LOG_TAG="$(basename $0)"

# Print a debug message
function debug {
    if [ ! -z $DEBUG ]; then
        echo "Debug: $1"
    fi
}

# Print an error message
function error {
    printf "%s\n" "$*" >&2
}

function log {
    # logger -p $LOG_FACILITY.$1 -t $LOG_TAG "$2"
    echo "$LOG_FACILITY.$1 $LOG_TAG: $2"
}

# Print a usage message
function usage {
    echo "$(basename $0) -- create and rotate backups from an rsync-based source backup snapshot"
    echo "Usage: $(basename $0) [-l level] [-n num] source_snapshot"
    echo "  -l level -- define level (= name prefix) for the snapshots"
    echo "  -n num   -- define number of snapshots to keep"
    echo "  -h       -- display help"
    #sed -n 's/\(.\))\ #\(.*\)/-\1  --  \2/p' $0
    exit 0
}

# Return the absolute path of an existing file for directory
# See http://stackoverflow.com/questions/3915040/bash-fish-command-to-print-absolute-path-to-a-file
function abspath {
    if [ -d $1 ]; then
        echo "$(cd $1 && pwd)"
    else
        if [ -d "$(dirname "$1")" ]; then
            echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
        fi
    fi
}

# Clone a tree using hard-links
function copy {
    debug "cd $1 && find . -print | cpio -dpl $2"
    cd $1 && find . -print | cpio -dpl $2 2> /dev/null
}

# TODO: Parse command line
[ $# -eq 0 ] && usage

while getopts ":vl:n:" arg; do
    case $arg in
        l) # level (=name prefix for the snapshots)
            LEVEL=${OPTARG}
            debug "level is $LEVEL"
            ;;
        n) # number of snapshots to keep
            NUM=${OPTARG}
            debug "num is $NUM"
            ;;
        v) # turn on debug messages
            DEBUG=1
            ;;
        h) # help.
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 1
            ;;

    esac
done
shift $((OPTIND-1))

# Enforce, that the argument 'source_snapshot' is an absolute path
SOURCE=$(abspath $1)

# If source snapshot cannot be found, look for candiates by attaching suffixes .99 to .0
if [ ! -d "$SOURCE" ]; then
    debug "Source snapshot $1 does not exist (or is not a directory), looking for similar candidates"
    for ((i=99; i >= 0; i-- )) do
        # debug "Check for 'source' in $(abspath "$1.$i")"
        if [ -d "$(abspath "$1.$i")" ]; then
            SOURCE=$(abspath $1.$i)
            break;
        fi
    done
    if [ ! -d $SOURCE ]; then
        error "Source snapshot $1 not found."
        exit 1
    fi
fi
debug "Source snapshot is $SOURCE"

# Base directory for snapshots
SNAPSHOT_ROOT=`dirname $SOURCE`

START_TIME=`date +%s`

# Do the actual rotation
N=$(($NUM-1))

# ...by removing the oldest snapshot
if  [ -d $SNAPSHOT_ROOT/$LEVEL.$N ]; then
    debug "Removing oldest snapshot in $SNAPSHOT_ROOT/$LEVEL.$N"
    rm -rf $SNAPSHOT_ROOT/$LEVEL.$N
fi

# ...rotating the middle ones
for (( i=N; i > 0; i-- )) do
    if [ -d $SNAPSHOT_ROOT/$LEVEL.$((i-1)) ]; then
        debug "Moving snpashot $SNAPSHOT_ROOT/$LEVEL.$((i-1)) to $SNAPSHOT_ROOT/$LEVEL.$i"
        mv $SNAPSHOT_ROOT/$LEVEL.$((i-1)) $SNAPSHOT_ROOT/$LEVEL.$i
    fi
done

#...and cloning the source snapshot
if [ -d $SOURCE ] ; then
    debug "Cloning $SOURCE to $SNAPSHOT_ROOT/$LEVEL.0 with hard-links"
    copy $SOURCE $SNAPSHOT_ROOT/$LEVEL.0
    # TODO: Error handling if cloning fails
    if [ ! $? -eq 0 ]; then
        error "Could not clone source snapshot $1."
        exit 1
    fi
fi;

# Log successful execution
EXECUTION_TIME=$(expr `date +%s` - $START_TIME)
log "INFO" "Rotation of $LEVEL snapshots completed in $EXECUTION_TIME s"
