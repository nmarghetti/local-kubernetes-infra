#! /bin/bash

export PS1='${debian_chroot:+($debian_chroot)}\[`[[ $? -eq 0 ]] && echo "\e[01;34m" || echo "\e[01;31m"`\]\t \[\033[01;32m\]\u\[\033[01;33m\]@\[\033[01;35m\]\h \[\e[01;35m\]${OSTYPE}\s@\v \[\e[01;36m\]git@`git --version | sed -re "s#^[^0-9]*([0-9\.]+).*#\1#" | cut -d. -f-3` \[\033[01;33m\]\w\[\033[00m\]\[\033[01;36m\]`__git_ps1`\[\033[00m\]\n\$ '
export PS4=$'+ \t\t''\e[33m\s@\v ${BASH_SOURCE:-}#\e[35m${LINENO} \e[34m${FUNCNAME[0]:+${FUNCNAME[0]}() }''\e[36m\t\e[0m\n'
