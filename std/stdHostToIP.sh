#!/bin/bash

function stdHostToIP() {
    local host=$1

    test -n "$(which dig)" \
        && cmd='dig +short' \
        || cmd='getent ahostsv4'

    echo -n $($cmd $host | head -1 | cut -d ' ' -f 1)

    return 0
}
