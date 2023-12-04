#!/bin/bash

SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

STD_GIT_HOST=${STD_GIT_HOST:="$GITLAB_HOST"}
STD_GIT_ROOT=${STD_GIT_ROOT:="$GITLAB_ROOT"}
STD_GIT_LOGIN=${STD_GIT_LOGIN:="$GITLAB_LOGIN"}
STD_GIT_PASSWORD=${STD_GIT_PASSWORD:="$GITLAB_PASSWORD"}
STD_GIT_USER_EMAIL=${STD_GIT_USER_EMAIL:="$GITLAB_USER_EMAIL"}
STD_GIT_USER=${STD_GIT_USER:="$GITLAB_USER_NAME"}

. $SCRIPTS_DIR/std/utils.sh

function stdGitCloneCheckout() {

    local repoPath="$1"
    local repoRef="$2"
    local removeProject="$3"

    local projectName=$(echo "$repoPath" | grep -Eio '[^\/]+' | tail -1)

    echo -e "machine $STD_GIT_HOST\nlogin $STD_GIT_LOGIN\npassword $STD_GIT_PASSWORD" >> ~/.netrc

    git config --global user.email "$STD_GIT_USER_EMAIL"
    git config --global user.name "$STD_GIT_USER"

    local repoURL="${STD_GIT_ROOT}/${repoPath}.git"
    stdLogDebug "Cloning repo: '$repoURL', ref: '$repoRef'..."

    if [[ -d "${projectName}" ]] && [[ "$removeProject" == "true" ]]; then
       stdLogDebug "Removing ${projectName}..."
       rm -rf "${projectName}"
    fi

    local __out=""
    git clone "$repoURL" >__stdGitClone.out 2>&1
    if ( [[ ! $? -eq 0 ]] ); then
     __out=$(cat __stdGitClone.out)
     stdLogErr "$__out"
     if [[ ! $? -eq 128 ]]; then # 128 - means that folder already exist
        return 1
     fi
    fi

    cd "${projectName}"
    git checkout "${repoRef}" >../__stdGitClone.out 2>&1
    if ( [[ ! $? -eq 0 ]] ); then
        __out=$(cat ../__stdGitClone.out)
        stdLogErr "$__out"
        return 1
    fi

    cd ..

    local content=$(ls -la "${projectName}")
    stdLogDebug "Content of  '${repoPath}', ref '$repoRef':\n=========\n$content\n========="

    rm -rf __stdGitClone.out

}

function stdGitRepoExist(){
    #Checking if state repo is available
    echo -e "machine $STD_GIT_HOST\nlogin $STD_GIT_LOGIN\npassword $STD_GIT_PASSWORD" >> ~/.netrc

    git config --global user.email "$STD_GIT_USER_EMAIL"
    git config --global user.name "$STD_GIT_USER"

    stdLogDebug "Checking if $STD_GIT_HOST hosts the following repo: $1"

    git ls-remote -h "$1" 1> /dev/null || return 1
    return 0
}