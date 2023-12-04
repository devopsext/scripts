#!/bin/bash
SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

. $SCRIPTS_DIR/std/utils.sh

AWS_REGISTRY_ACCOUNT_ID=${AWS_REGISTRY_ACCOUNT_ID:=""}
AWS_REGISTRY_REGION=${AWS_REGISTRY_REGION:=""}
AWS_REGISTRY_DOMAIN=${AWS_REGISTRY_DOMAIN:="amazonaws.com"}

function awsCliVersion() {

  if [[ -n $(which aws) ]]; then
    echo $(aws --version 2>/dev/null | grep -oE 'aws-cli\/[^\ ]+' | grep -oE '[0-9,\.]+')
  else
    echo ""
  fi
}

function awsCliVersion2Exists() {

  local version=$(awsCliVersion | grep -E "^2.*")
  if [[ "$version" != "" ]]; then
    true
    return
  fi
  false
}

function awsRegistryGetDefaultRegistry() {
  local defaultRegistryOut="$1"
  local awsAccountID="$2"
  local __awsRgdrDefaultRegistry=""

  awsAccountID=${awsAccountID:="$AWS_REGISTRY_ACCOUNT_ID"}

  if [[ -z $awsAccountID ]] && [[ -z $(which aws) ]]; then #aws cli here needed only if awsAccountID is not known
    stdLogErr "'aws cli is not installed or not found in $PATH"
    return 1
  fi

  if [[ -z "$AWS_REGISTRY_REGION" ]]; then
    stdLogErr "'AWS_REGISTRY_REGION' env.var is not set!"
    return 1
  fi

  #AWS Image format: <aws_account_id>.dkr.ecr.<aws_region>.amazonaws.com/<IMAGE>:<TAG>
  #Getting Account ID
  if [[ -z "$awsAccountID" ]]; then
    aws configure set region "$AWS_REGISTRY_REGION"
    awsAccountID=$(aws sts get-caller-identity | jq '.Account' | sed -E 's/\"//g')
    if [[ -z "$awsAccountID" ]]; then
      stdLogErr "Can't get aws account ID via aws cli"
      return 1
    fi
  fi

  __awsRgdrDefaultRegistry="${awsAccountID}.dkr.ecr.${AWS_REGISTRY_REGION}.${AWS_REGISTRY_DOMAIN}"

  eval "$defaultRegistryOut=$__awsRgdrDefaultRegistry"
  return 0
}

function awsRegistryRenderTargetImage() {
  local sourceImagePath="$1"
  local sourceImageName="$2"
  local sourceImageTag="$3"
  local targetImageOut="$4"

  local registry=""

  awsRegistryGetDefaultRegistry "registry" || return 1

  eval "$targetImageOut=${registry}/${sourceImagePath}/${sourceImageName}:${sourceImageTag}"

}

function awsRegistryPrepareTargetRepository() {

  local targetImagePath="$1"
  local targetImageName="$2"
  local registryIDOut="$3"

  local repositoryMeta=""
  local __awsRptrRegistryID=""

  local exitCode=""

  if [[ -z "$AWS_REGISTRY_REGION" ]]; then
    stdLogErr "'AWS_REGISTRY_REGION' env.var is not set!"
    return 1
  fi

  if [[ -z $(which aws) ]]; then
    stdLogErr "'aws cli is not installed or not found in $PATH"
    return 1
  fi

  aws configure set region "$AWS_REGISTRY_REGION" || return 1

  stdExec "aws ecr describe-repositories --repository-names ${targetImagePath}/${targetImageName}" "repositoryMeta" || true

  if [[ "$repositoryMeta" != "" ]]; then
    local repositoryCount=$(echo "$repositoryMeta" | jq '.repositories' | jq '. | length')
    if [[ "$repositoryCount" != 1 ]]; then
      stdLogErr "More than 1 repository found for '${targetImagePath}/${targetImageName}'..."
      return 1
    else
      __awsRptrRegistryID=$(echo "$repositoryMeta" | jq '.repositories[0].registryId' | sed -E 's/\"//g' | awk '{$1=$1};1')
    fi
  else #Repo is not exist
    #Creating repository
    stdLogInfo "Creating repository '${targetImagePath}/${targetImageName}'..."
    repositoryMeta=$(aws ecr create-repository --repository-name "${targetImagePath}/${targetImageName}") || return 1
    __awsRptrRegistryID=$(echo "$repositoryMeta" | jq '.repository.registryId' | sed -E 's/\"//g' | awk '{$1=$1};1')

  fi

  stdLogDebug "Registry ID: '$__awsRptrRegistryID'"
  eval "$registryIDOut=$__awsRptrRegistryID"
  return 0
}

function awsRegistryAutheticateDocker() {
  local registryID="$1"
  local dockerLoginCommand=""
  local __rgsDocker_out=""
  local __rgsDockerOutFile="/tmp/__$$.__rgsDockerOutFile"

  if [[ -z "$AWS_REGISTRY_REGION" ]]; then
    stdLogErr "'AWS_REGISTRY_REGION' env.var is not set!"
    return 1
  fi

  if [[ -z $(which aws) ]]; then
    stdLogErr "'aws cli is not installed or not found in $PATH"
    return 1
  fi

  if [[ ! -d "/tmp" ]]; then
    mkdir -p /tmp
  fi

  aws configure set region "$AWS_REGISTRY_REGION" || return 1

  echo "awsCliVersion => $(awsCliVersion)"

  #if awsCliVersion2Exists; then
    #dockerLoginCommand holds (https://docs.aws.amazon.com/cli/latest/reference/ecr/get-login.html):
    #docker login -u AWS -p password https://aws_account_id.dkr.ecr.us-east-1.amazonaws.com
    #dockerLoginCommand=$(aws ecr get-login --region ${AWS_REGISTRY_REGION} --registry-ids ${registryID} --no-include-email) || return 1
  #else
    #aws ecr get-login deprecated in 2.x
    dockerLoginCommand="aws ecr get-login-password --region ${AWS_REGISTRY_REGION} | docker login --username AWS --password-stdin \"${AWS_REGISTRY_ACCOUNT_ID}.dkr.ecr.${AWS_REGISTRY_REGION}.${AWS_REGISTRY_DOMAIN}\""    
  #fi

  #Auth in registry:
  eval "$dockerLoginCommand >${__rgsDockerOutFile} 2>&1"
  if [[ $? != 0 ]]; then
    __rgsDocker_out=$(cat "$__rgsDockerOutFile") && rm -rf "$__rgsDockerOutFile"
    stdLogErr "Failed to authorize in AWS registry '$registryID':\n${__rgsDocker_out}"
    return 1
  else
    stdLogDebug "Successfully authorized in AWS registry '$registryID'"
  fi
}
