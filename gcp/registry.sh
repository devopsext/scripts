#!/bin/bash
SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

. $SCRIPTS_DIR/std/utils.sh

GCP_REGISTRY_PROJECT=${GCP_REGISTRY_PROJECT:=""}
GCP_REGISTRY_LOCATION=${GCP_REGISTRY_LOCATION:=""}
GCP_REGISTRY_DOMAIN=${GCP_REGISTRY_DOMAIN:="gcr.io"}

function gcpRegistryGetDefaultRegistry() {
  local defaultRegistryOut="$1"
  local gcpProject="$2"
  local gcpLocation="$3"
  local __gcpRgdrDefaultRegistry=""
  local registryHost=""
  local location=""
  local preparedProject=""

  gcpProject=${gcpProject:="$GCP_REGISTRY_PROJECT"}
  gcpLocation=${gcpLocation:="$GCP_REGISTRY_LOCATION"}

  if [[ -z $gcpProject ]] || [[ -z $gcpLocation ]]; then
    stdLogErr " Set env. vars. 'GCP_REGISTRY_PROJECT' and/or 'GCP_REGISTRY_LOCATION' or provide project and location as input parameters..."
    return 1
  fi

  #Select registry based on cluster location
  #gcr.io hosts the images in the United States, but the location may change in the future
  #us.gcr.io hosts the image in the United States, in a separate storage bucket from images hosted by gcr.io
  #eu.gcr.io hosts the images in the European Union
  #asia.gcr.io hosts the images in Asia
  location=$(echo "$GCP_REGISTRY_LOCATION" | grep -Eio '[^-]+' | head -1)

  if [[ "$location" == "asia" ]] || [[ "$location" == "australia" ]]; then
    registryHost="asia.${GCP_REGISTRY_DOMAIN}"
  elif [[ "$location" == "europe" ]]; then
    registryHost="eu.${GCP_REGISTRY_DOMAIN}"
  elif [[ "$location" == "us" ]] ||
    [[ "$location" == "northamerica" ]] ||
    [[ "$location" == "southamerica" ]]; then
    registryHost="${GCP_REGISTRY_DOMAIN}"
  else
    stdLogErr "Can't detect registry host name based on location: '$GCP_REGISTRY_LOCATION'"
    return 1
  fi

  preparedProject=$(echo "$GCP_REGISTRY_PROJECT" | sed -E 's/\:/\//g')
  __gcpRgdrDefaultRegistry="${registryHost}/${preparedProject}"

  eval "$defaultRegistryOut=$__gcpRgdrDefaultRegistry"
  return 0
}

function gcpRegistryRenderTargetImage() {
  local sourceImagePath="$1"
  local sourceImageName="$2"
  local sourceImageTag="$3"
  local targetImageOut="$4"

  local registry=""

  gcpRegistryGetDefaultRegistry "registry" || return 1

  eval "$targetImageOut=${registry}/${sourceImagePath}/${sourceImageName}:${sourceImageTag}"

}

function gcpRegistryAutheticateDocker() {

  local gcpProject="$1"

  if [[ -z "$gcpProject" ]]; then
    gcpProject="$GCP_REGISTRY_PROJECT"
  fi

  if [[ -z $gcpProject ]]; then
    stdLogErr "GCP project not provided as input parameter and env. vars. 'GCP_REGISTRY_PROJECT' not set..."
    return 1
  fi

  if [[ -z $(which gcloud) ]]; then
    stdLogErr "'gcloud cli is not installed or not found in $PATH"
    return 1
  fi

  gcloud config set project "$gcpProject" || return 1

  #Auth in registry:
  if gcloud auth configure-docker --quiet; then
    stdLogDebug "Succesfully authorized in GCP project ($gcpProject) registry..."
  else
    stdLogErr "Failed to authorize in GCP project ($gcpProject) registry..."
    return 1
  fi

  return 0
}
