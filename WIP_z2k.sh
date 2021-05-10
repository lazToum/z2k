#!/bin/bash
# shellcheck disable=SC1091

# Zero to Kubernetes (without vagrant)
# use vagrant only to generate the vms (cluters,workers, lb)
# not well tested yet

set -ex
_HERE="$(dirname "$(readlink -f "$0")")"
if [ "${_HERE}" = "." ]; then
  _HERE="$(pwd)"
fi

# shellcheck disable=SC2183
comment=$(printf "%30s");


function pre_check() {
    if [ ! -f "${_HERE}/.env" ]; then
      echo "Generate a ${_HERE}/.env file based on ${_HERE}/.env.template"
      exit 1
    else
      . "${_HERE}/.env"
    fi
    if [ ! -f  "${_HERE}/etc.hosts" ]; then
      echo "Generate a ${_HERE}/.etc.hosts file based on ${_HERE}/etc.hosts.template"
      exit 1
    else
      export ETC_HOSTS="${_HERE}/etc.hosts"
    fi
    if [ ! -f "${_HERE}/ssh.conf" ]; then
      echo "Generate a ${_HERE}/ssh.conf file based on ${_HERE}/ssh.conf"
      exit 1
    else
      if [ ! -f ~/.ssh/config ]; then
        mkdir -p ~/.ssh/ && touch ~/.ssh/config
      fi
      if [ ! "$(grep -i "${_HERE}/ssh.conf" ~/.ssh/config 2>/dev/null || :)" ];then
        cp ~/.ssh/config ~/.ssh/config.prez2k && echo "Include ${_HERE}/ssh.conf" | cat - ~/.ssh/config > temp && mv temp  ~/.ssh/config
      fi
    fi
#   TODO?: also check ssh connections on all hosts before starting?
}

function main() {
    ORIGINAL_IFS=$IFS
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

pre_check
main
