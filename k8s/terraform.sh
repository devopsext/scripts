#!/bin/bash

SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

K8S_TERRAFORM_GIT_HOST=${K8S_TERRAFORM_GIT_HOST:="$GITLAB_HOST"}
K8S_TERRAFORM_GIT_LOGIN=${K8S_TERRAFORM_GIT_LOGIN:="$GITLAB_LOGIN"}
K8S_TERRAFORM_GIT_PASSWORD=${K8S_TERRAFORM_GIT_PASSWORD:="$GITLAB_PASSWORD"}
K8S_TERRAFORM_VARIABLES_PATTERN=${K8S_TERRAFORM_VARIABLES_PATTERN:="K8S_.*|DOCKER_.*|CI_.*"}
K8S_TERRAFORM_PREFIX=${K8S_TERRAFORM_PREFIX:="K8S_CLUSTER_"}

K8S_TERRAFORM_CREATE_BEFORE_PREPARE=${K8S_TERRAFORM_CREATE_BEFORE_PREPARE:=""}
K8S_TERRAFORM_CREATE_AFTER_PREPARE=${K8S_TERRAFORM_CREATE_AFTER_PREPARE:=""}

K8S_TERRAFORM_DESTROY_BEFORE_PREPARE=${K8S_TERRAFORM_DESTORY_BEFORE_PREPARE:=""}
K8S_TERRAFORM_DESTROY_AFTER_PREPARE=${K8S_TERRAFORM_DESTORY_AFTER_PREPARE:=""}

K8S_TERRAFORM_BEFORE_CREATE=${K8S_TERRAFORM_BEFORE_CREATE:=""}
K8S_TERRAFORM_AFTER_CREATE=${K8S_TERRAFORM_AFTER_CREATE:=""}
K8S_TERRAFORM_BEFORE_DESTROY=${K8S_TERRAFORM_BEFORE_DESTROY:=""}
K8S_TERRAFORM_AFTER_DESTROY=${K8S_TERRAFORM_AFTER_DESTROY:=""}
K8S_TERRAFORM_TFSTATE=${K8S_TERRAFORM_TFSTATE:="terraform.tfstate"}
K8S_TERRAFORM_DIR=${K8S_TERRAFORM_DIR:="terraform"}
K8S_TERRAFORM_APPLY_DIR=${K8S_TERRAFORM_APPLY_DIR:="$GITLAB_PIPELINE_ID"}
K8S_TERRAFORM_STATE_DIR=${K8S_TERRAFORM_STATE_DIR:="state"}
K8S_TERRAFORM_LOAD_DIR=${K8S_TERRAFORM_LOAD_DIR:="load"}

K8S_TERRAFORM_APPLY_ARGS=${K8S_TERRAFORM_APPLY_ARGS:=""}
K8S_TERRAFORM_DESTROY_ARGS=${K8S_TERRAFORM_DESTROY_ARGS:=""}

. $SCRIPTS_DIR/std/utils.sh
. $SCRIPTS_DIR/k8s/state.sh

function k8sTerraformPrepare() {

  local APPLY_DIR="$1"
  local TERRAFORM_DIR="$2"

  stdLogInfo "Terraform version is: " && terraform version

  stdLogInfo "Preparing..."

  if [ ! -d "$APPLY_DIR" ]; then

    mkdir -p "$APPLY_DIR"
  fi

  if [ -d "$APPLY_DIR" ]; then

    echo -e "machine $K8S_TERRAFORM_GIT_HOST\nlogin $K8S_TERRAFORM_GIT_LOGIN\npassword $K8S_TERRAFORM_GIT_PASSWORD" >> ~/.netrc

    mkdir -p "$APPLY_DIR/$TERRAFORM_DIR"

    cp -r "$TERRAFORM_DIR/" "$APPLY_DIR/"

    local TF_PREFIX="TF_VAR_"

    for NAME in $(printenv | awk -F '=' '{printf "%s\n", $1}' | grep -E "^$K8S_TERRAFORM_PREFIX*" | xargs); do

      NAME_WO_PREFIX=${NAME/$K8S_TERRAFORM_PREFIX/}
      TFVARNAME="$TF_PREFIX$NAME_WO_PREFIX"

      export ${TFVARNAME}="${!NAME}"
    done

    export VARIABLES=$(printenv | awk -F '=' '{printf "$%s\n", $1}' | grep -E "$K8S_TERRAFORM_VARIABLES_PATTERN" | xargs)

    local EXTENTION=".template"

    for FILE in $(find "$APPLY_DIR/$TERRAFORM_DIR/" -maxdepth 1 -type f -name "*.tf"); do

      mv "$FILE" "$FILE.$EXTENTION"
      envsubst "$VARIABLES" < "$FILE.$EXTENTION" > "$FILE"
      rm -f "$FILE.$EXTENTION"
    done

  else

    stdLogWarn "Apply directory is not found. Skipped."
  fi
}

function k8sTerraformDryRun() {

  local APPLY_DIR="$1"
  local STATE_DIR="$2"
  local TERRAFORM_DIR="$3"
  local TERRAFORM_FILE="$4"
  local RETURN="$5"
  local PROVIDER_ACTION="$6"

  stdLogInfo "Dry running..."

  if [ -d "$APPLY_DIR" ]; then

    local TERRAFORM_TFSTATE="$STATE_DIR/$TERRAFORM_FILE"
    local TERRAFORM_DIR="$APPLY_DIR/$TERRAFORM_DIR"

    stdLogInfo "Terraform init..." && terraform -chdir="$TERRAFORM_DIR/" init

    local LOCAL_SERIAL=$(cat "$TERRAFORM_TFSTATE" 2>/dev/null | jq -r .serial)
    LOCAL_SERIAL=${LOCAL_SERIAL:="0"}

    local REPO_TERRAFORM_TFSTATE="$K8S_TERRAFORM_LOAD_DIR/$TERRAFORM_FILE"

    local REPO_SERIAL=$(cat "$REPO_TERRAFORM_TFSTATE" 2>/dev/null | jq -r .serial)
    REPO_SERIAL=${REPO_SERIAL:="0"}

    stdLogInfo "Repo serial repo serial $REPO_SERIAL should be > than local serial $LOCAL_SERIAL to use repo"

    if [ $REPO_SERIAL -gt $LOCAL_SERIAL ]; then

      echo "Using repo state. Copying $REPO_TERRAFORM_TFSTATE to $TERRAFORM_TFSTATE"
      cp -f "$REPO_TERRAFORM_TFSTATE" "$TERRAFORM_TFSTATE" && echo "Done."
    fi

    stdLogInfo "Terraform validate..." && terraform -chdir="$TERRAFORM_DIR/" validate

    if [[ "$PROVIDER_ACTION" != "" ]]; then
      PROVIDER_ACTION="-$PROVIDER_ACTION"
    fi

    stdLogInfo "Terraform plan..."

    EXIT_FILE="$GITLAB_PIPELINE_ID.plan"

    EXIT_CODE=$(terraform -chdir="$TERRAFORM_DIR/" plan -detailed-exitcode $PROVIDER_ACTION -state="$TERRAFORM_TFSTATE" &>"$EXIT_FILE" || echo "$?")

    if [[ "$EXIT_CODE" == "" ]]; then
      EXIT_CODE=0
    fi

    cat "$EXIT_FILE" && rm -f "$EXIT_FILE"

    stdLogInfo "Plan exit code => $EXIT_CODE"
    eval "$RETURN=$EXIT_CODE"
  else

    stdLogWarn "Apply directory is not found. Skipped."
  fi
}

function k8sTerraformApply() {

  local APPLY_DIR="$1"
  local STATE_DIR="$2"
  local TERRAFORM_DIR="$3"
  local TERRAFORM_FILE="$4"
  local PROVIDER_ACTION="$5"

  stdLogInfo "Applying..."

  if [ -d "$APPLY_DIR" ]; then

    local TERRAFORM_TFSTATE="$STATE_DIR/$TERRAFORM_FILE"
    local TERRAFORM_DIR="$APPLY_DIR/$TERRAFORM_DIR"

    stdLogInfo "Terraform graph..." && terraform -chdir="$TERRAFORM_DIR/" graph

    PROVIDER_ACTION=${PROVIDER_ACTION:="apply"}
    ARGS=""

    stdLogInfo "Terraform $PROVIDER_ACTION..."

    if [[ "$PROVIDER_ACTION" == "apply" ]]; then
      stdCallback "$K8S_TERRAFORM_BEFORE_CREATE"
      ARGS="$K8S_TERRAFORM_APPLY_ARGS"
    fi

    if [[ "$PROVIDER_ACTION" == "destroy" ]]; then
      stdCallback "$K8S_TERRAFORM_BEFORE_DESTROY" "$TERRAFORM_TFSTATE"
      ARGS="$K8S_TERRAFORM_DESTROY_ARGS"
    fi

    terraform -chdir="$TERRAFORM_DIR/" $PROVIDER_ACTION $ARGS -auto-approve -state="$TERRAFORM_TFSTATE"

    if [[ "$PROVIDER_ACTION" == "apply" ]]; then
      stdCallback "$K8S_TERRAFORM_AFTER_CREATE" "$TERRAFORM_TFSTATE"
    fi

    if [[ "$PROVIDER_ACTION" == "destroy" ]]; then
      stdCallback "$K8S_TERRAFORM_AFTER_DESTROY" "$TERRAFORM_TFSTATE"
    fi

    k8sStateSave "$STATE_DIR"
  else

    stdLogWarn "Apply directory is not found. Skipped."
  fi
}

function k8sTerraformCreate() {

  DRY_RUN_EXIT_CODE=""

  if [ ! -d "$K8S_TERRAFORM_STATE_DIR" ]; then
    mkdir -p "$K8S_TERRAFORM_STATE_DIR" 
  fi
  stdCallback "$K8S_TERRAFORM_CREATE_BEFORE_PREPARE" "$TERRAFORM_TFSTATE"
  k8sTerraformPrepare "$K8S_TERRAFORM_APPLY_DIR" "$K8S_TERRAFORM_DIR"
  stdCallback "$K8S_TERRAFORM_CREATE_AFTER_PREPARE" "$TERRAFORM_TFSTATE"

  k8sStateLoad "$K8S_TERRAFORM_LOAD_DIR"
  k8sTerraformDryRun "$K8S_TERRAFORM_APPLY_DIR" "$K8S_TERRAFORM_STATE_DIR" "$K8S_TERRAFORM_DIR" "$K8S_TERRAFORM_TFSTATE" "DRY_RUN_EXIT_CODE"

  if [[ "$DRY_RUN_EXIT_CODE" == "2" ]]; then

    k8sTerraformApply "$K8S_TERRAFORM_APPLY_DIR" "$K8S_TERRAFORM_STATE_DIR" "$K8S_TERRAFORM_DIR" "$K8S_TERRAFORM_TFSTATE"
  fi
}

function k8sTerraformDestroy() {

  DRY_RUN_EXIT_CODE=""

  if [ ! -d "$K8S_TERRAFORM_STATE_DIR" ]; then
    mkdir -p "$K8S_TERRAFORM_STATE_DIR" 
  fi

  stdCallback "$K8S_TERRAFORM_DESTROY_BEFORE_PREPARE" "$TERRAFORM_TFSTATE"
  k8sTerraformPrepare "$K8S_TERRAFORM_APPLY_DIR" "$K8S_TERRAFORM_DIR"
  stdCallback "$K8S_TERRAFORM_DESTROY_AFTER_PREPARE" "$TERRAFORM_TFSTATE"

  k8sStateLoad "$K8S_TERRAFORM_LOAD_DIR"
  k8sTerraformDryRun "$K8S_TERRAFORM_APPLY_DIR" "$K8S_TERRAFORM_STATE_DIR" "$K8S_TERRAFORM_DIR" "$K8S_TERRAFORM_TFSTATE" "DRY_RUN_EXIT_CODE" "destroy"

  if [[ "$DRY_RUN_EXIT_CODE" == "2" ]]; then

   k8sTerraformApply "$K8S_TERRAFORM_APPLY_DIR" "$K8S_TERRAFORM_STATE_DIR" "$K8S_TERRAFORM_DIR" "$K8S_TERRAFORM_TFSTATE" "destroy"
  fi
}
