#!/bin/bash
SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

. $SCRIPTS_DIR/std/utils.sh

ALIYUN_REGISTRY_REGION_ID=${ALIYUN_REGISTRY_REGION_ID:=""}
ALIYUN_REGISTRY_NAMESPACE=${ALIYUN_REGISTRY_NAMESPACE:=""}
ALIYUN_REGISTRY_DOMAIN=${ALIYUN_REGISTRY_DOMAIN:="aliyuncs.com"}
ALIYUN_REGISTRY_ACCESS_KEY=${ALIYUN_REGISTRY_ACCESS_KEY:=""}
ALIYUN_REGISTRY_SECRET_KEY=${ALIYUN_REGISTRY_SECRET_KEY:=""}

ALYUN_REGISTRY_INTERNET_ACCESS_HOST=${ALYUN_REGISTRY_INTERNET_ACCESS_HOST:="registry-intl"}
ALYUN_REGISTRY_VPC_ACCESS_HOST=${ALYUN_REGISTRY_VPC_ACCESS_HOST:="registry-intl-vpc"}
ALYUN_REGISTRY_INTRANET_ACCESS_HOST=${ALYUN_REGISTRY_INTRANET_ACCESS_HOST:="registry-intl-internal"}

ALYUN_REGISTRY_LOGIN=${ALYUN_REGISTRY_LOGIN:=""}
ALYUN_REGISTRY_PASSWORD=${ALYUN_REGISTRY_PASSWORD:=""}

function aliyunRegistryGetDefaultRegistry() {
  local defaultRegistryOut="$1"
  local regionID="$2"
  local __aliyunRgdrDefaultRegistry=""

  regionID=${regionID:="$ALIYUN_REGISTRY_REGION_ID"}

  if [[ -z "$regionID" ]]; then
    stdLogErr "Aliyun region ID is not provided as input parameter and env. var. 'ALIYUN_REGISTRY_REGION_ID' is not set..."
    return 1
  fi

  #Ali registry format: <host>.<region-id>.aliyuncs.com
  __aliyunRgdrDefaultRegistry="${ALYUN_REGISTRY_INTERNET_ACCESS_HOST}.${regionID}.${ALIYUN_REGISTRY_DOMAIN}"

  eval "$defaultRegistryOut=$__aliyunRgdrDefaultRegistry"
  return 0
}

function aliyunRegistryRenderTargetImage() {
  local sourceImagePath="$1"
  local sourceImageName="$2"
  local sourceImageTag="$3"
  local targetImageOut="$4"
  local targetImageName=""
  local targetImageTag=""

  local __aliyunRrtiTargetImage=""

  local namespace="$5"

  namespace=${namespace:="$ALIYUN_REGISTRY_NAMESPACE"}
  if [[ -z "$namespace" ]]; then
    stdLogErr "Namspace is not passed as intput parameter and env. var. 'ALIYUN_REGISTRY_NAMESPACE' is not set!"
    return 1
  fi

  aliyunRegistryGetDefaultRegistry "targetRegistry" || return 1

  #Ali cloud registry is flattern
  #Transformation is: '<registry_base>/platform/service/nginx:15.1' => '<registry_aliyun>/<namespace>/platform:service_nginx_15.1'
  targetImageName=$(echo "$sourceImagePath" | awk -F '/' '{printf "%s",$1 }')
  targetImageTag=$(echo "${sourceImagePath}/${sourceImageName}_${sourceImageTag}" | sed -E "s/$targetImageName\///g" | sed -E 's/\//_/g')

  __aliyunRrtiTargetImage="${targetRegistry}/${namespace}/${targetImageName}:${targetImageTag}"
  eval "$targetImageOut=${__aliyunRrtiTargetImage}"
}

function aliyunRegistryRenderBaseImage() {
  local baseRegistry="$1"
  local baseImageOut="$2"
  local baseImagePath=""
  local baseImageName=""
  local baseImageTag=""
  local inputImagePath="$3"
  local inputImageName="$4"
  local inputImageTag="$5"

  #Unflattern image name
  #'<registry_aliyun>/<namespace>/platform:service_nginx_15.1' => '<base_registry>/platform/service/nginx:15.1'

  baseImagePath="$inputImageName"

  #service_nginx_15.1 => 15.1
  baseImageTag=$(echo "$inputImageTag" | grep -Eio '[^_]+' | tail -1)
  #service_nginx_15.1 => service/nginx
  baseImageName=$(echo "$inputImageTag" | sed -E "s/_$baseImageTag//g" | sed -E 's/_/\//g')

  eval "$baseImageOut=${baseRegistry}/${baseImagePath}/${baseImageName}:${baseImageTag}"
}

function aliyunRegistryPrepareNamespace() {

  local imagePath="$1"
  local imageNamespace=""
  local namespaceID=""
  local exitCode=""

  if [[ -z "$ALIYUN_REGISTRY_REGION_ID" ]]; then
    stdLogErr "'ALIYUN_REGISTRY_REGION_ID' env.var is not set!"
    return 1
  else
    stdLogTrace "ALIYUN_REGISTRY_REGION_ID = $ALIYUN_REGISTRY_REGION_ID"
  fi

  if [[ -z $(which aliyun) ]]; then
    stdLogErr "'aliyun cli is not installed or not found in $PATH"
    return 1
  fi

  #Get namespace from targetImage
  imageNamespace=$(echo "${imagePath}" | awk -F '/' '{printf "%s",$1 }')
  stdLogTrace "Image namespace is: $imageNamespace"

  aliyun configure set --mode AK --region "$ALIYUN_REGISTRY_REGION_ID" --access-key-id "$ALIYUN_REGISTRY_ACCESS_KEY" --access-key-secret "$ALIYUN_REGISTRY_SECRET_KEY" || return 1

  local errorResponse=""
  stdExec "aliyun cr GET /namespace/$imageNamespace" "namespacesMeta" "errorResponse" "exitCode" "true" || true
  if [[ $exitCode != 0 ]] && (echo "${errorResponse}${namespacesMeta}" | grep -qEio 'NAMESPACE_NOT_EXIST'); then
    stdLogDebug "Namespace '$imageNamespace' is not exist! Trying to create...."
    #Creating new namespace
    stdExec "aliyun cr CreateNamespace --body '{\"Namespace\": {\"Namespace\": \"$imageNamespace\"}}'" "namespaceID" "" "exitCode" || return 1
    namespaceID=$(echo "$namespaceID" | jq -r '.data.namespaceId')
    stdLogDebug "Namespace '$imageNamespace' created, namespace ID: $namespaceID..."
  elif [[ $exitCode == 0 ]]; then
    stdLogDebug "Found namespace '$imageNamespace'..."
  elif [[ $exitCode != 0 ]]; then
    stdLogWarn "Can't perform valid request to API (access rights issues?), assume that namespace '$imageNamespace' is already exist..."
  fi

  return 0
}

function aliyunRegistryAutheticateDocker() {
  local regionID="$1"
  local login="$2"
  local password="$3"
  local dockerLoginOut=""

  regionID=${regionID:="$ALIYUN_REGISTRY_REGION_ID"}

  if [[ -z "$regionID" ]]; then
    stdLogErr "Aliyun region ID is not provided as input parameter and env. var. 'ALIYUN_REGISTRY_REGION_ID' is not set..."
    return 1
  fi

  login=${login:="$ALYUN_REGISTRY_LOGIN"}
  password=${password:="$ALYUN_REGISTRY_PASSWORD"}

  if [[ "$login" == "" && "$password" == "" ]]; then
    stdLogDebug "Trying to generate temporary token to access registry..."
    aliyun configure set --mode AK --region "$ALIYUN_REGISTRY_REGION_ID" --access-key-id "$ALIYUN_REGISTRY_ACCESS_KEY" --access-key-secret "$ALIYUN_REGISTRY_SECRET_KEY" || return 1

    local loginPassword=""
    stdExec "aliyun cr GetAuthorizationToken" "loginPassword" || return 1
    if [[ -z "$loginPassword" ]]; then
      stdLogErr "Can't generate temporary token, API call returned empty response, access rights issue?"
      return 1
    fi
    loginPassword=$(echo "$loginPassword" | jq -r '.data.tempUserName + "=" + .data.authorizationToken')

    login="${loginPassword%=*}"
    password="${loginPassword#*=}"
  fi

  local registry="${ALYUN_REGISTRY_INTERNET_ACCESS_HOST}.${regionID}.aliyuncs.com"

  stdLogDebug "Authenticating in aliyun docker registry '$registry' with '$login' user..."

  echo "$password" | docker login -u "$login" --password-stdin "$registry" >__rgsDocker.out 2>&1
  if [[ $? != 0 ]]; then
    dockerLoginOut=$(cat __rgsDocker.out) && rm -rf __rgsDocker.out
    stdLogErr "Failed to authorize in registry '$registry':\n$dockerLoginOut"
    return 1
  fi

  return 0
}
