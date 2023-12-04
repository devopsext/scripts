#!/bin/bash

SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

K8S_RKE_NODE_USER=${K8S_RKE_NODE_USER:=""}
K8S_RKE_NODE_RSAKEY=${K8S_RKE_NODE_RSAKEY:=""}

. $SCRIPTS_DIR/std/ssh.sh


function k8sRKEAfterCreate() {

  echo "k8sRKEAfterCreate..."
}

function k8sRKEAfterDestroy() {

  local TERRAFORM_TFSTATE="$1"

  echo "State $TERRAFORM_TFSTATE"

  if [ -f "$TERRAFORM_TFSTATE" ]; then

    local IPS=$(cat "$TERRAFORM_TFSTATE" | jq -r '. | .resources[]? | select(.type=="rke_cluster") | .instances[]? | .attributes.nodes[]? | .address')

    if [[ "$IPS" != "" ]]; then


      local RSAKEY_FILE="/tmp/$K8S_RKE_NODE_USER"

      STD_SSH_USER="$K8S_RKE_NODE_USER"
      STD_SSH_OPTIONS="-i $RSAKEY_FILE"

      if [ -f "$RSAKEY_FILE" ]; then
        rm "$RSAKEY_FILE"
      fi

      echo "$K8S_RKE_NODE_RSAKEY" > "$RSAKEY_FILE" & chmod 600 "$RSAKEY_FILE"

      for IP in $IPS; do

        echo "Removing containers from $IP..."

        stdSshExecute 'sudo docker stop $(sudo docker ps -aq) && sudo docker rm -f $(sudo docker ps -aq)' "$IP"
      done
    else

      echo "Node's addresses are not found"
    fi
  else

    echo "State is not found"
  fi

}