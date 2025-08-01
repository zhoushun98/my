#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

_NAME=$1
_HOSTNAME=$_NAME-$(hostname -I | awk -F " " '{print $1}')

hostnamectl set-hostname "$_HOSTNAME"

cat << EOF > /etc/hosts
127.0.0.1 localhost
$(hostname -I | awk -F " " '{print $1}') $(hostname)
EOF

> /etc/motd
rm -rf /etc/update-motd.d/*

cat <<'EOF' > /etc/apt/sources.list
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
EOF

chattr +i /etc/apt/sources.list

apt update && apt install -y sudo wget curl xz-utils \
    socat tzdata locales lsof ca-certificates \
    unzip zip tar vim jq bash-completion tree \
    cron net-tools htop iftop git rsync dnsutils binutils

sed -i 's|set mouse=.*|set mouse=""|g' /usr/share/vim/vim90/defaults.vim
echo -e '\nset paste' >> /usr/share/vim/vim90/defaults.vim

sed -i '/^#*DefaultLimitNOFILE/s/^#*DefaultLimitNOFILE=.*/DefaultLimitNOFILE=655360/' /etc/systemd/system.conf
sed -i '/^#*DefaultLimitNPROC/s/^#*DefaultLimitNPROC=.*/DefaultLimitNPROC=655360/' /etc/systemd/system.conf
systemctl daemon-reexec

cat << 'EOF' >> /etc/security/limits.conf
root soft nofile 655350
root hard nofile 655350
* soft nofile 655350
* hard nofile 655350
EOF

ulimit -SHn 655350

cat << 'EOF' > ~/.bashrc
# ~/.bashrc: executed by bash(1) for non-login shells.

# You may uncomment the following lines if you want `ls' to be colorized:
export LS_OPTIONS='--color=auto'
eval "$(dircolors)"
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'

# Some more alias to avoid making mistakes:
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

export PS1='\n\[\e[1;33m\]\u@\H\[\e[1;35m\]<$(date +"%Y-%m-%d %H:%M:%S")> \[\e[1;32m\]\w\[\e[0m\]\n\$ '
EOF

sed -i \
  -e 's|^#*PasswordAuthentication.*|PasswordAuthentication no|' \
  -e 's|^#*PermitRootLogin.*|PermitRootLogin prohibit-password|' \
  /etc/ssh/sshd_config; \
  systemctl restart ssh || systemctl restart sshd

timedatectl set-timezone Asia/Shanghai

cat << 'EOF' > /etc/sysctl.conf
# 基础网络优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 全局缓冲区
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# TCP缓冲区
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 启用窗口缩放
net.ipv4.tcp_window_scaling = 1
EOF
sysctl -p

apt full-upgrade -y && reboot
