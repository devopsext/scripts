#!/bin/bash

SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

K8S_RANCHER_API_URL=${K8S_RANCHER_API_URL:=""}
K8S_RANCHER_ACCESS_KEY=${K8S_RANCHER_ACCESS_KEY:=""}
K8S_RANCHER_SECRET_KEY=${K8S_RANCHER_SECRET_KEY:=""}
K8S_RANCHER_CLUSTER_NAME=${K8S_RANCHER_CLUSTER_NAME:="$GITLAB_PROJECT_NAME"} #TODO: Change default value to 'K8S_CLUSTER_NAME'
K8S_RANCHER_KUBE_CONFIG=${K8S_RANCHER_KUBE_CONFIG:="rancher.kube-config"}
K8S_RANCHER_CLUSTER_KUBE_CONFIG=${K8S_RANCHER_CLUSTER_KUBE_CONFIG:="cluster.kube-config"}
K8S_RANCHER_LOAD_DIR=${K8S_RANCHER_LOAD_DIR:="load"}
K8S_RANCHER_STATE_DIR=${K8S_RANCHER_STATE_DIR:="state"}
K8S_RANCHER_TFSTATE=${K8S_RANCHER_TFSTATE:="rancher.tfstate"}

. $SCRIPTS_DIR/std/utils.sh
. $SCRIPTS_DIR/k8s/state.sh

function k8sRancherApply() {

  local TERRAFORM_DIR="$1"
  local TERRAFORM_TFSTATE="$2"
  local PROVIDER_ACTION="$3"

  echo "Terraform version" && terraform version

  echo "Terraform init..." && terraform init "$TERRAFORM_DIR/"

  echo "Terraform validate..." && terraform validate "$TERRAFORM_DIR/"

  local ACTION="$PROVIDER_ACTION"

  if [[ "$ACTION" != "" ]]; then
    ACTION="-$ACTION"
  fi

  PROVIDER_ACTION=${PROVIDER_ACTION:="apply"}

  echo "Terraform plan..." && terraform plan $ACTION -state="$TERRAFORM_TFSTATE" "$TERRAFORM_DIR/"

  echo "Terraform graph..." && terraform graph "$TERRAFORM_DIR/"

  echo "Terraform $PROVIDER_ACTION..."

  terraform $PROVIDER_ACTION -auto-approve -state="$TERRAFORM_TFSTATE" "$TERRAFORM_DIR/"
}

function k8sRancherAttach() {

  local TMP_DIR=$(mktemp -d)

  local TERRAFORM_DIR="$TMP_DIR"
  local RANCHER_TFSTATE="$K8S_RANCHER_TFSTATE"
  local MAIN_TF="$TERRAFORM_DIR/main.tf"

  local RANCHER_API_URL="$K8S_RANCHER_API_URL"
  local RANCHER_ACCESS_KEY="$K8S_RANCHER_ACCESS_KEY"
  local RANCHER_SECRET_KEY="$K8S_RANCHER_SECRET_KEY"
  local RANCHER_CLUSTER_NAME="$K8S_RANCHER_CLUSTER_NAME"

  local LOAD_DIR="$K8S_RANCHER_LOAD_DIR"
  local STATE_DIR="$K8S_RANCHER_STATE_DIR"

  if [ ! -d "$STATE_DIR" ]; then
    mkdir -p "$STATE_DIR"
  fi

  cat <<EOF > ${MAIN_TF}
terraform {
  required_providers {
    rancher2 = {
      source = "rancher/rancher2"
      version = "1.10.6"
    }
  }
}

provider rancher2 {
  api_url = "${RANCHER_API_URL}"
  insecure = true
  access_key = "${RANCHER_ACCESS_KEY}"
  secret_key = "${RANCHER_SECRET_KEY}"
  version = "~> 1.5"
}
resource rancher2_cluster cluster {
  name = "${RANCHER_CLUSTER_NAME}"
}
output insecure_command {
  value = rancher2_cluster.cluster.cluster_registration_token[0].insecure_command
}
output kube_config {
  value = rancher2_cluster.cluster.kube_config
}
output cluster_id {
  value = rancher2_cluster.cluster.id
}
EOF

  k8sStateLoad "$LOAD_DIR"

  k8sRancherApply "$TERRAFORM_DIR" "$TERRAFORM_DIR/$RANCHER_TFSTATE"

  local CLUSTER_KUBE_CONFIG="$LOAD_DIR/$K8S_RANCHER_CLUSTER_KUBE_CONFIG"
  if [ ! -f "$CLUSTER_KUBE_CONFIG" ]; then

    CLUSTER_KUBE_CONFIG="$STATE_DIR/$K8S_RANCHER_CLUSTER_KUBE_CONFIG"
  fi

  stdLogDebug "CLUSTER_KUBE_CONFIG sourced from '$CLUSTER_KUBE_CONFIG'..."


  # we need to export KUBECONFIG="$CLUSTER_KUBE_CONFIG" before execute next line, by default => KUBECONFIG=state/cluster.kube-config
  #eval $(export KUBECONFIG="$CLUSTER_KUBE_CONFIG" && terraform output -state="$TERRAFORM_DIR/$RANCHER_TFSTATE" insecure_command)

  export KUBECONFIG="$CLUSTER_KUBE_CONFIG"
  eval $(terraform output -state="$TERRAFORM_DIR/$RANCHER_TFSTATE" insecure_command)

  terraform output -state="$TERRAFORM_DIR/$RANCHER_TFSTATE" kube_config > "$STATE_DIR/$K8S_RANCHER_KUBE_CONFIG"

  #Added for future
  #terraform output -state="$TERRAFORM_DIR/$RANCHER_TFSTATE" cluster_id > "$K8S_CLUSTER_RANCHER_CLUSTER_ID"

  cp -f "$TERRAFORM_DIR/$RANCHER_TFSTATE" "$STATE_DIR/"

  k8sStateSave "$STATE_DIR"
}

function k8sRancherDetach() {

  local TMP_DIR=$(mktemp -d)

  local TERRAFORM_DIR="$TMP_DIR"
  local RANCHER_TFSTATE="$K8S_RANCHER_TFSTATE"
  local MAIN_TF="$TERRAFORM_DIR/main.tf"

  local RANCHER_API_URL="$K8S_RANCHER_API_URL"
  local RANCHER_ACCESS_KEY="$K8S_RANCHER_ACCESS_KEY"
  local RANCHER_SECRET_KEY="$K8S_RANCHER_SECRET_KEY"
  local RANCHER_CLUSTER_NAME="$K8S_RANCHER_CLUSTER_NAME"

  local LOAD_DIR="$K8S_RANCHER_LOAD_DIR"
  local STATE_DIR="$K8S_RANCHER_STATE_DIR"

  if [ ! -d "$STATE_DIR" ]; then
    mkdir -p "$STATE_DIR"
  fi

  cat <<EOF > ${MAIN_TF}
provider rancher2 {
  api_url = "${RANCHER_API_URL}"
  insecure = true
  access_key = "${RANCHER_ACCESS_KEY}"
  secret_key = "${RANCHER_SECRET_KEY}"
  version = "~> 1.5"
}
resource rancher2_cluster cluster {
  name = "${RANCHER_CLUSTER_NAME}"
}
output insecure_command {
  value = rancher2_cluster.cluster.cluster_registration_token[0].insecure_command
}
output kube_config {
  value = rancher2_cluster.cluster.kube_config
}
output cluster_id {
  value = rancher2_cluster.cluster.id
}
EOF

  k8sStateLoad "$LOAD_DIR"

  local LOAD_RANCHER_TFSTATE="$LOAD_DIR/$RANCHER_TFSTATE"
  if [ -f "$LOAD_RANCHER_TFSTATE" ]; then

    cp -f "$LOAD_RANCHER_TFSTATE" "$TERRAFORM_DIR/$RANCHER_TFSTATE"

    k8sRancherApply "$TERRAFORM_DIR" "$TERRAFORM_DIR/$RANCHER_TFSTATE" "destroy"

    cp -f "$TERRAFORM_DIR/$RANCHER_TFSTATE" "$STATE_DIR/"

    k8sStateSave "$STATE_DIR"
  else

    echo "Not found $LOAD_RANCHER_TFSTATE"
  fi
}
