#!/bin/bash

#############################################
# Debian 系统初始化脚本 (支持 11/12/13)
# 用途: 系统初始配置、软件安装、性能优化
# 作者: Claude
# 日期: 2026-03-21
#############################################

set -e -o pipefail

export DEBIAN_FRONTEND=noninteractive

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 自动检测 Debian 版本（读 /etc/os-release，不依赖 lsb-release）
detect_version() {
    if [ ! -f /etc/os-release ]; then
        log_error "找不到 /etc/os-release，无法识别系统"
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    CODENAME=${VERSION_CODENAME:-}
    case "$CODENAME" in
        bullseye) DEBIAN_VER=11 ;;
        bookworm) DEBIAN_VER=12 ;;
        trixie)   DEBIAN_VER=13 ;;
        *)
            log_error "不支持的 Debian 版本: $CODENAME"
            exit 1
            ;;
    esac

    log_info "检测到 Debian $DEBIAN_VER ($CODENAME)"
}

# 备份重要配置文件
backup_configs() {
    log_info "备份重要配置文件..."
    local backup_dir
    backup_dir="/root/config_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    [ -f /etc/ssh/sshd_config ]      && cp /etc/ssh/sshd_config "$backup_dir/"
    [ -d /etc/ssh/sshd_config.d ]    && cp -r /etc/ssh/sshd_config.d "$backup_dir/"
    [ -f /etc/sysctl.conf ]          && cp /etc/sysctl.conf "$backup_dir/"
    [ -f /etc/security/limits.conf ] && cp /etc/security/limits.conf "$backup_dir/"
    [ -f /etc/systemd/system.conf ]  && cp /etc/systemd/system.conf "$backup_dir/"
    [ -f /etc/apt/sources.list ]     && cp /etc/apt/sources.list "$backup_dir/"
    [ -d /etc/apt/sources.list.d ]   && cp -r /etc/apt/sources.list.d "$backup_dir/"

    log_info "配置文件已备份到: $backup_dir"
}

# 更新软件源
update_sources() {
    log_info "准备更新软件源..."

    echo "------------------------------------------------"
    echo "请选择要使用的 Debian 软件源镜像:"
    echo "1) 默认"
    echo "2) 南方科大"
    echo "3) 阿里云(内网)"
    echo "4) 腾讯云(内网)"
    echo "5) 火山云(内网)"
    echo "6) xTom(香港)"
    echo "7) xTom(美国)"
    echo "8) xTom(荷兰)"
    echo "9) xTom(德国)"
    echo "10) xTom(爱沙尼亚)"
    echo "11) xTom(日本)"
    echo "12) xTom(澳洲)"
    echo "13) xTom(新加坡)"
    echo "------------------------------------------------"
    read -r -p "请输入选项 [1-13] (默认为 1): " choice || true

    # 支持 HTTPS 的镜像用 HTTPS；云内网源保持 HTTP（内网源多数不支持 HTTPS）
    local main_url="https://deb.debian.org/debian"
    local security_url="https://security.debian.org/debian-security"
    local source_name="官方源"

    case "$choice" in
        2)  main_url="https://mirrors.sustech.edu.cn/debian";    security_url="https://mirrors.sustech.edu.cn/debian-security";  source_name="南方科大" ;;
        3)  main_url="http://mirrors.cloud.aliyuncs.com/debian"; security_url="http://mirrors.cloud.aliyuncs.com/debian-security"; source_name="阿里云(内网)" ;;
        4)  main_url="http://mirrors.tencentyun.com/debian";     security_url="http://mirrors.tencentyun.com/debian-security";   source_name="腾讯云(内网)" ;;
        5)  main_url="http://mirrors.ivolces.com/debian";        security_url="http://mirrors.ivolces.com/debian-security";      source_name="火山云(内网)" ;;
        6)  main_url="https://mirrors.xtom.hk/debian";           security_url="https://mirrors.xtom.hk/debian-security";         source_name="xTom(香港)" ;;
        7)  main_url="https://mirrors.xtom.us/debian";           security_url="https://mirrors.xtom.us/debian-security";         source_name="xTom(美国)" ;;
        8)  main_url="https://mirrors.xtom.nl/debian";           security_url="https://mirrors.xtom.nl/debian-security";         source_name="xTom(荷兰)" ;;
        9)  main_url="https://mirrors.xtom.de/debian";           security_url="https://mirrors.xtom.de/debian-security";         source_name="xTom(德国)" ;;
        10) main_url="https://mirrors.xtom.ee/debian";           security_url="https://mirrors.xtom.ee/debian-security";         source_name="xTom(爱沙尼亚)" ;;
        11) main_url="https://mirrors.xtom.jp/debian";           security_url="https://mirrors.xtom.jp/debian-security";         source_name="xTom(日本)" ;;
        12) main_url="https://mirrors.xtom.au/debian";           security_url="https://mirrors.xtom.au/debian-security";         source_name="xTom(澳洲)" ;;
        13) main_url="https://mirrors.xtom.sg/debian";           security_url="https://mirrors.xtom.sg/debian-security";         source_name="xTom(新加坡)" ;;
    esac

    log_info "已选择: $source_name，正在配置..."

    if [ ! -f /etc/apt/sources.list.bak ] && [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
        log_info "已备份原始源到 /etc/apt/sources.list.bak"
    fi

    # Debian 12/13 默认把源写在 sources.list.d/debian.sources（DEB822 格式），
    # 我们要覆盖 sources.list，就得把它禁用，否则会同时生效导致双源
    if [ -f /etc/apt/sources.list.d/debian.sources ] && \
       [ ! -f /etc/apt/sources.list.d/debian.sources.disabled ]; then
        mv /etc/apt/sources.list.d/debian.sources \
           /etc/apt/sources.list.d/debian.sources.disabled
        log_info "已禁用默认的 debian.sources（防止双源）"
    fi

    if [ "$CODENAME" = "bullseye" ]; then
        # Debian 11: 无 non-free-firmware 组件，无 backports
        cat > /etc/apt/sources.list <<EOF
deb ${main_url}/ ${CODENAME} main contrib non-free
deb ${main_url}/ ${CODENAME}-updates main contrib non-free
deb ${security_url} ${CODENAME}-security main contrib non-free
EOF
    else
        # Debian 12+: 含 non-free-firmware 和 backports
        cat > /etc/apt/sources.list <<EOF
deb ${main_url}/ ${CODENAME} main contrib non-free non-free-firmware
deb ${main_url}/ ${CODENAME}-updates main contrib non-free non-free-firmware
deb ${main_url}/ ${CODENAME}-backports main contrib non-free non-free-firmware
deb ${security_url} ${CODENAME}-security main contrib non-free non-free-firmware
EOF
    fi

    log_info "软件源已更新为: $source_name"
}

# 系统更新（用 apt-get；apt 官方不推荐用于脚本）
system_update() {
    log_info "更新系统软件包..."
    apt-get update
    apt-get -y dist-upgrade
    apt-get -y autoremove
    apt-get autoclean
}

# 安装基础软件
install_basic_packages() {
    log_info "安装基础软件包..."

    local packages=(
        sudo vim curl wget git htop net-tools bind9-dnsutils lsof
        zip unzip xz-utils tar rsync screen ca-certificates jq tree
        cron bash-completion
        traceroute mtr-tiny tcpdump netcat-openbsd
        iotop sysstat strace procps
        parted dosfstools
        gnupg bc file pv less
    )

    # apt-transport-https：Debian 11 需要；12 是空过渡包；13 已删除
    if [ "$DEBIAN_VER" -lt 12 ]; then
        packages+=(apt-transport-https)
    fi

    # btop：Debian 12+ 主源可用；Debian 11 主源无（需 backports），此处跳过
    if [ "$DEBIAN_VER" -ge 12 ]; then
        packages+=(btop)
    fi

    apt-get install -y "${packages[@]}"

    log_info "基础软件包安装完成"
}

# SSH安全加固（使用 sshd_config.d/ drop-in，改完 sshd -t 验证再重启）
secure_ssh() {
    log_info "配置SSH安全..."

    local drop_in=/etc/ssh/sshd_config.d/99-hardening.conf
    local key_login="no"

    read -p "是否配置密钥登陆? (⚠️ 请确保已上传公钥，否则将无法登录) (y/N): " -r -n 1 || true
    echo
    [[ "$REPLY" =~ ^[Yy]$ ]] && key_login="yes"

    # 确保主配置文件加载了 sshd_config.d/ 下的 drop-in
    # Debian 12/13 默认已有 Include；Debian 11 需要手动加
    if ! grep -qE '^Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
        log_info "已在 sshd_config 首行添加 Include /etc/ssh/sshd_config.d/*.conf"
    fi

    mkdir -p /etc/ssh/sshd_config.d

    if [ "$key_login" = "yes" ]; then
        cat > "$drop_in" <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    else
        cat > "$drop_in" <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    fi
    chmod 600 "$drop_in"

    # 关键：验证配置合法性，避免重启后 sshd 起不来把自己踢下线
    if ! sshd -t; then
        log_error "sshd 配置校验失败，回滚 $drop_in 并中止"
        rm -f "$drop_in"
        return 1
    fi

    systemctl restart ssh
    log_info "SSH 安全配置完成（写入 $drop_in）"
}

# 系统内核参数优化
optimize_sysctl() {
    log_info "优化系统内核参数..."

    cat > /etc/sysctl.d/99-custom.conf <<EOF
# ===== 系统初始化脚本添加 =====
# 基础网络优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 网络性能优化
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_tw_buckets = 5000

# 文件系统优化
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

# 虚拟内存优化
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# 安全相关（IPv4）
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# 安全相关（IPv6）
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
EOF

    sysctl -p /etc/sysctl.d/99-custom.conf
    log_info "内核参数优化完成"
}

# 系统资源限制优化
optimize_limits() {
    log_info "优化系统资源限制..."

    # 1) PAM 层：/etc/security/limits.conf，作用于通过 PAM 登录的会话
    # 幂等性检查，避免重复追加
    if ! grep -q "系统初始化脚本添加" /etc/security/limits.conf; then
        cat >> /etc/security/limits.conf <<EOF

# ===== 系统初始化脚本添加 =====
* soft nofile 1024000
* hard nofile 1024000
* soft nproc 65535
* hard nproc 65535
root soft nofile 1024000
root hard nofile 1024000
EOF
    fi

    # 2) systemd 层：drop-in 而不是改主配置，作用于 systemd 启动的服务
    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/99-limits.conf <<EOF
[Manager]
DefaultLimitNOFILE=1024000
DefaultLimitNPROC=65535
EOF

    systemctl daemon-reload

    log_info "资源限制优化完成（已运行的服务需重启才能应用新限制）"
}

# 配置时区和时间同步
configure_time() {
    log_info "配置时区和时间同步..."

    timedatectl set-timezone Asia/Shanghai
    apt-get install -y systemd-timesyncd
    systemctl enable systemd-timesyncd
    systemctl start systemd-timesyncd

    log_info "时区设置为 Asia/Shanghai，时间同步已启用"
}

# 配置bash（放到 /etc/profile.d/，对所有交互式 bash 生效；不再覆盖 root 的 .bashrc）
configure_bash() {
    log_info "配置bash..."

    cat > /etc/profile.d/custom_bash.sh <<'EOF'
# ===== 系统初始化脚本添加 =====
if [ -n "$BASH_VERSION" ] && [ -n "$PS1" ]; then
    eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias ll='ls --color=auto -l'
    alias l='ls --color=auto -lA'

    alias rm='rm -i'
    alias cp='cp -i'
    alias mv='mv -i'

    export PS1='\n\[\e[1;33m\]\u@\H\[\e[1;35m\]<\D{%F %T}> \[\e[1;32m\]\w\[\e[0m\]\n\$ '
fi
EOF
    chmod 644 /etc/profile.d/custom_bash.sh

    # 动态查找 vim defaults.vim，避免硬编码版本号；可能匹配多个，逐一处理
    local vim_defaults
    while IFS= read -r vim_defaults; do
        [ -n "$vim_defaults" ] && sed -i 's|set mouse=.*|set mouse=""|g' "$vim_defaults"
    done < <(find /usr/share/vim/vim*/defaults.vim 2>/dev/null || true)

    : > /etc/motd
    rm -rf /etc/update-motd.d/*

    log_info "配置bash完成"
}

# 设置历史命令格式（放到 /etc/profile.d/，避免污染 /etc/profile）
configure_history() {
    log_info "配置历史命令格式..."

    cat > /etc/profile.d/history.sh <<'EOF'
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTTIMEFORMAT="%F %T "
export HISTCONTROL=ignoredups
EOF
    chmod 644 /etc/profile.d/history.sh

    log_info "历史命令格式配置完成"
}

# 系统信息显示
show_system_info() {
    log_info "========== 系统信息 =========="
    echo "主机名: $(hostnamectl --static 2>/dev/null || hostname)"
    # shellcheck disable=SC1091
    echo "操作系统: $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "内核版本: $(uname -r)"
    echo "CPU信息: $(lscpu | awk -F: '/Model name/ {sub(/^ +/,"",$2); print $2; exit}')"
    echo "内存信息: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "磁盘信息: $(df -h / | awk 'NR==2 {print $2}')"
    echo "IP地址: $(ip addr show | awk '/inet / && !/127\.0\.0\.1/ {print $2; exit}' | cut -d/ -f1)"
}

# 主函数
main() {
    check_root
    detect_version
    log_info "开始执行 Debian $DEBIAN_VER 初始化脚本..."

    backup_configs
    update_sources
    system_update
    install_basic_packages
    secure_ssh
    optimize_sysctl
    optimize_limits
    configure_time
    configure_bash
    configure_history

    log_info "========================================="
    log_info "初始化完成！"
    log_info "========================================="
    show_system_info
    log_info "========================================="
    log_warn "建议重启系统使所有配置生效: reboot"
}

main
