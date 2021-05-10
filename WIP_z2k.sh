#!/bin/bash

# Zero to Kubernetes (without vagrant)
# not ready yet (vagrant user is used in scripts)
set -ex

ORIGINAL_IFS=$IFS
# shellcheck disable=SC2183
comment=$(printf "%30s");


function validate() {
    if [ -f .env ]; then
        # shellcheck disable=SC1091
        . .env
        WORKER_NODES="${WORKER_NODES:-}"
        CONTROLLER_NODES="${CONTROLLER_NODES:-}"
    fi
    # TODO: replace /etc/hosts with ${ETC_HOSTS}
    # TODO: use "ssh_config" for "userless" ssh connections
    echo "Not ready yet :("
    echo "only using vagrant for now"
    exit 1
}

function main() {
    IFS=" " read -r -a _scripts <<< "$(find scripts/* -maxdepth 1 -print0 | sort -z | xargs --null)"
    for _script in "${_scripts[@]}"; do
        echo "${comment// /#}"
        echo "running: ${_script}"
        bash "${_script}"
        echo "finished: ${_script}"
        echo "${comment// /#}"
    done
    IFS=$ORIGINAL_IFS

}

validate
main
