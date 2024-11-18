#!/bin/bash

# Invocation of shakemap at 5, 10, 20, 30, 40, 50, 60 seconds after event detection

# This script is called when an event has been declared. 
# The following are passed as parameters: 
# - $1: The message string, 
# - $2: a flag (1=new event, 0=update event), 
# - $3: the EventID, 
# - $4: the arrival count 
# - $5: and the magnitude (optional when set) 

user="scalert"

exec > >(tee -a ~/.seiscomp/log/${user}-processing-info.log) 2>&1  # Redirect output to log file
export PS4='+ $(date "+%Y-%m-%d %H:%M:%S") '  # Add timestamp to each command trace
set -x  # Enable command tracing


# IF EVENT IS NOT NEW SKIP IT
#if [[ $2 -ne 1 ]] ; then
#    exit 1
#fi

# IF EVENT IS ALREADY BEING PROCESSED SKIP IT
PID=$$
ps -ef|grep -v $PID|grep $3|grep $0 && exit 1


# WAIT FOR STARTING EACH JOB
for DELAY in 5 10 20 30 40 50 60;
do

  # IF EVENT IS PROCESS ALREADY SKIP IT
  grep ${3}_${DELAY} ~/.seiscomp/log/${user}-processing-info.log | grep -v grep && echo ${3}_${DELAY} was already processed && exit 1
  
  ( echo sleep $DELAY seconds before running shakemap ... && \
    sleep  $DELAY && \
    ORGID=$( scxmldump -E ${3} -f|awk -F"[<>]" '$0~/preferredOriginID/{printf "%s",$3}' ) && \
    /home/sysop/miniconda/bin/python /home/sysop/.seiscomp/scripts/run_events/originbased_make_rupturejson_and_allxmlinput_fromdb.py ${3}_${DELAY} $ORGID ) &

done
