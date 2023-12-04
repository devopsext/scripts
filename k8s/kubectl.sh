#!/bin/bash

SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

K8S_KUBECTL_VARIABLES_PATTERN=${K8S_KUBECTL_VARIABLES_PATTERN:="K8S_.*|DOCKER_.*|CI_.*"}
K8S_KUBECTL_NAMESPACE=${K8S_KUBECTL_NAMESPACE:=""}
K8S_KUBECTL_KUBE_CONFIG=${K8S_KUBECTL_KUBE_CONFIG:="cluster.kube-config"}
K8S_KUBECTL_LOAD_DIR=${K8S_KUBECTL_LOAD_DIR:="load"}
K8S_KUBECTL_STATE_DIR=${K8S_KUBECTL_STATE_DIR:="state"}
K8S_KUBECTL_BACKUP_DIR=${K8S_KUBECTL_BACKUP_DIR:="backup"}
K8S_KUBECTL_RESTORE_DIR=${K8S_KUBECTL_RESTORE_DIR:="restore"}

K8S_KUBECTL_HELM_DIR=${K8S_KUBECTL_HELM_DIR:="helm"}
K8S_KUBECTL_HELM_ARGS=${K8S_KUBECTL_HELM_ARGS:=""}
K8S_KUBECTL_HELM_RELEASE_NAME=${K8S_KUBECTL_HELM_RELEASE_NAME:=""}
K8S_KUBECTL_HELM_VALUES_FILE=${K8S_KUBECTL_HELM_VALUES_FILE:="$GITLAB_JOB_NAME"}

K8S_KUBECTL_ENVTPL_ENABLED=${K8S_KUBECTL_ENVTPL_ENABLED:="true"}

K8S_KUBECTL_PROJECT_NAME=${K8S_KUBECTL_PROJECT_NAME:="$GITLAB_PROJECT_NAME"}

K8S_KUBECTL_DEPLOY_FILE=${K8S_KUBECTL_DEPLOY_FILE:="$GITLAB_JOB_ID.yml"}
K8S_KUBECTL_KUSTOMIZER_DIR=${K8S_KUBECTL_KUSTOMIZER_DIR:="kustomizer"}
K8S_KUBECTL_KUSTOMIZER_PATCH_DIR=${K8S_KUBECTL_KUSTOMIZER_PATCH_DIR:="$GITLAB_JOB_NAME"}
K8S_KUBECTL_KUSTOMIZER_FILE=${K8S_KUBECTL_KUSTOMIZER_FILE:="kustomization.yaml"}
K8S_KUBECTL_KUSTOMZIER_BUILD_FLAGS=${K8S_KUBECTL_KUSTOMZIER_BUILD_FLAGS:=""}
K8S_KUBECTL_APPLY_YML=${K8S_KUBECTL_APPLY_YML:="$GITLAB_JOB_NAME.yml"}
K8S_KUBECTL_DELETE_YML=${K8S_KUBECTL_DELETE_YML:="$GITLAB_JOB_NAME.yml"}
K8S_KUBECTL_DRY_RUN_ONLY=${K8S_KUBECTL_DRY_RUN_ONLY:="false"}

K8S_KUBECTL_BEFORE_APPLY=${K8S_KUBECTL_BEFORE_APPLY:=""}
K8S_KUBECTL_AFTER_APPLY=${K8S_KUBECTL_AFTER_APPLY:=""}
K8S_KUBECTL_BEFORE_CUSTOMIZE=${K8S_KUBECTL_BEFORE_CUSTOMIZE:=""}
K8S_KUBECTL_AFTER_CUSTOMIZE=${K8S_KUBECTL_AFTER_CUSTOMIZE:=""}

K8S_KUBECTL_KUSTOMIZE_IMAGE=${K8S_KUBECTL_KUSTOMIZE_IMAGE:=""}
K8S_KUBECTL_KUSTOMIZE_LABEL=${K8S_KUBECTL_KUSTOMIZE_LABEL:=""}
K8S_KUBECTL_KUSTOMIZE_ANNOTATION=${K8S_KUBECTL_KUSTOMIZE_ANNOTATION:=""}
K8S_KUBECTL_KUSTOMIZE_NAMESUFFIX=${K8S_KUBECTL_KUSTOMIZE_NAMESUFFIX:=""}
K8S_KUBECTL_KUSTOMIZE_NAMEPREFIX=${K8S_KUBECTL_KUSTOMIZE_NAMEPREFIX:=""}

. $SCRIPTS_DIR/std/utils.sh
. $SCRIPTS_DIR/k8s/state.sh
. $SCRIPTS_DIR/k8s/helm.sh

function k8sKubectlRender() {

  local HELM_DIR="$1"
  local VALUES="$HELM_DIR/$2"
  local APPLY_FILE="$3"
  local valuesContent=""

  if [[ -z $(which envtpl) ]] && [[ "$K8S_KUBECTL_ENVTPL_ENABLED" == "true" ]]; then
    stdLogWarn "'envtpl' is not installed. Rendering with envtpl will be skipped..."
  fi

  if [ -f "$HELM_DIR/Chart.yaml" ]; then

    stdLogInfo "Using helm for $HELM_DIR/Chart.yaml"

    export VARIABLES=$(printenv | awk -F '=' '{printf "$%s\n", $1}' | grep -E "$K8S_KUBECTL_VARIABLES_PATTERN" | xargs)

    if [ -f "$VALUES" ]; then

      stdLogInfo "Using values from $VALUES ..."

      mv "$VALUES" "$VALUES.template"
      envsubst "$VARIABLES" <"$VALUES.template" >"$VALUES" || return 1

      if [[ -n $(which envtpl) ]] && [[ "$K8S_KUBECTL_ENVTPL_ENABLED" == "true" ]]; then
        stdLogInfo "Trying to render '$VALUES' with envtpl..."
        envtpl "$VALUES" -o "$VALUES" -m zero || stdLogWarn "File '$VALUES' can't be rendered properly with envtpl..."
      fi

      valuesContent=$(cat "$VALUES")
      stdDebugSmallSeparator
      stdLogDebug "'$VALUES' content:\n$valuesContent"
      stdDebugSmallSeparator

      stdLogInfo "Rendering $VALUES in $HELM_DIR/ (name: $K8S_KUBECTL_HELM_RELEASE_NAME, namespace: $K8S_KUBECTL_NAMESPACE, args: $K8S_KUBECTL_HELM_ARGS)..."

      local namespace="$K8S_KUBECTL_NAMESPACE"
      if [[ "$namespace" != "" ]]; then
        namespace="--namespace $namespace"
      fi

      if k8sHelm2Exists; then
        stdLogInfo "Using helm 2..."
        helm template -f "$VALUES" "$HELM_DIR/" --name "$K8S_KUBECTL_HELM_RELEASE_NAME" $namespace $K8S_KUBECTL_HELM_ARGS 1>"$APPLY_FILE"
      elif k8sHelm3Exists; then
        stdLogInfo "Using helm 3..."
        helm template "$K8S_KUBECTL_HELM_RELEASE_NAME" -f "$VALUES" "$HELM_DIR/" $namespace $K8S_KUBECTL_HELM_ARGS 1>"$APPLY_FILE"
      fi

      rm -f "$VALUES.template"
    else

      VALUES="$HELM_DIR/values.yaml"

      if [ -f "$VALUES" ]; then

        stdLogInfo "Using values from $VALUES ..."

        mv "$VALUES" "$VALUES.template"
        envsubst "$VARIABLES" <"$VALUES.template" >"$VALUES" || return 1

        if [[ -n $(which envtpl) ]] && [[ "$K8S_KUBECTL_ENVTPL_ENABLED" == "true" ]]; then
          stdLogInfo "Trying to render '$VALUES' with envtpl..."
          envtpl "$VALUES" -o "$VALUES" -m zero || stdLogWarn "File '$VALUES' can't be rendered properly with envtpl..."
        fi

        valuesContent=$(cat "$VALUES")
        stdDebugSmallSeparator
        stdLogDebug "'$VALUES' content:\n$valuesContent"
        stdDebugSmallSeparator

        stdLogInfo "Rendering $HELM_DIR/ with $VALUES (name: $K8S_KUBECTL_HELM_RELEASE_NAME, namespace: $K8S_KUBECTL_NAMESPACE, args: $K8S_KUBECTL_HELM_ARGS)..."

        local namespace="$K8S_KUBECTL_NAMESPACE"
        if [[ "$namespace" != "" ]]; then
          namespace="--namespace $namespace"
        fi

        if k8sHelm2Exists; then
          stdLogInfo "Using helm 2..."
          helm template -f "$VALUES" "$HELM_DIR/" --name "$K8S_KUBECTL_HELM_RELEASE_NAME" $namespace $K8S_KUBECTL_HELM_ARGS 1>"$APPLY_FILE"
        elif k8sHelm3Exists; then
          stdLogInfo "Using helm 3..."
          helm template "$K8S_KUBECTL_HELM_RELEASE_NAME" -f "$VALUES" "$HELM_DIR/" $namespace $K8S_KUBECTL_HELM_ARGS 1>"$APPLY_FILE"
        fi

        rm -f "$VALUES.template"
      else

        stdLogInfo "Not found any helm values, skipping..."
      fi
    fi

  elif [[ -n $(which envtpl) ]] && [[ "$K8S_KUBECTL_ENVTPL_ENABLED" == "true" ]]; then #Not a helm chart trying to render all files with go templates via envtpl
    #Which directory should be rendered
    local renderDir=""
    if [[ -d "$K8S_KUBECTL_KUSTOMIZER_DIR" ]]; then
      renderDir="$K8S_KUBECTL_KUSTOMIZER_DIR"
    else
      renderDir="./"
    fi

    stdLogInfo "Trying to render '$renderDir' folder recursively with envtpl..."

    find "$renderDir" -type f | while read file; do
      #envtpl $file -o $file -m zero  || if [ ! $? -eq 0 ]; then echo "File '$file' can't be rendered properly with envtpl..."; fi
      envtpl $file -o $file -m zero
    done

  else #Nothing to do
    stdLogInfo "Not found any renders or rendering with envtpl disabled, skipping..."
  fi
}

function k8sKubectlCustomize() {
  local KUSTOMIZER_DIR="$1"
  local KUSTOMIZER_FILE="$KUSTOMIZER_DIR/$2"
  local APPLY_FILE="$3"

  if [ -f "$KUSTOMIZER_FILE" ]; then

    stdLogInfo "Using kustomize for $KUSTOMIZER_FILE"

    local PWD_OLD="$PWD"

    export VARIABLES=$(printenv | awk -F '=' '{printf "$%s\n", $1}' | grep -E "$K8S_KUBECTL_VARIABLES_PATTERN" | xargs)

    mv "$KUSTOMIZER_FILE" "$KUSTOMIZER_FILE.template"
    envsubst "$VARIABLES" <"$KUSTOMIZER_FILE.template" >"$KUSTOMIZER_FILE" || return 1

    if [ ! -f "$APPLY_FILE" ]; then
      touch "$APPLY_FILE"
    fi

    rm -f "$KUSTOMIZER_FILE.template"

    cp -f "$APPLY_FILE" "$KUSTOMIZER_DIR/" && cd "$KUSTOMIZER_DIR/"

    kustomize edit add resource "$APPLY_FILE" || return 1

    if [[ "$K8S_KUBECTL_NAMESPACE" != "" ]]; then
      kustomize edit set namespace "$K8S_KUBECTL_NAMESPACE" || return 1
    fi

    if [[ "$K8S_KUBECTL_KUSTOMIZE_IMAGE" != "" ]]; then

      if [[ -z $(echo "$K8S_KUBECTL_KUSTOMIZE_IMAGE" | grep -Ei '\=') ]]; then #$K8S_KUBECTL_KUSTOMIZE_IMAGE="nginx:latest"
        kustomize edit set image image="$K8S_KUBECTL_KUSTOMIZE_IMAGE" || return 1

      else #$K8S_KUBECTL_KUSTOMIZE_IMAGE="image1=nginx:latest" OR "image1=nginx:latest,image2=debian:10,..."
        local imagePlaceholder=""
        local imageName=""
        for item in ${K8S_KUBECTL_KUSTOMIZE_IMAGE//,/ }; do
          :
          if [[ -z "$item" || "$item" == "" ]]; then
            continue
          fi

          imagePlaceholder=$(echo "$item" | awk -F '=' '{printf "%s",$1 }')
          imageName=$(echo "$item" | awk -F '=' '{printf "%s",$2 }')
          echo "$imagePlaceholder=$imageName"
          kustomize edit set image "$imagePlaceholder=$imageName" || return 1
        done
      fi
    fi

    if [[ "$K8S_KUBECTL_KUSTOMIZE_LABEL" != "" ]]; then
      kustomize edit add label -f "$K8S_KUBECTL_KUSTOMIZE_LABEL"
    fi

    if [[ "$K8S_KUBECTL_KUSTOMIZE_ANNOTATION" != "" ]]; then
      kustomize edit add annotation -f "$K8S_KUBECTL_KUSTOMIZE_ANNOTATION"
    fi

    if [[ "$K8S_KUBECTL_KUSTOMIZE_NAMESUFFIX" != "" ]]; then
      kustomize edit set namesuffix -- "$K8S_KUBECTL_KUSTOMIZE_NAMESUFFIX"
    fi

    if [[ "$K8S_KUBECTL_KUSTOMIZE_NAMEPREFIX" != "" ]]; then
      kustomize edit set nameprefix -- "$K8S_KUBECTL_KUSTOMIZE_NAMEPREFIX"
    fi

    cd "$PWD_OLD" && cat "$KUSTOMIZER_FILE"

    if [[ "$K8S_KUBECTL_KUSTOMZIER_BUILD_FLAGS" == "" ]]; then
      kustomize build "$KUSTOMIZER_DIR/" -o "$APPLY_FILE" || return 1
    else
      #kustomize build "$KUSTOMIZER_DIR/" $K8S_KUBECTL_KUSTOMZIER_BUILD_FLAGS -o "$APPLY_FILE" || return 1
      local command="kustomize build '$KUSTOMIZER_DIR/' $K8S_KUBECTL_KUSTOMZIER_BUILD_FLAGS -o '$APPLY_FILE'"
      stdLogTrace "kustomize build command:\n$command"
      eval "$command" || return 1
    fi

    stdCallback "$K8S_KUBECTL_AFTER_CUSTOMIZE" "$APPLY_FILE"

  else

    stdLogInfo "Not found customize file '$KUSTOMIZER_FILE', skipping..."
  fi
}

function k8sKubectlDryRun() {

  local APPLY_FILE="$1"
  local LOAD_DIR="$2"
  local STATE_DIR="$3"
  local applyFileContent=""

  if [ -f "$APPLY_FILE" ]; then

    local LOAD_KUBE_CONFIG="$LOAD_DIR/$K8S_KUBECTL_KUBE_CONFIG"
    if [ -f "$LOAD_KUBE_CONFIG" ]; then

      stdLogInfo "Copying '$LOAD_KUBE_CONFIG' to '$STATE_DIR/'..." && cp -f "$LOAD_KUBE_CONFIG" "$STATE_DIR/"
    fi

    stdLogInfo "Dry running $APPLY_FILE..."

    stdDebugSmallSeparator
    applyFileContent=$(cat "$APPLY_FILE")
    stdLogDebug "Apply file content:\n$applyFileContent"
    stdDebugSmallSeparator

    kubectl apply -f "$APPLY_FILE" --dry-run || return 1
  else

    stdLogErr "Apply file is not found!"
    return 1
  fi
}

function k8sKubectlApplyYaml() {
  local APPLY_FILE="$1"

  if [[ -z "$APPLY_FILE" ]]; then
    APPLY_FILE="$K8S_KUBECTL_DEPLOY_FILE"
  fi

  if [ -f "$APPLY_FILE" ]; then

    stdCallback "$K8S_KUBECTL_BEFORE_APPLY" "$APPLY_FILE"

    stdLogInfo "Applying $APPLY_FILE..."

    if [[ "$K8S_KUBECTL_NAMESPACE" != "" ]]; then

      kubectl apply -f "$APPLY_FILE" --record -n "$K8S_KUBECTL_NAMESPACE" || return 1
    else
      kubectl apply -f "$APPLY_FILE" --record || return 1
    fi

    stdCallback "$K8S_KUBECTL_AFTER_APPLY" "$APPLY_FILE"
  else

    stdLogErr "Apply file is not found!"
    return 1
  fi
}

function k8sKubectlApply() {

  local APPLY_FILE="$1"
  local STATE_DIR="$2"
  local APPLY_YML="$3"

  if [ -f "$APPLY_FILE" ]; then

    k8sKubectlApplyYaml "$APPLY_FILE" || return 1
    cp -f "$APPLY_FILE" "$STATE_DIR/$APPLY_YML"

    k8sStateSave "$STATE_DIR"
  fi
}

function k8sKubectlDelete() {

  local DELETE_FILE="$1"
  local LOAD_DIR="$2"
  local STATE_DIR="$3"
  local DELETE_STAGES="$4"
  local DELETE_YML="$5"

  local LOAD_KUBE_CONFIG="$LOAD_DIR/$K8S_KUBECTL_KUBE_CONFIG"
  if [ -f "$LOAD_KUBE_CONFIG" ]; then

    echo "Copying..." && cp -f "$LOAD_KUBE_CONFIG" "$STATE_DIR/"
  fi

  local SHOULD_PROCEED=""
  if [ -f "$DELETE_FILE" ]; then
    SHOULD_PROCEED="true"
  fi

  if [[ "$DELETE_STAGES" != "" ]]; then
    SHOULD_PROCEED="true"
  fi

  if [[ "$SHOULD_PROCEED" == "true" ]]; then

    if [ -f "$DELETE_FILE" ]; then

      echo "Deleting $DELETE_FILE..." && kubectl delete -f "$DELETE_FILE"

      cp -f "$DELETE_FILE" "$STATE_DIR/$DELETE_YML"
    fi

    if [[ "$DELETE_STAGES" != "" ]]; then

      local LOAD_DIR="$K8S_KUBECTL_LOAD_DIR"

      if [ ! -f "$STATE_DIR/$DELETE_YML" ]; then
        touch "$STATE_DIR/$DELETE_YML"
      fi

      for STAGE in $DELETE_STAGES; do

        local STAGE_FILE="$LOAD_DIR/$STAGE.yml"
        if [ ! -f "$STAGE_FILE" ]; then
          STAGE_FILE="$STATE_DIR/$STAGE.yml"
        fi

        if [ -f "$STAGE_FILE" ]; then

          echo "Deleting $STAGE_FILE..."

          local EXIT_FILE="$GITLAB_PIPELINE_ID.delete"
          local EXIT_CODE=$(kubectl delete -f "$STAGE_FILE" &>"$EXIT_FILE" || echo "$?")
          cat "$EXIT_FILE" && rm -f "$EXIT_FILE"

          if [[ "$EXIT_CODE" == "" ]]; then
            EXIT_CODE=0
          fi

          if [[ "$EXIT_CODE" == "0" ]]; then

            echo "---" >>"$STATE_DIR/$DELETE_YML"
            cat "$STAGE_FILE" >>"$STATE_DIR/$DELETE_YML"
          fi
        fi
      done
    fi

    k8sStateSave "$STATE_DIR"
  else

    echo "Delete file(s) is not found."
  fi
}

function k8sKubectlPrepare() {

  local skipDryRun="$1"

  k8sKubectlRender "$K8S_KUBECTL_HELM_DIR" "$K8S_KUBECTL_HELM_VALUES_FILE" "$K8S_KUBECTL_DEPLOY_FILE" || return 1
  k8sKubectlCustomize "$K8S_KUBECTL_KUSTOMIZER_DIR" "$K8S_KUBECTL_KUSTOMIZER_FILE" "$K8S_KUBECTL_DEPLOY_FILE" || return 1
  if [[ "$skipDryRun" != "true" ]]; then
    k8sKubectlDryRun "$K8S_KUBECTL_DEPLOY_FILE" "$K8S_KUBECTL_LOAD_DIR" "$K8S_KUBECTL_STATE_DIR"
  fi
}

function k8sKubectlDeploy() {

  if [ -f "$K8S_KUBECTL_DEPLOY_FILE" ]; then
    rm "$K8S_KUBECTL_DEPLOY_FILE"
  fi

  if [ ! -d "$K8S_KUBECTL_STATE_DIR" ]; then
    mkdir -p "$K8S_KUBECTL_STATE_DIR"
  fi

  k8sStateLoad "$K8S_KUBECTL_LOAD_DIR" || return 1
  k8sKubectlPrepare || return 1

  if [[ ! "$K8S_KUBECTL_DRY_RUN_ONLY" == "true" ]]; then
    k8sKubectlApply "$K8S_KUBECTL_DEPLOY_FILE" "$K8S_KUBECTL_STATE_DIR" "$K8S_KUBECTL_APPLY_YML" || return 1
  fi
}

function k8sKubectlMultipleDeploy() {
  local __kpdmDeployYamlFile=""
  if [[ -z "$KUBECTL_DEPLOY_SOURCES" ]]; then
    stdLogErr "Env. var 'KUBECTL_DEPLOY_SOURCES' is not set, stage skipped..." || return 1
  fi

  if [ ! -d "$K8S_KUBECTL_STATE_DIR" ]; then
    mkdir -p "$K8S_KUBECTL_STATE_DIR"
  fi

  k8sStateLoad "$K8S_KUBECTL_LOAD_DIR" || return 1

  local oldIFS="$IFS"
  IFS="|"

  local k8sKubectlHelmDirOld="$K8S_KUBECTL_HELM_DIR"
  local k8sKubectlHelmValuesFileOld="$K8S_KUBECTL_HELM_VALUES_FILE"

  local k8sKubectlKustomizerDirOld="$K8S_KUBECTL_KUSTOMIZER_DIR"
  local k8sKubectlKustomizerFileOld="$K8S_KUBECTL_KUSTOMIZER_FILE"
  local k8sKubectlKustomizerPatchDirOld="$K8S_KUBECTL_KUSTOMIZER_PATCH_DIR"

  for source in $KUBECTL_DEPLOY_SOURCES; do
    stdLogInfo "Processing '$source'..."
    if [[ ! -d "$source" ]]; then
      stdLogErr "Source '$source' is not exist..." || return 1
    fi

    __kpdmDeployYamlFile="${GITLAB_JOB_NAME}_"$(echo "$source" | grep -Eio '[^\/]+' | tail -1)".yml"
    stdLogTrace "Rednered output yaml file name: '$__kpdmDeployYamlFile'"

    export K8S_KUBECTL_HELM_DIR="$source"
    export K8S_KUBECTL_KUSTOMIZER_DIR="$source"

    stdLogDebug "Renedring..."
    k8sKubectlRender "$K8S_KUBECTL_HELM_DIR" "$K8S_KUBECTL_HELM_VALUES_FILE" "$__kpdmDeployYamlFile" || return 1

    stdLogDebug "Customizing..."
    k8sKubectlCustomize "$K8S_KUBECTL_KUSTOMIZER_DIR" "$K8S_KUBECTL_KUSTOMIZER_FILE" "$__kpdmDeployYamlFile" || return 1

    k8sKubectlDryRun "$__kpdmDeployYamlFile" "$K8S_KUBECTL_LOAD_DIR" "$K8S_KUBECTL_STATE_DIR"

    if [[ ! "$K8S_KUBECTL_DRY_RUN_ONLY" == "true" ]]; then
      k8sKubectlApplyYaml "$__kpdmDeployYamlFile" || return 1
      cp -f "$__kpdmDeployYamlFile" "$K8S_KUBECTL_STATE_DIR/$__kpdmDeployYamlFile"
    fi
  done

  #Reverting back....
  export K8S_KUBECTL_HELM_DIR="$k8sKubectlHelmDirOld"
  export K8S_KUBECTL_HELM_VALUES_FILE="$k8sKubectlHelmValuesFileOld"

  export K8S_KUBECTL_KUSTOMIZER_DIR="$k8sKubectlKustomizerDirOld"
  export K8S_KUBECTL_KUSTOMIZER_FILE="$k8sKubectlKustomizerFileOld"
  export K8S_KUBECTL_KUSTOMIZER_PATCH_DIR="$k8sKubectlKustomizerPatchDirOld"

  IFS="$oldIFS"
  k8sStateSave "$K8S_KUBECTL_STATE_DIR"
}

function k8sKubectlRollback() {

  local DELETE_STAGES="$1"

  if [ -f "$K8S_KUBECTL_DEPLOY_FILE" ]; then
    rm "$K8S_KUBECTL_DEPLOY_FILE"
  fi

  if [ ! -d "$K8S_KUBECTL_STATE_DIR" ]; then
    mkdir -p "$K8S_KUBECTL_STATE_DIR"
  fi

  k8sStateLoad "$K8S_KUBECTL_LOAD_DIR"
  k8sKubectlPrepare "true"

  k8sKubectlDelete "$K8S_KUBECTL_DEPLOY_FILE" "$K8S_KUBECTL_LOAD_DIR" "$K8S_KUBECTL_STATE_DIR" "$DELETE_STAGES" "$K8S_KUBECTL_DELETE_YML"
}

function k8sKubectlKubeconfig() {

  local P1="$1"
  local USER_NAME=${USER_NAME:="$P1"}

  local P2="$2"
  local USER_KEY_LENGTH=${USER_KEY_LENGTH:="$P2"}

  USER_KEY_LENGTH=${USER_KEY_LENGTH:="2048"}

  if [[ "$USER_NAME" == "" ]]; then
    echo "User name is empty. Kubeconfig skipped."
    return
  fi

  local LOAD_DIR="$K8S_KUBECTL_LOAD_DIR"

  k8sStateLoad "$LOAD_DIR"

  local STATE_DIR="$K8S_KUBECTL_STATE_DIR"
  if [ ! -d "$STATE_DIR" ]; then
    mkdir -p "$STATE_DIR"
  fi

  local LOAD_KUBE_CONFIG="$LOAD_DIR/$K8S_KUBECTL_KUBE_CONFIG"
  if [ -f "$LOAD_KUBE_CONFIG" ]; then

    echo "Copying..." && cp -f "$LOAD_KUBE_CONFIG" "$STATE_DIR/"
  fi

  local USER_DIR="$STATE_DIR/$USER_NAME"

  if [ ! -d "$USER_DIR" ]; then
    mkdir -p "$USER_DIR"
  fi

  local USER_KUBECONFIG="${USER_DIR}/${USER_NAME}.kube-config"

  echo "Generating $USER_KUBECONFIG..."

  local USER_CSR_CONF="${USER_DIR}/${USER_NAME}.conf"

  cat <<EOF >"${USER_CSR_CONF}"
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn

[ dn ]
CN = ${USER_NAME}

[ v3_ext ]
authorityKeyIdentifier = keyid, issuer:always
basicConstraints = CA:FALSE
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF

  local USER_KEY="${USER_DIR}/${USER_NAME}.key"
  local USER_CSR="${USER_DIR}/${USER_NAME}.csr"

  openssl genrsa -out "${USER_KEY}" "${USER_KEY_LENGTH}"
  echo "Creating csr..." && openssl req -new -key "${USER_KEY}" -out "${USER_CSR}" -config "${USER_CSR_CONF}" && echo "Done."

  local USER_CSR_REQUEST=$(cat "${USER_CSR}" | base64 | tr -d '\n')
  local USER_CSR_YML="${USER_DIR}/${USER_NAME}.yml"

  cat <<EOF >"${USER_CSR_YML}"
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: ${USER_NAME}
spec:
  groups:
  - system:authenticated
  request: ${USER_CSR_REQUEST}
  usages:
  - digital signature
  - key encipherment
  - server auth
  - client auth
EOF

  echo "Deleting old csr..."

  kubectl delete csr "${USER_NAME}" || true

  echo "Creating new csr..."

  cat "${USER_CSR_YML}" | kubectl apply --wait=true -f -

  echo "Approving new csr..."

  kubectl certificate approve "${USER_NAME}"

  local USER_CERT="${USER_DIR}/${USER_NAME}.cert"

  echo "Getting certificate..."

  kubectl get csr "${USER_NAME}" -o jsonpath='{.status.certificate}' | base64 --decode >"${USER_CERT}"

  openssl x509 -in "${USER_CERT}" -noout -dates

  local CLUSTER_NAME=$(kubectl config view --raw -o json | jq -r '.clusters[] | .name')
  local CLUSTER_ENDPOINT=$(kubectl config view --raw -o json | jq -r '.clusters[] | .cluster.server')
  local CLUSTER_CA_DATA=$(kubectl config view --raw -o json | jq -r '.clusters[] | .cluster."certificate-authority-data"')
  local USER_CERT_DATA=$(cat "${USER_CERT}" | tr -d '"' | base64 -w 0)
  local USER_KEY_DATA=$(cat "${USER_KEY}" | tr -d '"' | base64 -w 0)

  cat <<EOF >"${USER_KUBECONFIG}"
apiVersion: v1
kind: Config
preferences: {}
current-context: ${USER_NAME}-${CLUSTER_NAME}
clusters:
- cluster:
    server: ${CLUSTER_ENDPOINT}
    certificate-authority-data: ${CLUSTER_CA_DATA}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: ${USER_NAME}
  name: ${USER_NAME}-${CLUSTER_NAME}
users:
- name: ${USER_NAME}
  user:
    client-certificate-data: ${USER_CERT_DATA}
    client-key-data: ${USER_KEY_DATA}
EOF

  k8sStateSave "$STATE_DIR"
}

function k8sKubectlBackupYamls() {

  local BACKUP_DIR="$1"

  local LOAD_KUBE_CONFIG="$K8S_KUBECTL_LOAD_DIR/$K8S_KUBECTL_KUBE_CONFIG"
  if [ -f "$LOAD_KUBE_CONFIG" ]; then

    echo "Copying kubeconfig file." && cp -f "$LOAD_KUBE_CONFIG" "$K8S_KUBECTL_STATE_DIR/"
  fi

  local outputFormat="yaml"

  listOfClusterObjects="clusterrolebindings
  clusterroles
  namespaces
  componentstatuses
  storageclasses
  persistentvolumes
  mutatingwebhookconfigurations
  validatingwebhookconfigurations
  customresourcedefinitions
  podsecuritypolicies
  priorityclasses
  volumeattachments"

  listOfNamespaceResources="
  configmaps
  secrets
  services
  serviceaccounts
  daemonsets
  deployments
  statefulsets
  cronjobs
  jobs
  ingresses
  networkpolicies
  rolebindings
  roles
  persistentvolumeclaims"

  mkdir -p ${BACKUP_DIR}

  echo -n "Create cluster objects backup..."
  for ressource in $listOfClusterObjects; do

    kubectl --kubeconfig="$KUBECONFIG" get -o $outputFormat $ressource >>"./${BACKUP_DIR}/$ressource.$outputFormat"
  done
  echo "Done."

  echo "Create every namespaced objects backup "
  for ns in $(yq r "./${BACKUP_DIR}/namespaces.$outputFormat" 'items.*.metadata.name' -j | jq -r .[]); do

    echo -n "Namespace $ns : "
    mkdir -p "${BACKUP_DIR}/$ns"
    for ressource in $listOfNamespaceResources; do

      EXPORT=$(kubectl --kubeconfig="$KUBECONFIG" --namespace="${ns}" get "$ressource" -o="$outputFormat")
      if [ -n "$EXPORT" ]; then
        echo "$EXPORT" >>"./${BACKUP_DIR}/$ns/$ressource.$outputFormat"
        echo -n ${ressource//[$'\t\r\n']/}" "
      fi
    done

    echo " "
  done
}

function k8sKubectlBackup() {

  if [ ! -d "$K8S_KUBECTL_STATE_DIR" ]; then
    mkdir -p "$K8S_KUBECTL_STATE_DIR"
  fi

  k8sStateLoad "$K8S_KUBECTL_LOAD_DIR"
  k8sKubectlBackupYamls "$K8S_KUBECTL_STATE_DIR/$K8S_KUBECTL_BACKUP_DIR"
  k8sStateSave "$K8S_KUBECTL_STATE_DIR"
}

function k8sKubectlRestoreYamls() {

  local RESTORE_DIR="$1"
  local RESTORE_NAMESPACES="$2"

  local RESTORE_YAML="restore.yaml"
  local TARGET_DIR="$RESTORE_DIR/templates"
  local TMP_DIR="/tmp/restore"

  local FILTER='del( .items[].status,
                      .items[].metadata.uid,
                      .items[].spec.clusterIP,
                      .items[].spec.claimRef,
                      .items[].spec.finalizers,
                      .items[].spec?.ports[]?.nodePort?,
                      .items[].metadata.selfLink,
                      .items[].metadata.resourceVersion,
                      .items[].metadata.creationTimestamp,
                      .items[].metadata.generation,
                      .items[].metadata.finalizers,
                      .items[].metadata.spec.finalizers,
                      .items[].metadata.labels."authz.cluster.cattle.io/rtb-owner",
                      .items[].metadata.labels."cattle.io/creator",
                      .items[].metadata.labels."field.cattle.io/projectId",
                      .items[].metadata.annotations."cattle.io/status",
                      .items[].metadata.annotations."field.cattle.io/projectId",
                      .items[].metadata.annotations."field.cattle.io/publicEndpoints",
                      .items[].metadata.annotations."deployment.kubernetes.io/revision",
                      .items[].metadata.annotations."lifecycle.cattle.io/create.namespace-auth",
                      .items[].metadata.annotations."kubernetes.io/change-cause",
                      .items[].metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
                      .items[].spec.template.metadata.annotations."cattle.io/timestamp",
                      .items[].spec.template.metadata.annotations."field.cattle.io/ports"
                    )'
  stdLogDebug "Moving '$RESTORE_DIR/backup' to '$TARGET_DIR'"
  stdExec "mv $RESTORE_DIR/backup $TARGET_DIR" || return 1

  mkdir -p $TMP_DIR/templates

  cat <<EOF >"$TMP_DIR/Chart.yaml"
description: backup chart
keywords:
- template
maintainers:
- email: some@email.com
  name: Some Name
name: backup-chart
version: 1.0
EOF

  if [[ "$RESTORE_NAMESPACES" == "" ]]; then

    for filename in $TARGET_DIR/*.yaml; do

      stdLogDebug "Check files: $filename"
      yq r "$filename" -j | jq "$FILTER" | yq r - >"/tmp/$filename"
    done

    NAMESPACES=$(yq r "$TARGET_DIR/namespaces.yaml" -j | jq -r '.items[].metadata.name')
  else

    NAMESPACES="$RESTORE_NAMESPACES"
  fi

  for ns in $NAMESPACES; do

    stdLogInfo "Prepare namespace $ns for restoring... "
    stdExec "mkdir -p $TMP_DIR/templates/$ns" || return 1

    for filename in $TARGET_DIR/$ns/*.yaml; do

      stdLogTrace "Processing $filename..."
      yq r "$filename" -j | jq "$FILTER" | yq r - >"/tmp/$filename"

    done
    stdLogInfo " Done"
  done

  local restoreYamlContent=""
  helm template $TMP_DIR >$RESTORE_YAML || return 1

  restoreYamlContent=$(cat $RESTORE_YAML)

  stdLogDebug "Restore yaml content:\n$restoreYamlContent"

  stdLogInfo "Starting kubectl dry-run:"

  stdExec "kubectl --kubeconfig=$KUBECONFIG  apply -f $RESTORE_YAML --dry-run" || return 1

  stdLogInfo "Starting kubectl apply:"
  stdExec "kubectl --kubeconfig=$KUBECONFIG  apply -f $RESTORE_YAML" || return 1

  rm -rf $RESTORE_YAML

}

function k8sKubectlRestore() {

  echo "Run restore process here...fix"

  if [[ "$K8S_CLUSTER_RESTORE_REPO" != "" ]] || [[ "$K8S_CLUSTER_RESTORE_TAG" != "" ]]; then

    # load config for current cluster

    load "$K8S_CLUSTER_LOAD_DIR"

    # Load state from repo with tag into restore dir

    export K8S_CLUSTER_STATE_REPO=$K8S_CLUSTER_RESTORE_REPO
    export K8S_CLUSTER_STATE_LOAD_TAG=$K8S_CLUSTER_RESTORE_TAG

    k8sStateLoad "$K8S_CLUSTER_RESTORE_DIR"

    # Run kubctl commands

    cp -f $K8S_CLUSTER_LOAD_DIR/$K8S_CLUSTER_KUBE_CONFIG $KUBECONFIG

    k8sKubectlRestoreYamls "$K8S_CLUSTER_RESTORE_DIR" "$K8S_CLUSTER_RESTORE_NAMESPACE"

  else

    echo "Please create new piplene from current tag. Add variable K8S_CLUSTER_RESTORE_REPO with repo url and K8S_CLUSTER_RESTORE_TAG from which tag you would like to restore! \n In K8S_CLUSTER_RESTORE_NAMESPACE you can filter which namespaces will be restore exactly. Namespace must be propertly configured before use!"
    return 1
  fi
}

function k8sKubectlRemoveK8SContent() {

  local nameSpacesList=""
  local exitCode=""
  local kubeConfig="${K8S_KUBECTL_LOAD_DIR}/$K8S_KUBECTL_KUBE_CONFIG"

  stdLogDebug "Using kubeconfig '$kubeConfig'..."

  stdExec "kubectl --kubeconfig=$kubeConfig get ns -o jsonpath={.items[*].metadata.name}" "nameSpacesList" || exitCode="$?"
  if [[ -z $exitCode ]]; then
    exitCode="$?"
  fi

  if ([[ "$exitCode" != 0 ]] || [[ -z "$nameSpacesList" ]]); then
    stdLogWarn "Can't get namespaces list..." #Already destroyed or kube.config is not valid...
    return 1
  fi

  for namespace in $(echo "$nameSpacesList" | sed -E 's/\n/ /g'); do
    if ([[ "$namespace" == "kube-system" ]] ||
      [[ "$namespace" == "cattle-system" ]] ||
      [[ "$namespace" == "kube-node-lease" ]] ||
      [[ "$namespace" == "kube-public" ]] ||
      [[ "$namespace" == "default" ]] ||
      [[ "$namespace" == "" ]]); then
      continue
    fi
    stdLogDebug "Removing namespace '$namespace'..."
    kubectl --kubeconfig=$kubeConfig delete ns $namespace --cascade=true --timeout=60s --wait=true ||
      stdLogWarn "For namespace '$namespace' some resources are not deleted!"
  done
  #Special case is namespace 'default' (can't be deleted through kubectl):
  stdLogDebug "Deleteing objects in 'default' namespace..."
  kubectl --kubeconfig=$kubeConfig delete Service,Ingress,Deployment,StatefulSet,DaemonSet,CronJob,Job,ReplicaSet,pvc,cm,Secret \
    -n "default" --all --cascade=true --timeout=300s --wait=true ||
    stdLogWarn "For namespace 'default' some resources are not deleted!"

}
