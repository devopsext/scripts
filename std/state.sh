#!/bin/bash

SCRIPTS_DIR=${SCRIPTS_DIR="/scripts"}

STD_STATE_GIT_HOST=${STD_STATE_GIT_HOST:="$GITLAB_HOST"}
STD_STATE_GIT_LOGIN=${STD_STATE_GIT_LOGIN:="$GITLAB_LOGIN"}
STD_STATE_GIT_PASSWORD=${STD_STATE_GIT_PASSWORD:="$GITLAB_PASSWORD"}
STD_STATE_GIT_EMAIL=${STD_STATE_GIT_EMAIL:="$GITLAB_USER_EMAIL"}
STD_STATE_GIT_USER=${STD_STATE_GIT_USER:="$GITLAB_USER_NAME"}
STD_STATE_REF_NAME=${STD_STATE_REF_NAME:="$GITLAB_COMMIT_REF_NAME"}

STD_STATE_NAME=${STD_STATE_NAME:="$GITLAB_PROJECT_NAME"}
STD_STATE_REPO=${STD_STATE_REPO:=""}
STD_STATE_GROUP=${STD_STATE_GROUP:=""}
STD_STATE_BRANCH=${STD_STATE_BRANCH:=""}
STD_STATE_COMMENT=${STD_STATE_COMMENT:="New state for job $GITLAB_JOB_ID"}
STD_STATE_PATTERN=${STD_STATE_PATTERN:=".*"}
STD_STATE_DEFAULT=${STD_STATE_DEFAULT:="master"}
STD_STATE_LOAD_TAG=${STD_STATE_LOAD_TAG:=""}
STD_STATE_LOAD_DIR=${STD_STATE_LOAD_DIR:="load"}
STD_STATE_SAVE_DIR=${STD_STATE_SAVE_DIR:="save"}
STD_STATE_STATE_DIR=${STD_STATE_STATE_DIR:="state"}
STD_STATE_SAVE_ENABLED=${STD_STATE_SAVE_ENABLED:="true"}
STD_STATE_LOAD_ENABLED=${STD_STATE_LOAD_ENABLED:="true"}

. $SCRIPTS_DIR/std/utils.sh

function stdStateSave() {

  if [[ "$STD_STATE_SAVE_ENABLED" != "true" ]]; then
    return
  fi

  local STATE_DIR="$1"
  local repoStatusBeforeCommit=""

  if [[ "$STATE_DIR" == "" ]]; then
    STATE_DIR="$STD_STATE_STATE_DIR"
  fi

  if [ -d "$STATE_DIR" ]; then

    stdLogInfo "Saving state..."

    local STATE_REPO="$STD_STATE_REPO"
    local STATE_GROUP="$STD_STATE_GROUP"
    local SAVE_DIR="$STD_STATE_SAVE_DIR"

    if [[ "$STATE_REPO" == "" ]] && [[ "$STATE_GROUP" != "" ]]; then

      STATE_REPO="$STATE_GROUP/$STD_STATE_NAME.git"
    fi

    if [ -d "$SAVE_DIR" ]; then

      rm -rf "$SAVE_DIR"
    fi

    if [[ "$STATE_REPO" != "" ]]; then

      local PWD_OLD="$PWD"

      echo -e "machine $STD_STATE_GIT_HOST\nlogin $STD_STATE_GIT_LOGIN\npassword $STD_STATE_GIT_PASSWORD" >> ~/.netrc

      if [[ -z "$STD_STATE_GIT_EMAIL" ]]; then
        stdLogWarn "'STD_STATE_GIT_EMAIL' env. var is not set!"
      fi

      if [[ -z "$STD_STATE_GIT_USER" ]]; then
        stdLogWarn "'STD_STATE_GIT_USER' env. var is not set!"
      fi

      git config --global user.email "$STD_STATE_GIT_EMAIL"
      git config --global user.name "$STD_STATE_GIT_USER"

      stdLogInfo "Cloning '$STATE_REPO' into '$SAVE_DIR'"
      stdExec "git clone '$STATE_REPO' '$SAVE_DIR'" || return 1

      cd "$SAVE_DIR"

      local STATE_BRANCH="$STD_STATE_BRANCH"
      if [[ "$STATE_BRANCH" == "" ]]; then

        STATE_BRANCH="${STD_STATE_REF_NAME%-*}"
      fi

      local STATE_PATTERN="$STD_STATE_PATTERN"
      local STATE_COMMENT="$STD_STATE_COMMENT"

      stdLogDebug "Looking for state branch '$STATE_BRANCH'..."

      local PATH_STATE="$PWD_OLD/$STATE_DIR/"
      local PATH_LEN=${#PATH_STATE}

      local EXISTS=$(git ls-remote --heads origin "$STATE_BRANCH" | wc -l)

      if [[ "$EXISTS" == "0" ]]; then

        stdLogDebug "State branch '$STATE_BRANCH' is not found. Adding files..."

        if [[ "$STD_STATE_DEFAULT" != "" ]]; then
          stdLogDebug "Checking out '$STD_STATE_DEFAULT'..."
          stdExec "git checkout -f  '$STD_STATE_DEFAULT'" || return 1
          stdExec "git fetch" || return 1
        fi

        stdLogDebug "Checking out '$STATE_BRANCH'..."
        stdExec "git checkout -f  -b '$STATE_BRANCH'" || return 1

        for FILE in $(find "$PATH_STATE" -maxdepth 1 | tail -n +2); do
          DEST="${FILE:$PATH_LEN}"
          rm -rf "$DEST" || true
          stdLogDebug "Copying $FILE to $DEST..." && cp -rfv "$FILE" "$DEST"
        done

        git rm --ignore-unmatch *.md

        stdLogDebug "Adding..."
        stdExec "git add ." || return 1

        repoStatusBeforeCommit=$(git status || return 1)
        stdLogDebug "Repo status before commit:\n$repoStatusBeforeCommit"

        stdLogInfo "Committing changes..."
        stdExec "git commit -m '$STATE_COMMENT'" || true

        stdLogInfo "Pushing '$STATE_BRANCH'..."
        stdExec "git push -u origin '$STATE_BRANCH'" || return 1

      else

        stdLogDebug "State branch $STATE_BRANCH is found. Adding files..."

        stdLogDebug "Checking out and pulling '$STATE_BRANCH'..."
        stdExec "git checkout -f '$STATE_BRANCH'" || return  1
        stdExec "git pull" || return 1
        local loadedContent=$(ls -la ./)
        stdLogTrace "Repo content:\n=============\n$loadedContent\n============="

        for FILE in $(find "$PATH_STATE" -maxdepth 1 | tail -n +2); do
          DEST="${FILE:$PATH_LEN}"
          stdLogTrace "Removing file '$DEST'"
          rm -rf "$DEST" || true
          stdLogDebug "Copying $FILE to $DEST..." && cp -rfv "$FILE" "$DEST"
        done

        stdLogInfo "Committing changes..."
        stdExec "git add ." || retrun 1
        repoStatusBeforeCommit=$(git status || return 1)
        stdLogDebug "Repo status before commit:\n$repoStatusBeforeCommit"

        stdExec "git commit -m '$STATE_COMMENT'" || true

        stdLogInfo "Pushing into '$STATE_REPO'..."
        stdExec "git push" || return 1
      fi

      local STATE_TAG="$STATE_BRANCH-$(date +%Y%m%d%H%M%S)"

      stdLogInfo "Adding and pushing state tag '$STATE_TAG'..."

      stdExec "git tag '$STATE_TAG'" || return 1
      stdExec "git push origin --tags" || return 1

      cd "$PWD_OLD"
    else

      stdLogWarn "State repository is not found. Skipped."
    fi
  else

    stdLogWarn "State directory is not found. Skipped."
  fi

  rm -f $EXIT_FILE
}

function stdStateLoad() {

  if [[ "$STD_STATE_LOAD_ENABLED" != "true" ]]; then
    return
  fi

  local LOAD_DIR="$1"

  if [[ "$LOAD_DIR" == "" ]]; then
    LOAD_DIR="$STD_STATE_LOAD_DIR"
  fi

  stdLogInfo "Loading state..."

  if [[ "$LOAD_DIR" != "" ]]; then

    local STATE_REPO="$STD_STATE_REPO"
    local STATE_GROUP="$STD_STATE_GROUP"

    if [[ "$STATE_REPO" == "" ]] && [[ "$STATE_GROUP" != "" ]]; then

      STATE_REPO="$STATE_GROUP/$STD_STATE_NAME.git"
    fi

    if [ -d "$LOAD_DIR" ]; then

      rm -rf "$LOAD_DIR"
    fi

    if [[ "$STATE_REPO" != "" ]]; then

      local PWD_OLD="$PWD"

      echo -e "machine $STD_STATE_GIT_HOST\nlogin $STD_STATE_GIT_LOGIN\npassword $STD_STATE_GIT_PASSWORD" >> ~/.netrc

      if [[ -z "$STD_STATE_GIT_EMAIL" ]]; then
        stdLogWarn "'STD_STATE_GIT_EMAIL' env. var is not set!"
      fi

      if [[ -z "$STD_STATE_GIT_USER" ]]; then
        stdLogWarn "'STD_STATE_GIT_USER' env. var is not set!"
      fi

      git config --global user.email "$STD_STATE_GIT_EMAIL"
      git config --global user.name "$STD_STATE_GIT_USER"

      stdLogInfo "Cloning '$STATE_REPO' into '$LOAD_DIR'"

      stdExec "git clone $STATE_REPO $LOAD_DIR" || exit 1

      cd "$LOAD_DIR"

      local STATE_TAG="$STD_STATE_LOAD_TAG"
      if [[ "$STATE_TAG" == "" ]]; then

        local STATE_PREFIX="$STD_STATE_BRANCH"
        if [[ "$STATE_PREFIX" == "" ]]; then
          STATE_PREFIX="${GITLAB_COMMIT_REF_NAME%-*}"
        fi

        if [[ "$STATE_PREFIX" != "" ]]; then
          STATE_PREFIX="$STATE_PREFIX-"
        fi

        stdLogDebug "Looking for state tag prefix '$STATE_PREFIX'..."

        local STATE_SUFFIX=$(git ls-remote --tags origin | grep "refs/tags/$STATE_PREFIX" | awk -F '-' '{printf "%s\n", $NF}' | sort -rn | head -1)

        if [[ "$STATE_SUFFIX" != "" ]]; then

          local STATE_TAG="$STATE_PREFIX$STATE_SUFFIX"

          stdLogDebug "Found state tag: '$STATE_TAG'..."
        fi
      fi

      if [[ "$STATE_TAG" != "" ]]; then

        stdLogInfo "Checking out tag '$STATE_TAG'..."
        stdExec "git checkout -f  tags/$STATE_TAG -b $(date +%Y%m%d%H%M%S)" || return 1

      else

        stdLogWarn "State tag is not found. Skipped."
      fi

      cd "$PWD_OLD"
    else

      stdLogWarn "State repository is not found. Skipped."
    fi
  else

    stdLogWarn "Load directory is empty. Skipped."
  fi

}
