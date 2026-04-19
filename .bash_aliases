# shellcheck shell=bash
# General System Utilities
alias c='clear'
alias grephist='history | grep'
alias lt='ls --human-readable --size -1 -S --classify'
alias sha='shasum -a 256'
alias sshrestart='sudo /etc/init.d/ssh restart'

# Network and File Download
alias ping='ping -c 5'
alias wget='wget -c'
alias wgetc='wget --content-disposition'

# Journal and Logging
alias wtf='sudo journalctl --since today -u'
alias wtfy='sudo journalctl --since yesterday -u'

# Systemd Services Management
alias sysdisable='sudo systemctl disable'
alias sysenable='sudo systemctl enable'
alias sysreload='sudo systemctl daemon-reload'
alias sysstart='sudo systemctl start'
alias sysstatus='sudo systemctl status'
alias sysstop='sudo systemctl stop'

# Archive and Compression
alias untar='tar -zxvf'

# Network Testing
alias speed='speedtest-cli --server 2406 --simple'

# Docker Management
alias dcdown='docker compose down'
alias dcup='docker compose up'
alias dexec='docker exec -it'
alias dockerclean='docker rm $(docker ps -a -q)'
alias dockerdu='docker system df'
alias dockerls='docker ps -a'
# shellcheck disable=SC2142  # $3 is awk's field variable, not a shell positional param
alias docker-rmi-untagged='docker rmi $(docker images | grep "^<none>" | awk "{print \$3}")'
alias dockerstopall='docker stop $(docker ps -a -q)'
alias dlogs='docker logs'

# Development and Git
startgit() { cd "$(git rev-parse --show-toplevel)" && git checkout master && git pull; }

# File Management
alias rmrf='rm -rf' # Use with caution
alias mkdir='mkdir -p'
alias mv='mv -i'
alias cp='cp -i'
alias chmod002='sudo chmod -R a=,a+rX,u+w,g+w'

# Searching
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# System Monitoring
alias top='htop' # Requires htop installed
alias df='df -h'
alias du='du -ch'

# Disk Usage
alias ducks='du -cks * | sort -rn | head'

# Networking
alias ports='netstat -tulanp'
alias myip='curl http://ipecho.net/plain; echo'

# Quick Navigation
alias ..='cd ..'
alias ...='cd ../../'
alias ....='cd ../../../'
alias .....='cd ../../../../'

# Enhanced ls
alias ll='ls -lAFha --color=auto --group-directories-first'
alias la='ls -A --color=auto --group-directories-first'
alias l='ls -CF --color=auto --group-directories-first'

# Git Operations
alias gs='git status'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'

# Safety Features
alias off='shutdown -h now'
alias reboot='sudo /sbin/reboot'
