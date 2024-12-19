#!/bin/bash
SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

STD_REGISTRY_BASE_REGISTRY=${STD_REGISTRY_BASE_REGISTRY:=""}

#Source registry itself detected from the image that being pushed
STD_REGISTRY_SOURCE_LOGIN=${STD_REGISTRY_SOURCE_LOGIN:="gitlab-ci-token"}
STD_REGISTRY_SOURCE_PASSWORD=${STD_REGISTRY_SOURCE_PASSWORD:="$GILTAB_JOB_TOKEN"}

STD_REGISTRY_TARGET_REGISTRY=${STD_REGISTRY_TARGET_REGISTRY:=""}
STD_REGISTRY_TARGET_REGISTRY_PROVIDER=${STD_REGISTRY_TARGET_REGISTRY_PROVIDER:=""}

STD_REGISTRY_TARGET_LOGIN=${STD_REGISTRY_TARGET_LOGIN:=""}
STD_REGISTRY_TARGET_PASSWORD=${STD_REGISTRY_TARGET_PASSWORD:=""}

STD_REGISTRY_TARGET_PATH=${STD_REGISTRY_TARGET_PATH:=""}
STD_REGISTRY_TARGET_NAME=${STD_REGISTRY_TARGET_NAME:=""}

STD_REGISTRY_TARGET_CHECK_EXISTENCE=${STD_REGISTRY_TARGET_CHECK_EXISTENCE:="false"}

. $SCRIPTS_DIR/std/utils.sh
. $SCRIPTS_DIR/aws/registry.sh
. $SCRIPTS_DIR/gcp/registry.sh
. $SCRIPTS_DIR/aliyun/registry.sh

function stdRegistryParseImage() {
  #TODO: cover cases for dockerhub images with or without tags (lstest) , etc.
  local imageInfo="$1"
  local imageRegistryOut="$2"
  local imagePathOut="$3"
  local imageNameOut="$4"
  local imageTagOut="$5"

  local __stdRpiImageRegistry=""
  local image=""
  local __stdRpiImageName=""
  local __stdRpiImageTag=""
  local __stdRpiImagePath=""

  #registry.env/project/service/ingress-nginx:0.24.1-1.0  => registry.env
  __stdRpiImageRegistry=$(echo "${imageInfo}" | awk -F '/' '{printf "%s",$1 }')

  #registry.env/project/service/ingress-nginx:0.24.1-1.0  => project/service/ingress-nginx:0.24.1-1.0
  image=$(echo "${imageInfo}" | sed -E "s/${__stdRpiImageRegistry}\///g")

  #project/service/ingress-nginx:0.24.1-1.0 => ingress-nginx
  __stdRpiImageName=$(echo "${image}" | grep -Eio '[^\/]+' | tail -1 | awk -F ':' '{printf "%s",$1 }')

  #project/service/ingress-nginx:0.24.1-1.0 => 0.24.1-1.0
  __stdRpiImageTag=$(echo "${image}" | awk -F ':' '{printf "%s",$2 }')

  #project/service/ingress-nginx => project/service
  __stdRpiImagePath=$(echo "${image}" | sed -E "s/\/${__stdRpiImageName}//g" | awk -F ':' '{printf "%s",$1 }')

  #Setting out variable
  stdLogTrace "Parsed image ${imageInfo} into following parts:\n\
registry: ${__stdRpiImageRegistry}\n\
path: ${__stdRpiImagePath}\n\
name: ${__stdRpiImageName}\n\
tag: ${__stdRpiImageTag}"

  if [[ -n "$imageRegistryOut" ]]; then
    eval "${imageRegistryOut}=${__stdRpiImageRegistry}"
  fi

  if [[ -n "$imagePathOut" ]]; then
    eval "${imagePathOut}=${__stdRpiImagePath}"
  fi

  if [[ -n "$imageNameOut" ]]; then
    eval "${imageNameOut}=${__stdRpiImageName}"
  fi

  if [[ -n "$imageTagOut" ]]; then
    eval "${imageTagOut}=${__stdRpiImageTag}"
  fi
}

function stdRegistryDockerLogin() {
  local registry="$1"
  local login="$2"
  local password="$3"
  local type="$4"
  local dockerLoginOut=""

  stdLogDebug "Authenticating in $type docker registry '$registry' with '$login' user..."

  echo "$password" | docker login -u "$login" --password-stdin "$registry" >__rgsDocker.out 2>&1
  if [[ $? != 0 ]]; then
    dockerLoginOut=$(cat __rgsDocker.out) && rm -rf __rgsDocker.out
    stdLogWarn "Failed to authorize in registry '$registry':\n$dockerLoginOut\nUsing anonymous connect..."
  fi

  return 0
}

function stdRegistryPullFromSourceRegistry() {
  local imageRegistry="$1"
  local sourceImage="$2"

  stdRegistryDockerLogin "$imageRegistry" "$STD_REGISTRY_SOURCE_LOGIN" "$STD_REGISTRY_SOURCE_PASSWORD" "SOURCE"

  stdLogDebug "Pulling image '$localImage'..."
  stdExec "docker pull '$sourceImage'" || return 1
  stdLogDebug "Image '$sourceImage' pulled..."

  return 0
}

function stdRegistryTagAndPush() {
  local localImage="$1"
  local remoteImage="$2"

  stdLogDebug "Tagging image '$localImage' to '$remoteImage'..."
  stdExec "docker tag $localImage $remoteImage" || return 1

  stdLogInfo "Pushing image '$remoteImage'..."
  stdExec "docker push $remoteImage" || return 1

  stdLogInfo "Image '$remoteImage' pushed..."

  return 0
}

function stdRegistryPushImage() {

  #Name of image to be pushed
  local sourceImage="$1"
  local sourceImageRegistry=""
  local sourceImagePath=""
  local sourceImageName=""
  local sourceImageTag=""

  #Name of image to be pushed
  local targetImage="$2"
  local targetImageRegistry=""
  local targetImagePath=""
  local targetImageName=""
  local targetImageTag=""

  local targetImageRegistryLogin="$3"
  local targetImageRegistryPassword="$4"

  targetImageRegistryLogin=${targetImageRegistryLogin:="$STD_REGISTRY_TARGET_LOGIN"}
  targetImageRegistryPassword=${targetImageRegistryPassword:="$STD_REGISTRY_TARGET_PASSWORD"}
  targetImageRegistryCheckExistence=${targetImageRegistryPassword:="$STD_REGISTRY_TARGET_CHECK_EXISTENCE"}

  stdRegistryParseImage "$sourceImage" "sourceImageRegistry" "sourceImagePath" "sourceImageName" "sourceImageTag"

  stdRegistryParseImage "$targetImage" "targetImageRegistry" "targetImagePath" "targetImageName" "targetImageTag"

  sourceImageRegistry=$(stdRegistryCleanRegistry "$sourceImageRegistry")
  targetImageRegistry=$(stdRegistryCleanRegistry "$targetImageRegistry")

  if [[ "$sourceImageRegistry" == "$targetImageRegistry" ]]; then
    stdLogInfo "No need to push image: source image ($sourceImage) refers to the target registry ($STD_REGISTRY_TARGET_REGISTRY)"
    return 0
  fi

  #Autheticating in source registry
  stdRegistryDockerLogin "$sourceImageRegistry" "$STD_REGISTRY_SOURCE_LOGIN" "$STD_REGISTRY_SOURCE_PASSWORD" "SOURCE"

  #Prepare target registry and authenticate against it!
  if [[ "$targetImageRegistryLogin" == "" && "$targetImageRegistryPassword" == "" ]]; then #Using cloud platform specific auth.
    local registryProvider=""
    stdRegistryGetRegistryProvider "$targetImageRegistry" "registryProvider"

    case "$registryProvider" in
      "aws")
        local registryID=""
        awsRegistryPrepareTargetRepository "$targetImagePath" "$targetImageName" "registryID" || return 1
        awsRegistryAutheticateDocker "$registryID"
        ;;
      "gcp")
        #For succesful auth, we need to set
        # GCP_REGISTRY_LOCATION, GCP_REGISTRY_PROJECT, and provide GCLOUD_ACCOUNT_JSON
        gcpRegistryAutheticateDocker
        ;;

      "aliyun")
        aliyunRegistryPrepareNamespace "$targetImagePath" || return 1
        aliyunRegistryAutheticateDocker || return 1
        ;;

      *)
        stdLogWarn "Trying to auth. in '$targetImageRegistry' with dummy user and password..."
        stdRegistryDockerLogin "$targetImageRegistry" "dummy" "dummy" "TARGET"
        ;;
    esac

  else #Assuming that we have full control to registry, and push operation will create necessary structure inside registry
    #Logging in docker

    stdRegistryDockerLogin "$targetImageRegistry" "$targetImageRegistryLogin" "$targetImageRegistryPassword" "TARGET"
  fi

  #Pull source image locally
  stdLogDebug "Pulling source image '$sourceImage'..."
  stdExec "docker pull '$sourceImage'" || return 1
  stdLogDebug "Source image '$sourceImage' pulled..."

  if [[ "$STD_REGISTRY_TARGET_CHECK_EXISTENCE" == "true" ]]; then

    stdLogInfo "Checking existence of target image '$targetImage'..."

    imageFailed=$(docker pull $targetImage &>/dev/null ; echo $?)
    if [[ "$imageFailed" == "0" ]]; then

      stdLogInfo "Target Image '$targetImage' is found. Skipping..."
      return 0
    fi
  fi

  stdLogDebug "The source image '$sourceImage'\nwill be pushed as target image '$targetImage'"

  stdRegistryTagAndPush "$sourceImage" "$targetImage" || return 1

  return 0
}

function stdRegistryCleanRegistry() {
  echo "$1" | sed -E "s/^(http:\/\/|https:\/\/)?//g"
}

function stdRegistryGetRegistryProvider() {
  local registry="$1"
  local registryProviderOut="$2"

  if echo "$registry" | grep -qEi "$ALIYUN_REGISTRY_DOMAIN"; then
    eval "$registryProviderOut=aliyun"
  elif echo "$registry" | grep -qEi "$AWS_REGISTRY_DOMAIN"; then
    eval "$registryProviderOut=aws"
  elif echo "$registry" | grep -qEi "$GCP_REGISTRY_DOMAIN"; then
    eval "$registryProviderOut=gcp"
  else
    eval "$registryProviderOut=plain"
  fi
}

function stdRegistryRenderBaseImage() {
  local inputImage="$1"
  local inputImageRegistry=""
  local inputImagePath=""
  local inputImageName=""
  local inputImageTag=""
  local inputRegistryProvider=""

  local baseImageOut="$2"
  local baseRegistry="$3"

  baseRegistry=${baseRegistry:="$STD_REGISTRY_BASE_REGISTRY"}

  if [[ -z "$baseRegistry" ]]; then
    stdLogErr "Base registry is not passed as input parameter, and env. var 'STD_REGISTRY_BASE_REGISTRY' is not set..."
    return 1
  fi

  baseRegistry=$(stdRegistryCleanRegistry "$baseRegistry")

  stdRegistryParseImage "$inputImage" "inputImageRegistry" "inputImagePath" "inputImageName" "inputImageTag"

  stdRegistryGetRegistryProvider "$inputImageRegistry" "inputRegistryProvider"
  stdLogDebug "Registry '$inputImageRegistry', detected registry provider: $inputRegistryProvider"

  case "$inputRegistryProvider" in
    "aws")
      eval "$baseImageOut=${baseRegistry}/${inputImagePath}/${inputImageName}:${inputImageTag}"
      ;;

    "gcp")
      eval "$baseImageOut=${baseRegistry}/${inputImagePath}/${inputImageName}:${inputImageTag}"
      ;;

    "aliyun")
      aliyunRegistryRenderBaseImage "$baseRegistry" "__stdRrbiBaseImage" "$inputImagePath" "$inputImageName" "$inputImageTag" || return 1
      eval "$baseImageOut=${__stdRrbiBaseImage}"
      ;;

    *)
      eval "$baseImageOut=${baseRegistry}/${inputImagePath}/${inputImageName}:${inputImageTag}"
      ;;
  esac
  return 0

}

function stdRegistryRenderTargetImage() {
  #Name of local image to be used to render target image
  local sourceImage="$1"
  local imageRegistry=""
  local imagePath=""
  local imageName=""
  local imageTag=""

  #Name of variable into wich the full name of target image will be set
  local targetImageOut="$2"

  local targetImageRegistry="$3"

  local targetImagePathOverride="$4"
  local targetImageNameOverride="$5"

  targetImageRegistry=${targetImageRegistry:="$STD_REGISTRY_TARGET_REGISTRY"}
  targetImagePathOverride=${targetImagePathOverride:="$STD_REGISTRY_TARGET_PATH"}
  targetImageNameOverride=${targetImageNameOverride:="$STD_REGISTRY_TARGET_NAME"}

  local targetImageTagOverride=""

  local targetRegistryPrepared=""
  local __stdRrtiTargetImage=""

  stdRegistryParseImage "$sourceImage" "imageRegistry" "imagePath" "imageName" "imageTag"

  if [[ "$targetImagePathOverride" != "" ]]; then

    imagePathOverriden="${targetImagePathOverride/\%s/$imagePath}"
    stdLogDebug "Target image path '$imagePath' overriden to '$imagePathOverriden'"
    imagePath="$imagePathOverriden"
  fi

  if [[ "$targetImageNameOverride" != "" ]]; then
    stdLogDebug "Target image name '$imageName' overriden to '$targetImageNameOverride'"
    imageName="$targetImageNameOverride"

    targetImageTagOverride=$(echo "$sourceImage" | sed -E "s/[\/,\:]+/-/g") #preserving infro from original image

    stdLogDebug "Target image tag '$imageTag' overriden to '$targetImageTagOverride'"
    imageTag="$targetImageTagOverride"
  fi

  #Default logic for plain registries...
  if [[ "$targetImageRegistry" != "" ]]; then

    targetImageRegistry=$(stdRegistryCleanRegistry "$targetImageRegistry")

    stdLogDebug "Rendering target image based on target registry '$targetImageRegistry'..."

    __stdRrtiTargetImage="${targetImageRegistry}/${imagePath}/${imageName}:${imageTag}"

  elif [[ -n "$STD_REGISTRY_TARGET_REGISTRY_PROVIDER" ]]; then #Trying to render using cloud specific
    local cloudDefaultRegistry=""
    case "$STD_REGISTRY_TARGET_REGISTRY_PROVIDER" in
      "aws")
        #Before call, we need to provide auth data for aws (AWS_ACCESS_KEY_ID, AWS_SECRET_KEY)
        awsRegistryRenderTargetImage "$imagePath" "$imageName" "$imageTag" "__stdRrtiTargetImage" || return 1
        ;;
      "gcp")
        #Before call, we need to set
        #GCP_REGISTRY_LOCATION, GCP_REGISTRY_PROJECT, and provide auth data for gcloud (GCLOUD_ACCOUNT_JSON)
        gcpRegistryRenderTargetImage "$imagePath" "$imageName" "$imageTag" "__stdRrtiTargetImage" || return 1
        ;;
      "aliyun")
        aliyunRegistryRenderTargetImage "$imagePath" "$imageName" "$imageTag" "__stdRrtiTargetImage" || return 1
        ;;
      *)
        stdLogErr "Unsupported target registry provider '$STD_REGISTRY_TARGET_REGISTRY_PROVIDER'!"
        return 1
        ;;

    esac
  else
    stdLogErr "Env. var 'STD_REGISTRY_TARGET_REGISTRY' & 'STD_REGISTRY_TARGET_REGISTRY_PROVIDER' is not set."
    return 1
  fi

  eval "$targetImageOut=$__stdRrtiTargetImage"
  return 0
}

#function stdRegistryInit() {
#  if [[ -z "$STD_REGISTRY_TARGET_REGISTRY" ]] && [[ -z "$STD_REGISTRY_TARGET_REGISTRY_PROVIDER" ]]; then
#
#    stdLogErr "Env. var. 'STD_REGISTRY_TARGET_REGISTRY' & 'STD_REGISTRY_TARGET_REGISTRY_PROVIDER' \
#are not set! One of them must be set!"
#    return 1
#  elif [[ -z "$STD_REGISTRY_TARGET_REGISTRY" ]] && [[ -n "$STD_REGISTRY_TARGET_REGISTRY_PROVIDER" ]]; then
#
#    stdLogWarn "Env. var. 'STD_REGISTRY_TARGET_REGISTRY' is not set, trying to detect target \
#registry as default registry for provider '$STD_REGISTRY_TARGET_REGISTRY_PROVIDER'..."
#
#    case "$STD_REGISTRY_TARGET_REGISTRY_PROVIDER" in
#      "aws")
#        #Before call, we need to provide auth data for aws (AWS_ACCESS_KEY_ID, AWS_SECRET_KEY)
#        awsRegistryGetDefaultRegistry "STD_REGISTRY_TARGET_REGISTRY" || return 1
#        ;;
#      "gcp")
#        #Before call, we need to set
#        #GCP_REGISTRY_LOCATION, GCP_REGISTRY_PROJECT, and provide auth data for gcloud (GCLOUD_ACCOUNT_JSON)
#        gcpRegistryGetDefaultRegistry "STD_REGISTRY_TARGET_REGISTRY" || return 1
#        ;;
#      "aliyun")
#        #Before call, we need to set
#        #ALIYUN_REGISTRY_REGION_ID and provide auth data for aliyun-cli
#        if [[ "$STD_REGISTRY_TARGET_REGISTRY_ROOT_FOLDER" != "" ]]; then
#          ALIYUN_REGISTRY_NAMESPACE="$STD_REGISTRY_TARGET_REGISTRY_ROOT_FOLDER"
#          stdLogDebug "Env. var 'ALIYUN_REGISTRY_NAMESPACE' set from 'STD_REGISTRY_TARGET_REGISTRY_ROOT_FOLDER' ($STD_REGISTRY_TARGET_REGISTRY_ROOT_FOLDER)..."
#        else
#          STD_REGISTRY_TARGET_REGISTRY_ROOT_FOLDER="$ALIYUN_REGISTRY_NAMESPACE"
#        fi
#        aliyunRegistryGetDefaultRegistry "STD_REGISTRY_TARGET_REGISTRY" || return 1
#        ;;
#
#      *)
#        stdLogErr "Unsupported target registry provider '$STD_REGISTRY_TARGET_REGISTRY_PROVIDER'!"
#        return 1
#        ;;
#
#    esac
#
#  else #Nothing to do
#    return 0
#  fi
#
#  export STD_REGISTRY_TARGET_REGISTRY="$STD_REGISTRY_TARGET_REGISTRY"
#  stdLogDebug "Detected target registry: '$STD_REGISTRY_TARGET_REGISTRY', for provider '$STD_REGISTRY_TARGET_REGISTRY_PROVIDER'..."
#  return 0
#}
