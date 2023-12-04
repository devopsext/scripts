#!/bin/bash
SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

SELF_DIR=$(dirname "$0" || true)
SELF_FILE=$(basename "$0" || true)

SELF_LINK=$(readlink "$SELF_DIR/$SELF_FILE" || true)

if [ "$SELF_LINK" != "" ] && [ "$SELF_LINK" != "$SELF_DIR/$SELF_FILE" ]; then
  SELF_DIR=$(dirname "$SELF_LINK")
  SELF_FILE=$(basename "$SELF_LINK")
fi

STD_LOG_IDENT=${STD_LOG_IDENT:="[${SELF_FILE}]"}
STD_LOG_LEVEL=${STD_LOG_LEVEL:="INFO"}
STD_LOG_OUTPUT=${STD_LOG_OUTPUT:="/dev/stdout"}
STD_LOG_COLORED=${STD_LOG_COLORED:="true"}

. $SCRIPTS_DIR/std/stdlib.sh "$STD_LOG_LEVEL" "$STD_LOG_IDENT" "$STD_LOG_OUTPUT" "$STD_LOG_COLORED"

function stdCallback() {

  local CALLBACKS="$1"

  stdLogTrace "stdCallback triggered with CALLBACKS = '$CALLBACKS'..."

  shift

  for CALLBACK in $CALLBACKS; do

    if [[ $(type -t "$CALLBACK") == function ]]; then

      stdLogInfo "Executing callback '$CALLBACK'..." && eval "$CALLBACK" "$@"
    else
      stdLogTrace "'$CALLBACK' is not a function, skipped..."
    fi
  done
}

function stdGenerateCertificates() {

  local SERVICE="$1"
  local NAMESPACE="$2"
  local KEY_FILE="$3"
  local CRT_FILE="$4"

  if [[ "$SERVICE" == "" ]] || [[ "$NAMESPACE" == "" ]]; then
    stdLogErr "Namespace/Service is not specified. Generation skipped."
    return
  fi

  if [[ "$KEY_FILE" == "" ]] || [[ "$CRT_FILE" == "" ]]; then
    stdLogErr "Key/Crt file name is not specified. Generation skipped."
    return
  fi

  tmpdir=$(mktemp -d)

  cat <<EOF >>"${tmpdir}/csr.conf"
  [req]
  req_extensions = v3_req
  distinguished_name = req_distinguished_name
  [req_distinguished_name]
  [ v3_req ]
  basicConstraints = CA:FALSE
  keyUsage = nonRepudiation, digitalSignature, keyEncipherment
  extendedKeyUsage = serverAuth
  subjectAltName = @alt_names
  [alt_names]
  DNS.1 = ${SERVICE}
  DNS.2 = ${SERVICE}.${NAMESPACE}
  DNS.3 = ${SERVICE}.${NAMESPACE}.svc
EOF

  local __out=""

  openssl genrsa -out "${KEY_FILE}" 2048 >__openSsl.out 2>&1
  __out=$(cat __openSsl.out)
  if [[ ! "$?" -eq 0 ]]; then
    stdLogErr "$__out"
    return 1
  else
    stdLogDebug "'openssl genrsa' output:\n$__out"
  fi

  openssl req -new -key "${KEY_FILE}" -subj "/CN=${SERVICE}.${NAMESPACE}.svc" -out "${tmpdir}/${SERVICE}.csr" -config "${tmpdir}/csr.conf" >__openSsl.out 2>&1
  __out=$(cat __openSsl.out)
  if [[ ! "$?" -eq 0 ]]; then
    stdLogErr "$__out"
    return 1
  else
    stdLogDebug "'openssl req -new -key' output:\n$__out"
  fi

  openssl x509 -signkey "${KEY_FILE}" -in "${tmpdir}/${SERVICE}.csr" -req -days 365 -out "${CRT_FILE}" >__openSsl.out 2>&1
  __out=$(cat __openSsl.out)
  if [[ ! "$?" -eq 0 ]]; then
    stdLogErr "$__out"
    return 1
  else
    stdLogDebug "'openssl x509 -signkey' output:\n$__out"
  fi

  rm -rf __openSsl.out
}

function stdExec() {
  local command="$1"
  local stdOutputOut="$2"
  local stdErrorOut="$3"
  local exitCodeOut="$4"
  local silentMode="$5"

  local stdoutFile="/tmp/__$$.stdout"
  local stderrFile="/tmp/__$$.stderr"
  local __stdEOut=""
  local __stdEErr=""
  local __stdEExitCode=""

  silentMode=${silentMode:="false"}

  if [[ ! -d "/tmp" ]]; then
    mkdir -p /tmp
  fi

  eval "${command} 2>${stderrFile} 1>${stdoutFile}" || __stdEExitCode="$?"
  if [[ -z "$__stdEExitCode" ]]; then
    __stdEExitCode="$?"
  fi

  __stdEOut=$(cat ${stdoutFile}) && rm -rf ${stdoutFile}
  __stdEErr=$(cat ${stderrFile}) && rm -rf ${stderrFile}

  #Setting outputs
  if [[ -n "$stdOutputOut" ]]; then
    eval "$stdOutputOut='${__stdEOut}'"
  fi

  if [[ -n "$stdErrorOut" ]]; then
    eval "$stdErrorOut='${__stdEErr}'"
  fi

  #Building output string for logging
  local outMixed=""
  if [[ -n "$__stdEOut" ]]; then
    outMixed="${outMixed}${__stdEOut}"
  fi

  if [[ -n "$__stdEErr" ]]; then
    outMixed="${outMixed}${__stdEErr}"
  fi

  if [[ "$silentMode" != "true" ]]; then
    if [[ "$__stdEExitCode" -ne 0 ]]; then
      stdLogErr "Output from '${command}':\n${outMixed}"
    elif [[ -n "$outMixed" ]]; then
      stdLogDebug "Output from '${command}':\n${outMixed}"
    fi
  fi

  if [[ -n "$exitCodeOut" ]]; then
    eval "$exitCodeOut=${__stdEExitCode}"
  fi
  return "$__stdEExitCode"
}

function stdCheckMultipleExitCode() { #Usage pattern stdCheckMultipleExitCode $? '0|9' || logExit # 0-ok, 9-already exist

  shopt -s extglob # enables pattern lists like +(...|...)
  local exitCode="$1"
  local goodCodes='+('"$2"')' # 0|1|3
  local badCodes='+('"$3"')'  # 2|4|6
  if [ -z "$3" ]; then
    badCodes="*"
  fi

  case "$exitCode" in
    "$goodCodes") return 0 ;;
    "$badCodes") return 1 ;;
    *) return 1 ;;
  esac
}

function stdCheckIfVarsEmpty() {
  local value=""
  local array=""
  #Precheck for cluster instance specific variables
  oldIFS="$IFS"
  if [[ ! -z "$2" ]]; then
    IFS="$2"
  else
    IFS=","
  fi

  read -r -a array <<<$(echo "$1")

  for var in "${array[@]}"; do
    value=$(eval echo \$"$var")
    if [[ -z "$value" ]]; then
      stdLogErr "Variable '$var' is not set"
      IFS="$oldIFS"
      return 1
    else
      stdLogTrace "Variable '$var' checked..."
    fi
  done
  IFS="$oldIFS"
  return 0
}

