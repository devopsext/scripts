#!/bin/bash

SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

STD_TERRAFORM_GIT_HOST=${STD_TERRAFORM_GIT_HOST:="$GITLAB_HOST"}
STD_TERRAFORM_GIT_LOGIN=${STD_TERRAFORM_GIT_LOGIN:="$GITLAB_LOGIN"}
STD_TERRAFORM_GIT_PASSWORD=${STD_TERRAFORM_GIT_PASSWORD:="$GITLAB_PASSWORD"}
STD_TERRAFORM_VARIABLES_PATTERN=${STD_TERRAFORM_VARIABLES_PATTERN:="STD_.*|K8S_.*|DOCKER_.*|CI_.*"}
STD_TERRAFORM_PREFIX=${STD_TERRAFORM_PREFIX:=""}

STD_TERRAFORM_CREATE_BEFORE_PREPARE=${STD_TERRAFORM_CREATE_BEFORE_PREPARE:=""}
STD_TERRAFORM_CREATE_AFTER_PREPARE=${STD_TERRAFORM_CREATE_AFTER_PREPARE:=""}

STD_TERRAFORM_DESTROY_BEFORE_PREPARE=${STD_TERRAFORM_DESTORY_BEFORE_PREPARE:=""}
STD_TERRAFORM_DESTROY_AFTER_PREPARE=${STD_TERRAFORM_DESTORY_AFTER_PREPARE:=""}

STD_TERRAFORM_BEFORE_CREATE=${STD_TERRAFORM_BEFORE_CREATE:=""}
STD_TERRAFORM_AFTER_CREATE=${STD_TERRAFORM_AFTER_CREATE:=""}
STD_TERRAFORM_BEFORE_DESTROY=${STD_TERRAFORM_BEFORE_DESTROY:=""}
STD_TERRAFORM_AFTER_DESTROY=${STD_TERRAFORM_AFTER_DESTROY:=""}
STD_TERRAFORM_TFSTATE=${STD_TERRAFORM_TFSTATE:="terraform.tfstate"}
STD_TERRAFORM_DIR=${STD_TERRAFORM_DIR:="terraform"}
STD_TERRAFORM_APPLY_DIR=${STD_TERRAFORM_APPLY_DIR:="$GITLAB_PIPELINE_ID"}
STD_TERRAFORM_STATE_DIR=${STD_TERRAFORM_STATE_DIR:="state"}
STD_TERRAFORM_LOAD_DIR=${STD_TERRAFORM_LOAD_DIR:="load"}

STD_TERRAFORM_APPLY_ARGS=${STD_TERRAFORM_APPLY_ARGS:=""}
STD_TERRAFORM_DESTROY_ARGS=${STD_TERRAFORM_DESTROY_ARGS:=""}

. $SCRIPTS_DIR/std/utils.sh
. $SCRIPTS_DIR/std/state.sh

function stdTerraformPrepare() {

  local APPLY_DIR="$1"
  local TERRAFORM_DIR="$2"

  stdLogInfo "Terraform version is: " && terraform version

  stdLogInfo "Preparing..."

  if [ ! -d "$APPLY_DIR" ]; then

    mkdir -p "$APPLY_DIR"
  fi

  if [ -d "$APPLY_DIR" ]; then

    echo -e "machine $STD_TERRAFORM_GIT_HOST\nlogin $STD_TERRAFORM_GIT_LOGIN\npassword $STD_TERRAFORM_GIT_PASSWORD" >> ~/.netrc

    mkdir -p "$APPLY_DIR/$TERRAFORM_DIR"

    cp -r "$TERRAFORM_DIR/" "$APPLY_DIR/"

    local TF_PREFIX="TF_VAR_"

    for NAME in $(printenv | awk -F '=' '{printf "%s\n", $1}' | grep -E "^$STD_TERRAFORM_PREFIX*" | xargs); do

      NAME_WO_PREFIX=${NAME/$STD_TERRAFORM_PREFIX/}
      TFVARNAME="$TF_PREFIX$NAME_WO_PREFIX"

      export ${TFVARNAME}="${!NAME}"
    done

    export VARIABLES=$(printenv | awk -F '=' '{printf "$%s\n", $1}' | grep -E "$STD_TERRAFORM_VARIABLES_PATTERN" | xargs)

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

function stdTerraformDryRun() {

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

    stdLogInfo "Terraform init..." && terraform init "$TERRAFORM_DIR/"

    local LOCAL_SERIAL=$(cat "$TERRAFORM_TFSTATE" 2>/dev/null | jq -r .serial)
    LOCAL_SERIAL=${LOCAL_SERIAL:="0"}

    local REPO_TERRAFORM_TFSTATE="$STD_TERRAFORM_LOAD_DIR/$TERRAFORM_FILE"

    local REPO_SERIAL=$(cat "$REPO_TERRAFORM_TFSTATE" 2>/dev/null | jq -r .serial)
    REPO_SERIAL=${REPO_SERIAL:="0"}

    stdLogInfo "Repo serial repo serial $REPO_SERIAL should be > than local serial $LOCAL_SERIAL to use repo"

    if [ $REPO_SERIAL -gt $LOCAL_SERIAL ]; then

      echo "Using repo state. Copying $REPO_TERRAFORM_TFSTATE to $TERRAFORM_TFSTATE"
      cp -f "$REPO_TERRAFORM_TFSTATE" "$TERRAFORM_TFSTATE" && echo "Done."
    fi

    stdLogInfo "Terraform validate..." && terraform validate "$TERRAFORM_DIR/"

    if [[ "$PROVIDER_ACTION" != "" ]]; then
      PROVIDER_ACTION="-$PROVIDER_ACTION"
    fi

    stdLogInfo "Terraform plan..."

    EXIT_FILE="$GITLAB_PIPELINE_ID.plan"

    EXIT_CODE=$(terraform plan -detailed-exitcode $PROVIDER_ACTION -state="$TERRAFORM_TFSTATE" "$TERRAFORM_DIR/" &>"$EXIT_FILE" || echo "$?")

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

function stdTerraformApply() {

  local APPLY_DIR="$1"
  local STATE_DIR="$2"
  local TERRAFORM_DIR="$3"
  local TERRAFORM_FILE="$4"
  local PROVIDER_ACTION="$5"

  stdLogInfo "Applying..."

  if [ -d "$APPLY_DIR" ]; then

    local TERRAFORM_TFSTATE="$STATE_DIR/$TERRAFORM_FILE"
    local TERRAFORM_DIR="$APPLY_DIR/$TERRAFORM_DIR"

    stdLogInfo "Terraform graph..." && terraform graph "$TERRAFORM_DIR/"

    PROVIDER_ACTION=${PROVIDER_ACTION:="apply"}
    ARGS=""

    stdLogInfo "Terraform $PROVIDER_ACTION..."

    if [[ "$PROVIDER_ACTION" == "apply" ]]; then
      stdCallback "$STD_TERRAFORM_BEFORE_CREATE"
      ARGS="$K8S_TERRAFORM_APPLY_ARGS"
    fi

    if [[ "$PROVIDER_ACTION" == "destroy" ]]; then
      stdCallback "$STD_TERRAFORM_BEFORE_DESTROY" "$TERRAFORM_TFSTATE"
      ARGS="$K8S_TERRAFORM_DESTROY_ARGS"
    fi

    terraform $PROVIDER_ACTION $ARGS -auto-approve -state="$TERRAFORM_TFSTATE" "$TERRAFORM_DIR/"

    if [[ "$PROVIDER_ACTION" == "apply" ]]; then
      stdCallback "$STD_TERRAFORM_AFTER_CREATE" "$TERRAFORM_TFSTATE"
    fi

    if [[ "$PROVIDER_ACTION" == "destroy" ]]; then
      stdCallback "$STD_TERRAFORM_AFTER_DESTROY" "$TERRAFORM_TFSTATE"
    fi

    stdStateSave "$STATE_DIR"
  else

    stdLogWarn "Apply directory is not found. Skipped."
  fi
}

function stdTerraformCreate() {

  DRY_RUN_EXIT_CODE=""

  if [ ! -d "$STD_TERRAFORM_STATE_DIR" ]; then
    mkdir -p "$STD_TERRAFORM_STATE_DIR" 
  fi
  stdCallback "$STD_TERRAFORM_CREATE_BEFORE_PREPARE" "$TERRAFORM_TFSTATE"
  stdTerraformPrepare "$STD_TERRAFORM_APPLY_DIR" "$STD_TERRAFORM_DIR"
  stdCallback "$STD_TERRAFORM_CREATE_AFTER_PREPARE" "$TERRAFORM_TFSTATE"

  stdStateLoad "$STD_TERRAFORM_LOAD_DIR"
  stdTerraformDryRun "$STD_TERRAFORM_APPLY_DIR" "$STD_TERRAFORM_STATE_DIR" "$STD_TERRAFORM_DIR" "$STD_TERRAFORM_TFSTATE" "DRY_RUN_EXIT_CODE"

  if [[ "$DRY_RUN_EXIT_CODE" == "2" ]]; then

    stdTerraformApply "$STD_TERRAFORM_APPLY_DIR" "$STD_TERRAFORM_STATE_DIR" "$STD_TERRAFORM_DIR" "$STD_TERRAFORM_TFSTATE"
  fi
}

function stdTerraformDestroy() {

  DRY_RUN_EXIT_CODE=""

  if [ ! -d "$STD_TERRAFORM_STATE_DIR" ]; then
    mkdir -p "$STD_TERRAFORM_STATE_DIR" 
  fi

  stdCallback "$STD_TERRAFORM_DESTROY_BEFORE_PREPARE" "$TERRAFORM_TFSTATE"
  stdTerraformPrepare "$STD_TERRAFORM_APPLY_DIR" "$STD_TERRAFORM_DIR"
  stdCallback "$STD_TERRAFORM_DESTROY_AFTER_PREPARE" "$TERRAFORM_TFSTATE"

  stdStateLoad "$STD_TERRAFORM_LOAD_DIR"
  stdTerraformDryRun "$STD_TERRAFORM_APPLY_DIR" "$STD_TERRAFORM_STATE_DIR" "$STD_TERRAFORM_DIR" "$STD_TERRAFORM_TFSTATE" "DRY_RUN_EXIT_CODE" "destroy"

  if [[ "$DRY_RUN_EXIT_CODE" == "2" ]]; then

   stdTerraformApply "$STD_TERRAFORM_APPLY_DIR" "$STD_TERRAFORM_STATE_DIR" "$STD_TERRAFORM_DIR" "$STD_TERRAFORM_TFSTATE" "destroy"
  fi
}
