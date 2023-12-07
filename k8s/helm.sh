#!/bin/bash

SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

K8S_HELM_VARIABLES_PATTERN=${K8S_HELM_VARIABLES_PATTERN:="K8S_.*|DOCKER_.*|CI_.*"}
K8S_HELM_KUBE_CONFIG=${K8S_HELM_KUBE_CONFIG:="cluster.kube-config"}
K8S_HELM_LOAD_DIR=${K8S_HELM_LOAD_DIR:="load"}
K8S_HELM_STATE_DIR=${K8S_HELM_STATE_DIR:="state"}

K8S_HELM_DIR=${K8S_HELM_DIR:="helm"}
K8S_HELM_TEMP_DIR=${K8S_HELM_TEMP_DIR:="$GITLAB_JOB_ID"}
K8S_HELM_TEMPLATE_FLAGS=${K8S_HELM_TEMPLATE_FLAGS:=""}
K8S_HELM_UPGRADE_FLAGS=${K8S_HELM_UPGRADE_FLAGS:=""}
K8S_HELM_UPGRADE_TIMEOUT=${K8S_HELM_UPGRADE_TIMEOUT:=""}
K8S_HELM_RELEASE_NAME=${K8S_HELM_RELEASE_NAME:=""}
K8S_HELM_NAMESPACE=${K8S_HELM_NAMESPACE:=""}
K8S_HELM_VALUES_FILE=${K8S_HELM_VALUES_FILE:="$GITLAB_JOB_NAME"}

K8S_HELM_KUSTOMIZER_DIR=${K8S_HELM_KUSTOMIZER_DIR:="kustomizer"}
K8S_HELM_KUSTOMIZER_ROOT=${K8S_HELM_KUSTOMIZER_ROOT:=""}
K8S_HELM_KUSTOMIZER_FILE=${K8S_HELM_KUSTOMIZER_FILE:="kustomization.yaml"}
K8S_HELM_KUSTOMZIER_BUILD_FLAGS=${K8S_HELM_KUSTOMZIER_BUILD_FLAGS:=""}

K8S_HELM_YAML=${K8S_HELM_YAML:="$GITLAB_JOB_NAME.yaml"}
K8S_HELM_CHART_YAML=${K8S_HELM_CHART_YAML:="Chart.yaml"}

K8S_HELM_KUSTOMIZE_USAGE=${K8S_HELM_KUSTOMIZE_USAGE:="true"}
K8S_HELM_KUSTOMIZE_IMAGE=${K8S_HELM_KUSTOMIZE_IMAGE:=""}
K8S_HELM_KUSTOMIZE_LABEL=${K8S_HELM_KUSTOMIZE_LABEL:=""}
K8S_HELM_KUSTOMIZE_ANNOTATION=${K8S_HELM_KUSTOMIZE_ANNOTATION:=""}
K8S_HELM_KUSTOMIZE_NAMESUFFIX=${K8S_HELM_KUSTOMIZE_NAMESUFFIX:=""}
K8S_HELM_KUSTOMIZE_NAMEPREFIX=${K8S_HELM_KUSTOMIZE_NAMEPREFIX:=""}

K8S_HELM_ENVTPL_DIR=${K8S_HELM_ENVTPL_DIR:=""}

. $SCRIPTS_DIR/std/utils.sh
. $SCRIPTS_DIR/k8s/state.sh

function k8sHelmVersion() {

  if [[ -n $(which helm) ]]; then

    echo $(helm version 2>/dev/null | awk -F '"v' '{printf "%s", $2}' | awk -F '",' '{printf "%s",$1}')
  else
    echo ""
  fi
}

function k8sHelm3Exists() {

  local version=$(k8sHelmVersion | grep -E "^3.*")
  if [[ "$version" != "" ]]; then
    true
    return
  fi
  false
}

function k8sHelm2Exists() {

  local version=$(k8sHelmVersion | grep -E "^2.*")
  if [[ "$version" != "" ]]; then
    true
    return
  fi
  false
}

function k8sHelmExists() {

  if [ k8sHelm2Exists || k8sHelm3Exists ]; then
    true
    return
  fi 
  false
}

function __k8sHelmTreeTrace() {

  local dir="$1"
  if [[ "$dir" == "" ]]; then
    dir="$PWD"
  fi

  if [[ -n $(which tree) ]]; then
    stdTraceSeparator
    stdLogTrace "'$dir' contents is:\n$(tree $dir)"
    stdTraceSeparator

    find "${dir}" -type f | while read file; do
      stdLogTrace "$file content:\n"
      stdLogTrace "$(cat $file)"
    done    
  fi
}

function __k8sHelmRenderByValues() {

  if [ ! k8sHelmExists ]; then
    stdLogErr "Helm is not found."
    return 1
  fi

  local helmDir="$1"
  local valuesFile="$2"
  local outputFile="$3"

  local pattern="$K8S_HELM_VARIABLES_PATTERN"
  local releaseName="$K8S_HELM_RELEASE_NAME"
  local namespace="$K8S_HELM_NAMESPACE"
  local flags="$K8S_HELM_TEMPLATE_FLAGS"

  stdLogInfo "Using values => $valuesFile ..."

  export variables=$(printenv | awk -F '=' '{printf "$%s\n", $1}' | grep -E "$pattern" | xargs)
  
  mv "$valuesFile" "$valuesFile.template"
  envsubst "$variables" <"$valuesFile.template" >"$valuesFile" || return 1
  rm -f "$valuesFile.template"

  local valuesContent=$(cat "$valuesFile")
  stdDebugSmallSeparator
  stdLogDebug "'$valuesFile' content:\n$valuesContent"
  stdDebugSmallSeparator

  stdLogInfo "Rendering release: $releaseName in namespace: $namespace with flags: $flags..."
  
  if [[ "$namespace" != "" ]]; then
    namespace="--namespace $namespace"
  fi

  if k8sHelm2Exists; then
    #helm template -f "$valuesFile" "$helmDir/" --name "$releaseName" $namespace $flags 1>"$outputFile" || return 1
    return 1
  elif k8sHelm3Exists; then
    __k8sHelmTreeTrace "$helmDir/"
    helm template "$releaseName" -f "$valuesFile" "$helmDir/" $namespace $flags 1>"$outputFile" || return 1
  fi
}

function __k8sHelmRenderByEnvtpl() {

  local dir="$1"

  if [ ! -d "$dir" ]; then
    stdLogDebug "Envtpl $dir is not found"
    return 1
  fi

  if [[ -n $(which envtpl) ]]; then

    local renderDir="$dir"

    stdLogInfo "Trying to render '$renderDir' folder recursively with envtpl..."

    find "$renderDir" -type f | while read file; do
      stdLogDebug "Rendering $file..."
      envtpl "$file" -o "$file" -m zero
    done
  fi
}

function __k8sHelmRenderByHelm() {

  local helmDir="$1"
  local valuesFile="$2"
  local outputFile="$3"

  local helmChartYaml="$helmDir/$K8S_HELM_CHART_YAML"

  if [ ! -f "$valuesFile" ]; then
    valuesFile="$helmDir/$valuesFile"
  fi

  if [ ! -f "$helmChartYaml" ]; then
    stdLogErr "Not found $helmChartYaml"
    return 1
  fi

  stdLogInfo "Using helm => $helmChartYaml"

  if [ -f "$valuesFile" ]; then
    __k8sHelmRenderByValues "$helmDir" "$valuesFile" "$outputFile" || return 1
  elif [ -f "$helmDir/values.yaml" ]; then
    __k8sHelmRenderByValues "$helmDir" "$helmDir/values.yaml" "$outputFile" || return 1
  else
    stdLogErr "Not found any helm values in $valuesFile"
    return 1
  fi
}

function __k8sHelmCustomize() {

  local kustomizerDir="$1"
  local kustomizerFile="$2"
  local inputFile="$3"
  local outputFile="$4"

  local pattern="$K8S_HELM_VARIABLES_PATTERN"
  local namespace="$K8S_HELM_NAMESPACE"
  local image="$K8S_HELM_KUSTOMIZE_IMAGE"
  local label="$K8S_HELM_KUSTOMIZE_LABEL"
  local annotation="$K8S_HELM_KUSTOMIZE_ANNOTATION"
  local nameSuffix="$K8S_HELM_KUSTOMIZE_NAMESUFFIX"
  local namePrefix="$K8S_HELM_KUSTOMIZE_NAMEPREFIX"
  local flags="$K8S_HELM_KUSTOMZIER_BUILD_FLAGS"

  if [ ! -f "$kustomizerFile" ]; then
    kustomizerFile="$kustomizerDir/$kustomizerFile"
  fi

  if [ ! -f "$kustomizerFile" ]; then
    stdLogInfo "Not found customize file '$kustomizerFile', skipping..."
    return
  fi

  stdLogInfo "Using kustomize for $kustomizerFile"

  local pwdOld="$PWD"

  export variables=$(printenv | awk -F '=' '{printf "$%s\n", $1}' | grep -E "$pattern" | xargs)

  mv "$kustomizerFile" "$kustomizerFile.template"
  envsubst "$variables" <"$kustomizerFile.template" >"$kustomizerFile" || return 1
  rm -f "$kustomizerFile.template"

  stdLogInfo "Going to $kustomizerDir/..." && cd "$kustomizerDir/"

  stdLogInfo "Adding resource $inputFile..."
  kustomize edit add resource "$inputFile" || return 1

  if [[ "$namespace" != "" ]]; then
    stdLogInfo "Setting namespace $namespace..."
    kustomize edit set namespace "$namespace" || return 1
  fi

  if [[ "$image" != "" ]]; then

    if [[ -z $(echo "$image" | grep -Ei '\=') ]]; then #$image="nginx:latest"
      stdLogInfo "Setting image $image..."
      kustomize edit set image image="$image" || return 1
    else #$image="image1=nginx:latest" OR "image1=nginx:latest,image2=debian:10,..."
      local imagePlaceholder=""
      local imageName=""
      for item in ${image//,/ }; do
        :
        if [[ -z "$item" || "$item" == "" ]]; then
          continue
        fi

        imagePlaceholder=$(echo "$item" | awk -F '=' '{printf "%s",$1 }')
        imageName=$(echo "$item" | awk -F '=' '{printf "%s",$2 }')
        stdLogInfo "Setting image $imagePlaceholder=$imageName..."
        kustomize edit set image "$imagePlaceholder=$imageName" || return 1
      done
    fi
  fi

  if [[ "$label" != "" ]]; then
    stdLogInfo "Adding label $labels..."
    kustomize edit add label -f "$labels" || return 1
  fi

  if [[ "$annotation" != "" ]]; then
    stdLogInfo "Adding annotation $annotation..."
    kustomize edit add annotation -f "$annotation" || return 1
  fi

  if [[ "$nameSuffix" != "" ]]; then
    stdLogInfo "Adding namesuffix $nameSuffix..."
    kustomize edit set namesuffix -- "$nameSuffix" || return 1
  fi

  if [[ "$namePrefix" != "" ]]; then
    stdLogInfo "Adding nameprefix $namePrefix..."
    kustomize edit set nameprefix -- "$namePrefix" || return 1
  fi

  cd "$pwdOld" && cat "$kustomizerFile"

  stdLogInfo "Customizing with flags: $flags..."
  stdLogDebug "Current dir: $PWD"

  __k8sHelmTreeTrace "$kustomizerDir/"

  kustomize build "$kustomizerDir/" $flags -o "$outputFile" || return 1
}

function __k8sHelmUpgrade() {

  if [ ! k8sHelmExists ]; then
    stdLogErr "Helm is not found."
    return 1
  fi

  local helmDir="$1"
  local dryRun="$2"

  local releaseName="$K8S_HELM_RELEASE_NAME"
  local namespace="$K8S_HELM_NAMESPACE"
  local flags="$K8S_HELM_UPGRADE_FLAGS"
  local timeout="$K8S_HELM_UPGRADE_TIMEOUT" 
  local helmChartYaml="$helmDir/$K8S_HELM_CHART_YAML"

  if [ ! -f "$helmChartYaml" ]; then
    stdLogErr "Not found $helmChartYaml"
    return 1
  fi

  if [[ "$namespace" != "" ]]; then
    namespace="--namespace $namespace"
  fi

  if [[ "$timeout" != "" ]]; then
    timeout="--timeout $timeout"
  fi

  if k8sHelm2Exists; then
    stdLogErr "Helm 2 is not supported anymore."
    return 1
  elif k8sHelm3Exists; then
    stdLogInfo "Upgrading $releaseName $dryRun..."
    __k8sHelmTreeTrace "$helmDir/"
    helm upgrade "$releaseName" "$helmDir/" -i --atomic --reset-values $dryRun $namespace $timeout $flags || return 1
  fi
}

#├── helm
#│   ├── Chart.yaml
#│   └── templates
#│       └── job.yaml
#└── kustomizer
#    └── iam-eks-sbx-eu
#        ├── job.yaml
#        └── kustomization.yaml

# Overall idea of the function is this:
# 0. Build temporary kustomize folder (referenced as $kustomizerTempDir)
# 1. From the helm chart specified ($helmDir) render with `helm template` command a $helmRenderFile file, that
#  is stored in temporary kustomize folder as: "$kustomizerOutputDir/$helmFile"
# 2. The $helmRenderFile is added into kustomize.yaml with the command `kustomize edit add resource`,
# then `kustomize build` command is run on top of temporary kustomzie directory. As a result we got $helmCustomizeFile
# that is stored in helm chart templates folder (helmCustomizeFile="$helmTemplatesDir/$helmFile")
# 3. Finally we deploy (via `helm upgrade`) the helm chart with $helmCustomizeFile

function __k8sHelmKustomizeDeploy() {

  local helmDir="$1"
  local valuesFile="$2"
  local dryRun="$3"

  local stateDir="$K8S_HELM_STATE_DIR"
  local loadDir="$K8S_HELM_LOAD_DIR"
  local helmFile="$K8S_HELM_YAML"
  local kustomizerDir="$K8S_HELM_KUSTOMIZER_DIR"
  local kustomizerRoot=${K8S_HELM_KUSTOMIZER_ROOT:="$K8S_HELM_KUSTOMIZER_DIR"}
  local kustomizerFile="$K8S_HELM_KUSTOMIZER_FILE"
  local kubeConfig="$K8S_HELM_KUBE_CONFIG"
  local helmChartYaml="$helmDir/$K8S_HELM_CHART_YAML"
  local tempDir="$K8S_HELM_TEMP_DIR"
  local envtplDir="$K8S_HELM_ENVTPL_DIR"

  k8sStateLoad "$loadDir" || return 1

  local loadKubeConfig="$loadDir/$kubeConfig"
  if [ -f "$loadKubeConfig" ]; then
    if [ ! -d "$stateDir" ]; then
      mkdir -p "$stateDir"
    fi
    stdLogInfo "Copying '$loadKubeConfig' to '$stateDir/'..." && cp -f "$loadKubeConfig" "$stateDir/"
  fi

  if [ -d "$tempDir" ]; then
    rm -rf "$tempDir"
  fi

  mkdir -p "$tempDir" 

  local helmTempDir="$tempDir/$helmDir"
  local helmTemplatesDir="$helmTempDir/templates"
  mkdir -p "$helmTemplatesDir"

  local kustomizerTempDir="$tempDir/$kustomizerDir"
  local parentKustomizerTempDir="$(dirname $tempDir/$kustomizerRoot)"
  local kustomizerOutputDir="$(dirname $kustomizerTempDir/$kustomizerFile)"
  local kustomizerFile="$(basename $kustomizerTempDir/$kustomizerFile)"

  #Step 0
  mkdir -p "$kustomizerTempDir"

  if [ -d "$kustomizerDir" ]; then
    stdLogInfo "Kustomizer dir is found. Copying from $kustomizerRoot/ to $parentKustomizerTempDir/..."
    cp -rf "$kustomizerRoot/" "$parentKustomizerTempDir/"
  else
    stdLogInfo "Kustomizer dir is not found. Emulating it in purpose of image retag..."
    mkdir -p "$kustomizerOutputDir" && touch "$kustomizerOutputDir/$kustomizerFile"
  fi

  #Step 1
  local helmRenderFile="$kustomizerOutputDir/$helmFile"
  __k8sHelmRenderByHelm "$helmDir" "$valuesFile" "$helmRenderFile" || return 1

  if [[ "$envtplDir" != "" ]]; then
    __k8sHelmRenderByEnvtpl "$tempDir/$envtplDir" || return 1
  fi

  #Step 2
  local helmCustomizeFile="$helmTemplatesDir/$helmFile"
  __k8sHelmCustomize "$kustomizerOutputDir" "$kustomizerFile" "$(basename $helmRenderFile)" "$helmCustomizeFile"
  
  cp -f "$helmChartYaml" "$helmTempDir/" || return 1

  if [ -f "$helmCustomizeFile" ]; then
    stdDebugSmallSeparator
    stdLogDebug "Final helm file content:\n$(cat $helmCustomizeFile)"
    stdDebugSmallSeparator
  fi

  #Step 3
  __k8sHelmUpgrade "$helmTempDir" "$dryRun" || return 1

  if [ -d "$stateDir" ] && [ -f "$helmCustomizeFile" ]; then
    cp -f "$helmCustomizeFile" "$stateDir/$helmFile"
    k8sStateSave "$stateDir" || return 1
  fi
  stdLogInfo "Done"
}

# Pure Helm deploy without kustomize
function __k8sHelmDeploy() {

  local helmDir="$1"
  local valuesFile="$2"
  local dryRun="$3"

  local stateDir="$K8S_HELM_STATE_DIR"
  local loadDir="$K8S_HELM_LOAD_DIR"
  local kubeConfig="$K8S_HELM_KUBE_CONFIG"

  k8sStateLoad "$loadDir" || return 1

  local loadKubeConfig="$loadDir/$kubeConfig"
  if [ -f "$loadKubeConfig" ]; then
    if [ ! -d "$stateDir" ]; then
      mkdir -p "$stateDir"
    fi
    stdLogInfo "Copying '$loadKubeConfig' to '$stateDir/'..." && cp -f "$loadKubeConfig" "$stateDir/"
  fi

  __k8sHelmUpgrade "$helmDir" "$dryRun" "$valuesFile" || return 1

  if [ -d "$stateDir" ]; then
    k8sStateSave "$stateDir" || return 1
  fi
  stdLogInfo "Done"
}

function k8sHelmDryRun() {

  local helmDir=${K8S_HELM_DIR:="$1"}
  local valuesFile=${K8S_HELM_VALUES_FILE:="$2"}
  local useKustomize=${K8S_HELM_KUSTOMIZE_USAGE}

  if [[ "useKustomize" != "true" ]]; then
  __k8sHelmDeploy "$helmDir" "$valuesFile" "--dry-run"
  else
  __k8sHelmKustomizeDeploy "$helmDir" "$valuesFile" "--dry-run"
  fi
}

function k8sHelmDeploy() {

  local helmDir=${K8S_HELM_DIR:="$1"}
  local valuesFile=${K8S_HELM_VALUES_FILE:="$2"}
  local useKustomize=${K8S_HELM_KUSTOMIZE_USAGE}

  if [[ "useKustomize" != "true" ]]; then
  __k8sHelmDeploy "$helmDir" "$valuesFile"
  else
  __k8sHelmKustomizeDeploy "$helmDir" "$valuesFile"
  fi
}

function k8sHelmRollback() {

  if [ ! k8sHelmExists ]; then
    stdLogErr "Helm is not found."
    return 1
  fi

  local releaseName="$K8S_HELM_RELEASE_NAME"
  local namespace="$K8S_HELM_NAMESPACE"

  if [[ "$namespace" != "" ]]; then
    namespace="--namespace $namespace"
  fi

  if k8sHelm2Exists; then
    stdLogErr "Helm 2 is not supported anymore."
    return 1
  elif k8sHelm3Exists; then

    local prevRelease=$(helm history "$releaseName" $namespace | tail -n2 | head -n1 | awk '{print $1}')
    if [[ "$prevRelease" != "REVISION" ]]; then
      stdLogInfo "Rolling back to revision => $prevRelease..."
      helm rollback "$releaseName" "$prevRelease" $namespace --recreate-pods || return 1
    else
      stdLogInfo "Previous release is not found. Uninstalling..."
      helm uninstall "$releaseName" $namespace || return 1
    fi
    stdLogInfo "Done"
  fi
}
