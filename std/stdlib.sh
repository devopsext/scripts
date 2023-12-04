#!/bin/bash
#Logging and some useful functions...
STD_LOG_HEADER_FORMAT=${STD_LOG_HEADER_FORMAT:='[${entryType}]'}
# All possible fields: '$_stdMsgIdent [$dateTimeUTCStamp UTC] [${entryType}] [${callStack}]' -> this produce header like this:
#[.gitlab-ci.yaml.sh] [2019.11.06 10:25:48 UTC] [I] [main()@53]
#Gitab-ci format [$${entryType}] [$${callStack}]

function stdGetColoredString() {
  local msg=$1
  local entryType=$2
  local color=""

  if ([[ ! "$_stdColoredOutput" ]]); then
    echo -n "$msg"
  else
    if [[ -z "$entryType" ]]; then
      entryType="$_stdLogLevelID"
    fi

    case "$entryType" in
      "T")
        color='\033[0;37m' #Ligth grey
        ;;
      "D")
        color='\033[0;33m' #Light brown
        ;;

      "I")
        color='\033[0;36m' #Light Blue
        ;;

      "W")
        color='\033[1;36m' #Bold Blue
        ;;

      'E')
        color='\033[1;31m' #Red bold
        ;;
      *)
        color='\033[0m' #No color
        ;;
    esac

    echo -n "${color}$msg${_stdNoColor}"
  fi
  return 0
}

function stdGetCallStack() {
  #getting stack trace except current function (and one above on a stack trace):
  local i=0
  local FRAMES=${#FUNCNAME[@]}
  local callStack=""
  local callStackDiscardLevels=$1

  if [[ -z "$callStackDiscardLevels" ]]; then
    callStackDiscardLevels=1
  fi

  # FRAMES-1 skips main shell, the last one in arrays
  for ((i = FRAMES - 1; i > $callStackDiscardLevels; i--)); do
    callStack=$(echo "${callStack}${FUNCNAME[i]}()@${BASH_LINENO[i - 1]}:")
  done

  #Remove last ':'
  echo ${callStack%?}
  return 0
}

function stdLog() {
  local msg=$1
  local logOutput=$2
  local callStackDiscardLevels=$3
  local toStderr=$4
  local entryType=$5

  if [[ -z "$logOutput" ]]; then
    logOutput="$_stdLogOutput"
  fi

  if [[ -z "$callStackDiscardLevels" ]]; then
    callStackDiscardLevels=3
  fi

  if [[ -z "$toStderr" ]]; then
    toStderr="false"
  fi

  if [[ -z "$entryType" ]]; then
    entryType=$_stdLogLevelID
  fi

  local callStack=$(stdGetCallStack $callStackDiscardLevels)

  local dateTimeUTCStamp=$(date -u '+%Y.%m.%d %H:%M:%S')

  local outputMsg=""
  local messageHeader=""
  local messageBody=""

  #    if [[ -z "$_stdMsgIdent" ]]; then
  #        messageHeader=""
  #    else
  #        messageHeader="$_stdMsgIdent"
  #    fi
  #
  #
  #    #local messageBody=$(stdGetColoredString "[$dateTimeUTCStamp UTC] [${entryType}] [${callStack}] ${msg}" ${entryType})
  #
  #    local messagePreambula=$(stdGetColoredString "[$dateTimeUTCStamp UTC] [${entryType}] [${callStack}]" ${entryType})
  #    messageBody="${messagePreambula} ${msg}"

  messageHeader=$(eval echo "$STD_LOG_HEADER_FORMAT" | sed -E 's/\[\]\ //g')
  messageHeader=$(stdGetColoredString "$messageHeader" ${entryType})

  outputMsg="${messageHeader} ${msg}"

  if [[ "$toStderr" == "false" ]]; then
    echo -e "$outputMsg" >>$logOutput

  else
    echo >&2 -e "$outputMsg" >>$logOutput
  fi
}

function stdSeparator() {

  local logOutput=$1
  local entryType=$2

  if [[ -z "$logOutput" ]]; then
    logOutput="$_stdLogOutput"
  fi

  local msg=$(stdGetColoredString "=========================================================" "$entryType")
  echo -e "$msg" >>$logOutput
}

function stdSmallSeparator() {
  local logOutput=$1
  local entryType=$2

  if [[ -z "$logOutput" ]]; then
    logOutput="$_stdLogOutput"
  fi

  local msg=$(stdGetColoredString "---------------------------------" "$entryType")
  echo -e "$msg" >>$logOutput
}

function stdLogTrace() {
  local msg=$1
  local logOutput=$2

  if (("$_stdLogLevelNumeric" <= 0)); then
    stdLog "$msg" "$logOutput" "2" "false" "T"
  fi
}

function stdTraceSeparator() {

  local logOutput=$1

  if (("$_stdLogLevelNumeric" <= 0)); then
    stdSeparator "" "T"
  fi
}

function stdTraceSmallSeparator() {

  local logOutput=$1

  if (("$_stdLogLevelNumeric" <= 0)); then
    stdSmallSeparator "" "T"
  fi
}

function stdLogDebug() {
  local msg=$1
  local logOutput=$2

  if (("$_stdLogLevelNumeric" <= 1)); then
    stdLog "$msg" "$logOutput" "2" "false" "D"
  fi
}

function stdLogDebugEnvVars() {
  local regexPattern=$1
  local logOutput=$2

  if (("$_stdLogLevelNumeric" <= 1)); then
    local vars=$(env | grep -Ei "$regexPattern")

    if [[ -z "$logOutput" ]]; then
      logOutput="$_stdLogOutput"
    fi

    stdDebugSmallSeparator
    stdLog "Reporting varialbes by pattern '$regexPattern':\n$vars" "$logOutput" "2" "false" "D"
    stdDebugSmallSeparator
  fi
}

function stdDebugSeparator() {

  local logOutput=$1

  if (("$_stdLogLevelNumeric" <= 1)); then
    stdSeparator "" "D"
  fi
}

function stdDebugSmallSeparator() {

  local logOutput=$1

  if (("$_stdLogLevelNumeric" <= 1)); then
    stdSmallSeparator "" "D"
  fi
}

function stdLogInfo() {
  local msg=$1
  local logOutput=$2
  if (("$_stdLogLevelNumeric" <= 2)); then
    stdLog "$msg" "$logOutput" "2" "false" "I"
  fi
}

function stdInfoSeparator() {

  local logOutput=$1

  if (("$_stdLogLevelNumeric" <= 2)); then
    stdSeparator "" "I"
  fi
}

function stdInfoSmallSeparator() {

  local logOutput=$1

  if (("$_stdLogLevelNumeric" <= 2)); then
    stdSmallSeparator "" "I"
  fi
}

function stdLogWarn() {
  local msg=$1
  local logOutput=$2
  if (("$_stdLogLevelNumeric" <= 3)); then
    stdLog "$msg" "$logOutput" "2" "false" "W"
  fi
}

function stdLogErr() {
  local msg=$1
  local logOutput=$2

  if (("$_stdLogLevelNumeric" <= 4)); then
    stdLog "$msg" "$logOutput" "2" "true" "E"
  fi
}

#To be used only in main script - logs to stderr, file and exit
function stdLogExit() {

  local msg=$1
  local logOutput=$2

  if [[ -z "$logOutput" ]]; then
    logOutput="$_stdLogOutput"
  fi

  set -o errexit

  stdLog "$msg, EXITING..." "$logOutput" "2" "true" "E"

  exit 1
}

#Working with JSON
function stdIsJSONvalid() {
  local jsonString="$1"
  if [[ -z "$jsonString" ]]; then
    stdLogErr "Json object string representations is empty."
    return 1
  fi
  # stdout suppresed, only stederr is returned
  resErr=$(echo "$jsonString" | jq "." 2>&1 >/dev/null)
  if ! [[ $? -eq 0 ]]; then
    stdLogErr "Can't parse JSON from string: '$jsonString'\nReason: $resErr"
    return 1
  fi

  return 0
}

function stdGetValueFromJson() {

  local jsonString="$1"       # String representation of json object
  local key="$2"              # Key name (supports hieracical keys). If the key name includes '.' escape then with '\.', otherwise, '.' threated as separator of hierarchical key.
  local valueType="$3"        # '' or 'object'/'raw'. If you have complex object to be returned (not the plain JSON value), set this input to "object", othervise left empty.
  local failIfEmptyValue="$4" # If the value is empty we can fail (specify then 'true' here)

  if [[ -z "$failIfEmptyValue" ]]; then
    failIfEmptyValue="true"
  fi

  #Checking if JSON is valid
  #stdIsJSONvalid "$jsonString" || return 1

  local jqCmd=''

  #Buidling the jq cmd line to retrive complex keys

  local oldIFS="$IFS"
  local keyIterateString=""
  local keySeparator="@:;#@"
  local array
  local arrayItemsSeparator=', '

  IFS="$arrayItemsSeparator"
  read -r -a array <<<$(echo "$key" | sed "s/\./$keySeparator/g" | sed "s/[\\]$keySeparator/\./g" | sed "s/$keySeparator/$arrayItemsSeparator/g")
  for keyItem in "${array[@]}"; do
    :
    if [[ -z "$keyItem" || "$keyItem" == "" ]]; then
      continue
    fi

    if [[ -z $(echo "$keyItem" | grep -i '[\[,\]]*') ]]; then #For non array keys
      jqCmd=$(echo "$jqCmd | jq '.[\"$keyItem\"]'")
    else #for array keys
      jqCmd=$(echo "$jqCmd | jq '.$keyItem'")
    fi
  done
  IFS="$oldIFS"

  local cmd=$(echo 'echo "$jsonString"' "$jqCmd")" 2>&1"
  local jsonValue=$(eval "$cmd")

  if ! [[ $? -eq 0 ]]; then
    stdLogErr "Can't parse json value using this command line: '$cmd'"
    return 3
  fi

  #Removing " around plain values (not objects)
  if ! [[ "$valueType" == "object" || "$valueType" == "raw" ]]; then
    jsonValue=$(echo $jsonValue | sed 's/\"//g')
    retCode=$?
  fi

  if ! [[ $retCode -eq 0 ]]; then
    stdLogErr $jsonValue
    return $retCode
  fi

  if [[ -z "$jsonValue" ]]; then
    stdLogErr "Key '${key}' value is empty."
    echo ""
    if [[ "$failIfEmptyValue" == "true" ]]; then
      return 2
    fi
  fi

  if [[ "$jsonValue" == "null" ]]; then
    stdLogErr "Key '${key}' is not valid/present.\nMake sure you've escaped all '.' (like this '\.') in the key name,\notherwise '.' will be treated as parts separator for hierarchical keys..."
    echo "null"
    return 1
  else
    echo "$jsonValue"
  fi

  return 0
}

##K8S API support
function stdk8sGetNamespace() {
  local k8sSAMountSecretDir=${K8S_SERVICE_ACCOUNT_MOUNT_SECRET_DIR:='/var/run/secrets/kubernetes.io/serviceaccount'}
  local namespaceFile="${k8sSAMountSecretDir}/${K8S_SERVICE_ACCOUNT_NAMESPACE_FILE:=namespace}"

  if [[ ! -z "$K8S_NAMESPACE" ]]; then
    echo "$K8S_NAMESPACE"
    return 0
  else

    if [[ -f "$namespaceFile" ]]; then
      cat "$namespaceFile"
      return 0
    else
      stdLogErr "Namespace file '$namespaceFile' is not found!"
      return 1
    fi
  fi
}

function stdk8sGetSAToken() {
  local k8sSAMountSecretDir=${K8S_SERVICE_ACCOUNT_MOUNT_SECRET_DIR:='/var/run/secrets/kubernetes.io/serviceaccount'}
  local tokenFile="${k8sSAMountSecretDir}/${K8S_SERVICE_ACCOUNT_TOKEN_FILE:=token}"

  if [[ ! -z "$K8S_SA_TOKEN" ]]; then
    echo "$K8S_SERVICE_ACCOUNT_TOKEN"
    return 0
  else
    if [[ -f "$tokenFile" ]]; then
      cat "$tokenFile"
      return 0
    else
      stdLogErr "Token file '$tokenFile' is not found!"
      return 1
    fi
  fi
}

function stdGetSelfContainerID() {
  local containerID=""
  local file=""
  local oldIFS=""

  oldIFS="$IFS"
  file="/proc/self/cgroup"

  local dockerSlice="docker-(.*).scope"

  while IFS= read line; do

    # 12:perf_event:/docker/4ec780db9098cf72397da7db1c34bcc507e86433f768e58871e483a83860f568
    # 3:net_prio,net_cls:/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod503e5541_11e0_11ea_954e_fad44fb97c83.slice/docker-1e188d9bb7964a618929310189566fea171521ddd6c771a50969dc77ea45cd57.scope
    containerID=$(echo "$line" | sed -En 's/.*:.*:.*\/(.*)/\1/gp' 2>/dev/null)

    if [[ "$containerID" =~ ^$dockerSlice ]]; then
      containerID=$(echo "$containerID" | sed -En "s/$dockerSlice/\1/gp")
    fi

    if [[ ! -z "$containerID" ]]; then
      break
    fi
  done <"$file"
  IFS="$oldIFS"

  if [[ -z "$containerID" ]]; then
    stdLogErr "Can'at detect self container ID..."
    return 1
  else
    echo "$containerID"
  fi
}

function stdk8sGetPodNameByContainerID() {
  local containerID="$1"
  local saToken=""
  local k8sMetadata=""
  local k8sNamespace=""
  local curlMaxTime=${K8S_TIMEOUT:="5"}

  if [[ -z "$containerID" ]]; then
    containerID=$(stdGetSelfContainerID) || return 1
  fi

  if [[ "$containerID" == $(stdGetSelfContainerID) && ! -z "$POD_NAME" ]]; then
    echo "$POD_NAME"
    return 0
  fi

  saToken=$(stdk8sGetSAToken) || return 1
  k8sNamespace=$(stdk8sGetNamespace) || return 1

  k8sMetadata=$(curl -m $curlMaxTime -sSk -H "Authorization: Bearer $saToken" https://"${KUBERNETES_SERVICE_HOST}":"${KUBERNETES_SERVICE_PORT}"/api/v1/namespaces/"${k8sNamespace}"/pods 2>&1)

  exitCode=$?
  if [[ $exitCode -eq 28 ]]; then #curl timeouts
    stdLogErr "Error querying k8s API, reason:\n$k8sMetadata"
    return 3 #This enables retries
  elif [[ ! $exitCode -eq 0 ]]; then
    stdLogErr "Error querying k8s API, reason:\n$k8sMetadata"
    return 1
  fi

  stdIsJSONvalid "$k8sMetadata" || return 1

  local apiResponseCode=$(echo "$k8sMetadata" | jq ".code")
  # code is present in the json object in case of error, or not present if success
  if [[ "$apiResponseCode" != "null" ]]; then
    stdLogErr "Error during querying pod specification via API:\n$k8sMetadata"
    return 1
  fi

  local podsSpec=""
  podsSpec=$(echo "$k8sMetadata" | jq ".items") || return 1
  local podItem=""
  local containerStatuses=""
  local arrayLength=$(echo "$podsSpec" | jq 'length')
  local containerStatusesLength=""
  local currContainerID=""
  local podName=""

  for ((i = 0; i < "$arrayLength"; i++)); do
    #podItem=$(echo "$podsSpec" | jq ".["$i"]" ) || return 1
    containerStatuses=$(echo "$podsSpec" | jq ".["$i"].status.containerStatuses") || return 1
    #containerStatuses=$(stdGetValueFromJson "$podItem" ".status.containerStatuses" "raw" ) || return 1

    containerStatusesLength=$(echo "$containerStatuses" | jq 'length')
    for ((j = 0; j < "$containerStatusesLength"; j++)); do
      currContainerID=$(echo "$containerStatuses" | jq ".["$j"].containerID" | sed 's/\"//g' | sed -En 's/docker:\/\/(.*)/\1/gip') || return 1

      if [[ "$containerID" == "$currContainerID" ]]; then
        podName=$(echo "$podsSpec" | jq ".["$i"].metadata.name" | sed 's/\"//g') || return 1
        echo "$podName"
        return 0
      fi
    done
  done

  stdLogErr "Can't find pod name for container ID '$containerID'"
  return 2

}

function stdk8sGetPodSpecification() {

  local podName="$1"
  local saToken=""
  local k8sNamespace=""
  local k8sMetadata=""
  local curlMaxTime=${K8S_TIMEOUT:="5"}
  local exitCode=""

  saToken=$(stdk8sGetSAToken) || return 1

  k8sNamespace=$(stdk8sGetNamespace) || return 1

  if [[ -z "$podName" ]]; then
    if [[ -z "$POD_NAME" ]]; then
      podName=$(stdk8sGetPodNameByContainerID)
      exitCode="$?"
      if [[ ! "$exitCode" -eq 0 ]]; then
        return "$exitCode"
      fi
    else
      podName="$POD_NAME"
    fi
  fi

  k8sMetadata=$(curl -m $curlMaxTime -sSk -H "Authorization: Bearer $saToken" https://"${KUBERNETES_SERVICE_HOST}":"${KUBERNETES_SERVICE_PORT}"/api/v1/namespaces/"${k8sNamespace}"/pods/"${podName}" 2>&1)
  exitCode=$?
  if [[ ! $exitCode -eq 0 ]]; then
    stdLogErr "Error querying k8s API, reason:\n$k8sMetadata"
    return 1
  fi

  stdIsJSONvalid "$k8sMetadata" || return 1

  local apiResponseCode=$(echo "$k8sMetadata" | jq ".code")
  # code is present in the json object in case of error, or not present if success
  if [[ "$apiResponseCode" != "null" ]]; then
    stdLogErr "Error during querying pod specification via API:\n$k8sMetadata"
    return 1
  fi

  echo "$k8sMetadata"
  return 0

}

function stdk8sGetPodAnnotations() {

  local podSpec=""
  local annotantions=""
  podSpec=$(stdk8sGetPodSpecification) || return 1

  annotations=$(stdGetValueFromJson "$podSpec" "metadata.annotations" "object" "true") || return 1

  echo "$annotations"
  return 0
}

function stdk8sGetNamespaceSpecification() {

  local nmspSpec=""
  local saToken=""
  local k8sNamespace=""
  local k8sMetadata=""
  local curlMaxTime=${K8S_TIMEOUT:="5"}

  saToken=$(stdk8sGetSAToken) || return 1
  k8sNamespace=$(stdk8sGetNamespace) || return 1

  nmspSpec=$(curl -m $curlMaxTime -sSk -H "Authorization: Bearer $saToken" https://"${KUBERNETES_SERVICE_HOST}":"${KUBERNETES_SERVICE_PORT}"/api/v1/namespaces/"${k8sNamespace}" 2>&1)
  exitCode=$?
  if [[ ! $exitCode -eq 0 ]]; then
    stdLogErr "Error querying k8s API, reason:\n$nmspSpec"
    return 1+

  fi

  stdIsJSONvalid "$nmspSpec" || return 1

  local apiResponseCode=$(echo "$nmspSpec" | jq ".code")
  # code is present in the json object in case of error, or not present if success
  if [[ "$apiResponseCode" != "null" ]]; then
    stdLogErr "Error during querying pod specification via API:\n$nmspSpec"
    return 1
  fi

  echo "$nmspSpec"
  return 0
}

function stdk8sGetNamespaceListByRegexPattern() {
  local RETURN="$1"
  local namespacePattern="$2"
  local saToken="$3"
  local apiEndpoint="$4"
  local namespaceSeparator="$5"

  local apiResponseCode=""
  local namespacesSpec=""
  local retValue=""

  local includedNamespacesList=""
  local curlMaxTime=${K8S_TIMEOUT:="5"}

  if [[ -z "$namespaceSeparator" ]]; then
    namespaceSeparator="|"
  fi

  namespacesSpec=$(curl -m $curlMaxTime -sSk -H "Authorization: Bearer $saToken" \
    "${apiEndpoint}"/api/v1/namespaces/)
  stdIsJSONvalid "$namespacesSpec" || return 1

  apiResponseCode=$(stdGetValueFromJson "$namespacesSpec" "code")
  # code is present in the json object in case of error, or not present if success
  if [[ "$apiResponseCode" != "null" ]]; then
    stdLogErr "Error during querying namespaces specification via API:\n$namespacesSpec"
    return 1
  fi

  nmspItems=$(stdGetValueFromJson "$namespacesSpec" "items" "raw") || return 1

  local arrayLength=$(echo "$nmspItems" | jq 'length')
  for ((i = 0; i < "$arrayLength"; i++)); do
    namespaceName=$(stdGetValueFromJson "$nmspItems" "["$i"].metadata.name") || return 1
    if [[ "$namespaceName" =~ $namespacePattern ]]; then
      retValue="$retValue""$namespaceSeparator""${namespaceName}"
    else
      stdLogDebug "Namespace '$namespaceName' filtered."
    fi

  done

  eval "$RETURN=\"$retValue\""
  return 0

}

function stdk8sGetContainerLogicalLocation() {

  local containerName="$1"
  local podName="$2"
  local namespace="$3"
  local podSpec="$4"

  if [[ -z "$namespace" ]]; then
    if [[ ! -z "$NAMESPACE" ]]; then
      namespace="$NAMESPACE"
    elif [[ -z "$NAMESPACE" && -f /var/run/s6/container_environment/NAMESPACE ]]; then
      namespace=$(cat "/var/run/s6/container_environment/NAMESPACE")
    else
      stdLogErr "Can't detect container name (env var. 'NAMESPACE' is not set and '/var/run/s6/container_environment/NAMESPACE' is not exist)"
      return 1
    fi
  fi

  if [[ -z "$podName" ]]; then
    if [[ ! -z "$POD_NAME" ]]; then
      podName="$POD_NAME"
    elif [[ -z "$POD_NAME" && -f /var/run/s6/container_environment/POD_NAME ]]; then
      podName=$(cat "/var/run/s6/container_environment/POD_NAME")
    else
      stdLogErr "Can't detect container name (env var. 'POD_NAME' is not set and '/var/run/s6/container_environment/POD_NAME' is not exist)"
      return 1
    fi
  fi

  if [[ -z "$containerName" ]]; then
    if [[ ! -z "$CONTAINER_NAME" ]]; then
      containerName="$CONTAINER_NAME"
    elif [[ -z "$CONTAINER_NAME" && -f /var/run/s6/container_environment/CONTAINER_NAME ]]; then
      containerName=$(cat "/var/run/s6/container_environment/CONTAINER_NAME")
    else
      stdLogErr "Can't detect container name (env var. 'CONTAINER_NAME' is not set and '/var/run/s6/container_environment/CONTAINER_NAME' is not exist)"
      return 1
    fi
  fi

  if [[ -z "$podSpec" ]]; then
    if [[ ! -z "$K8S_METADATA" ]]; then
      podSpec="$K8S_METADATA"
    elif [[ -z "$K8S_METADATA" && -f /var/run/s6/container_environment/K8S_METADATA ]]; then
      podSpec=$(cat "/var/run/s6/container_environment/K8S_METADATA")
    else
      podSpec=$(stdk8sGetPodSpecification) || return 1
    fi
  fi

  #Strip variable part from pod name
  local podOwner=""
  local podOwnerKind=""
  podOwner=$(stdGetValueFromJson "$podSpec" ".metadata.ownerReferences[0]" "raw" 2>/dev/null)
  if [[ "$podOwner" == "null" ]]; then
    podOwnerName="$podName"
  else
    podOwnerKind=$(stdGetValueFromJson "$podOwner" ".kind")
    if [[ "$podOwnerKind" == "DaemonSet" || "$podOwnerKind" == "StatefulSet" || "$podOwnerKind" == "Job" ]]; then
      podOwnerName=$(stdGetValueFromJson "$podOwner" ".name")
    else
      podOwnerName=$(stdGetValueFromJson "$podOwner" ".name" | sed -E 's/\-[^\-]+$//g')
    fi
  fi

  echo "$namespace"."$podOwnerName"."$containerName"

  return 0

}
###################

function stdParseCICommitRefName() {

  local ciCommitRefName="$1"
  local RETURN1="$2"
  local RETURN2="$3"
  local RETURN3="$4"
  local RETURN4="$5"

  local productVersion=""
  local templateVersion=""
  local baseServiceVersion=""
  local customServcieVersion=""

  local templatePart=""
  local baseSvcPart=""
  local customSvcPart=""

  productVersion=$(echo "${ciCommitRefName}" | sed -En 's/([^-]+)?-?([0-9]+)?\.?([0-9]+)?\.?([0-9]+)?/\1/p')

  local templatePart=$(echo "${ciCommitRefName}" | sed -En 's/([^-]+)?-?([0-9]+)?\.?([0-9]+)?\.?([0-9]+)?/\2/p')
  if [[ -z "$templatePart" ]]; then
    templateVersion=""
  else
    templateVersion=${productVersion}-${templatePart}
  fi

  baseSvcPart=$(echo "${ciCommitRefName}" | sed -En 's/([^-]+)?-?([0-9]+)?\.?([0-9]+)?\.?([0-9]+)?/\3/p')
  if [[ -z "$baseSvcPart" ]]; then
    baseServiceVersion=""
  else
    baseServiceVersion=${templateVersion}.${baseSvcPart}
  fi

  customSvcPart=$(echo "${ciCommitRefName}" | sed -En 's/([^-]+)?-?([0-9]+)?\.?([0-9]+)?\.?([0-9]+)?/\4/p')
  if [[ -z "$customSvcPart" ]]; then
    customServcieVersion=""
  else
    customServcieVersion=${baseServiceVersion}.${customSvcPart}
  fi

  if [[ ! -z "$RETURN1" ]]; then
    eval "$RETURN1=$productVersion"
  fi

  if [[ ! -z "$RETURN2" ]]; then
    eval "$RETURN2=$templateVersion"
  fi

  if [[ ! -z "$RETURN3" ]]; then
    eval "$RETURN3=$baseServiceVersion"
  fi

  if [[ ! -z "$RETURN4" ]]; then
    eval "$RETURN4=$customServcieVersion"
  fi
}

#############
function _stdInit() {

  if ! [[ -z "$@" ]]; then
    _stdLogLevel=$1
    _stdMsgIdent=$2
    _stdLogOutput=$3
    _stdColoredOutput=$4
  fi

  _stdNoColor='\033[0m'

  case "$_stdLogLevel" in
    "TRACE")
      _stdLogLevelNumeric=0
      _stdLogLevelID="T"
      ;;
    "DEBUG")
      _stdLogLevelNumeric=1
      _stdLogLevelID="D"
      ;;

    "INFO")
      _stdLogLevelNumeric=2
      _stdLogLevelID="I"
      ;;

    "WARN")
      _stdLogLevelNumeric=3
      _stdLogLevelID="W"
      ;;

    "ERROR")
      _stdLogLevelNumeric=4
      _stdLogLevelID="E"
      ;;
    *)
      _stdLogLevel="INFO"
      _stdLogLevelNumeric=2
      _stdLogLevelID="I"
      ;;
  esac

  if [[ -z "$_stdColoredOutput" ]]; then
    _stdColoredOutput="$false"
  fi

  if [[ -z "$_stdMsgIdent" ]]; then
    _stdMsgIdent=""
  fi

  if [[ -z "$_stdLogOutput" ]]; then
    _stdLogOutput='/dev/stdout'
  fi

}
#############

_stdInit "$@" || true
