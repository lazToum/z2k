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

function repeat_string() {
  local string="${1:-#}"
  local times="${2:-30}"
  local repeat;
  repeat=$(printf "%${times}s");
  echo "${repeat// /${string}}"
}

function etc_hosts() {
  if [ ! -f "${_HERE}/etc.hosts" ]; then
    echo "Generate a ${_HERE}/.etc.hosts file based on ${_HERE}/etc.hosts.template"
    exit 1
  else
    export ETC_HOSTS="${_HERE}/etc.hosts"
  fi
}

function ssh_config() {
  if [ ! -f "${_HERE}/ssh.conf" ]; then
    echo "Generate a ${_HERE}/ssh.conf file based on ${_HERE}/ssh.conf"
    exit 1
  else
    if [ ! -f ~/.ssh/config ]; then
      mkdir -p ~/.ssh/ && touch ~/.ssh/config
    fi
    if [ "$(grep -i "${_HERE}/ssh.conf" ~/.ssh/config 2>/dev/null || echo "no")" = "no" ]; then
      cp ~/.ssh/config ~/.ssh/config.prez2k && echo "Include ${_HERE}/ssh.conf" | cat - ~/.ssh/config >temp && mv temp ~/.ssh/config
    fi
  fi
}

function dot_env() {
  if [ ! -f "${_HERE}/.env" ]; then
    echo "Generate a ${_HERE}/.env file based on ${_HERE}/.env.template"
    exit 1
  else
    . "${_HERE}/.env"
  fi
}

function pre_check() {
  dot_env
  etc_hosts
  ssh_config
  #   TODO?: also check ssh connections on all hosts before starting?
}

function main() {
  ORIGINAL_IFS=$IFS
  IFS=" " read -r -a _scripts <<<"$(find scripts/* -maxdepth 1 -print0 | sort -z | xargs --null)"
  for _script in "${_scripts[@]}"; do
    repeat_string "#" 40
    echo "running: ${_script}"
    bash "${_script}"
    echo "finished: ${_script}"
    repeat_string "#" 40
  done
  IFS=$ORIGINAL_IFS
}

if [ ! "${1}" = "--skip-checks" ]; then
  # from vagrant, or with "valid" /etc/hosts and ~/.ssh/config
  pre_check
fi
main
