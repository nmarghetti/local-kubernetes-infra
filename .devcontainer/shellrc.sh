#! /bin/bash

export PS1='${debian_chroot:+($debian_chroot)}\[`[[ $? -eq 0 ]] && echo "\e[01;34m" || echo "\e[01;31m"`\]\t \[\033[01;32m\]\u\[\033[01;33m\]@\[\033[01;35m\]\h \[\e[01;35m\]${OSTYPE}\s@\v \[\e[01;36m\]git@`git --version | sed -re "s#^[^0-9]*([0-9\.]+).*#\1#" | cut -d. -f-3` \[\033[01;33m\]\w\[\033[00m\]\[\033[01;36m\]`__git_ps1`\[\033[00m\]\n\$ '
export PS4=$'+ \t\t''\e[33m\s@\v ${BASH_SOURCE:-}#\e[35m${LINENO} \e[34m${FUNCNAME[0]:+${FUNCNAME[0]}() }''\e[36m\t\e[0m\n'

# kubectl autocompletion
. <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k

# helm autocompletion
. <(helm completion bash)

# flux autocompletion
command -v flux >/dev/null && . <(flux completion bash)

# argocd autocompletion
command -v argocd >/dev/null && . <(argocd completion bash)

# minikube autocompletion
. <(minikube completion bash)

# terraform autocompletion
complete -C /usr/bin/terraform terraform

# kind autocompletion
. <(kind completion bash)
