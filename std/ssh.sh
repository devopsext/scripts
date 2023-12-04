#!/bin/bash

STD_SSH_OPTIONS=${STD_SSH_OPTIONS:=""}
STD_SSH_CONNECT_TIMEOUT=${STD_SSH_CONNECT_TIMEOUT:="10"}
STD_SSH_USER=${STD_SSH_USER:=""}
STD_SSH_PASSWORD=${STD_SSH_PASSWORD:=""}

function stdSshExecuteCommand() {

  local COMMAND_FILE="$1"
  local HOST="$2"
  local RESULT_NAME="$3"

  local OPTIONS="$STD_SSH_OPTIONS -o ConnectTimeout=$STD_SSH_CONNECT_TIMEOUT -o StrictHostKeyChecking=no -q -T"
  local USER="$STD_SSH_USER"
  
  export SSHPASS="$STD_SSH_PASSWORD"

  if [ -f "$COMMAND_FILE" ]; then

    TEMP_FILE="/tmp/$HOST.command"

    local VARIABLES=$(printenv | awk -F '=' '{printf "$%s\n", $1}' | xargs)

    envsubst "$VARIABLES" < $COMMAND_FILE > $TEMP_FILE

    sshpass -e ssh $OPTIONS $USER@$HOST < $TEMP_FILE &>/tmp/$HOST.output &

  else

    echo "$COMMAND_FILE" | sshpass -e ssh $OPTIONS $USER@$HOST &>/tmp/$HOST.output &
  fi

  local PID_HOST="$!^$HOST"
  eval "$RESULT_NAME=$PID_HOST"
}

function stdSshExecuteFile() {

  local COMMAND_FILE="$1"
  local HOST_FILE="$2"
  local RESULT_NAME="$3"

  local RESULT=""

  local LINE=""
  local END_OF_HOST_FILE=0

  if [ -f "$HOST_FILE" ]; then

    while true; do

      read -r LINE

      END_OF_HOST_FILE=$?

      if [ "$LINE" != "" ]; then

        local R="R$RANDOM"

        if [ -f "$LINE" ]; then

          stdSshExecuteFile "$COMMAND_FILE" "$LINE" "$R"
        else

          stdSshExecuteCommand "$COMMAND_FILE" "$LINE" "$R"
        fi
        RESULT+="${!R}|"
      fi

      if [ $END_OF_HOST_FILE != 0 ]; then
        break
      fi

     done < $HOST_FILE

  else

    for HOST in $HOST_FILE; do

      local R="R$RANDOM"
      stdSshExecuteCommand "$COMMAND_FILE" "$HOST" "$R"
      RESULT+="${!R}|"
    done
  fi

  RESULT="'"${RESULT}"'"

  eval "${RESULT_NAME}=${RESULT}"
}

function stdSshExecute() {

  local COMMAND_FILE="$1"
  if [ "$COMMAND_FILE" == "" ]; then
    echo "Empty Command."
  fi

  local HOST_FILE="$2"
  if [ "$HOST_FILE" == "" ]; then
    echo "Empty Host."
  fi

  local BANNER_OFFSET="$3"
  BANNER_OFFSET=${BANNER_OFFSET:="0"}

  echo "Processing $HOST_FILE..."

  local PID_HOSTS="PH$RANDOM"

  stdSshExecuteFile "$COMMAND_FILE" "$HOST_FILE" "$PID_HOSTS"

  PID_HOSTS="${!PID_HOSTS}"

  if [ "$PID_HOSTS" != "" ]; then

    echo "Processing done. Waiting for response..."

    local OLD_IFS="$IFS"

    IFS="|"

    for PID_HOST in $PID_HOSTS; do

      local PID="${PID_HOST%^*}"
      local HOST="${PID_HOST#*^}"

      wait $PID

      PID_EXIT_CODE=$?

      if [ $PID_EXIT_CODE -ne 0 ]; then

        echo "$HOST => failed: $COMMAND_FILE"

      else

        echo "$HOST => ok: $COMMAND_FILE"
      fi

      if [ -f "/tmp/$HOST.output" ]; then

        HEAD_OFFSET=$BANNER_OFFSET
        UBUNTU=$(cat /tmp/$HOST.output | head -1)

        if [[ "$UBUNTU" =~ ^"Welcome to Ubuntu" ]]; then

          HEAD_OFFSET=11
        fi

        cat /tmp/$HOST.output | tail -n+$HEAD_OFFSET

        rm /tmp/$HOST.output
      fi

    done

    IFS="$OLD_IFS"

    if [ -f "$TEMP_FILE" ]; then

      rm "$TEMP_FILE"
    fi

  else

    echo "Not found pids"
  fi
}

