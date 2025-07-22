#!/bin/bash
# Advanced Glibc Updater Script
# 支持多种 Linux 发行版和地区的 Glibc 更新脚本
# Author: System Administrator
# Version: 2.0

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志文件
LOG_FILE="/var/log/glibc_update_$(date +%Y%m%d_%H%M%S).log"

# 函数：打印带颜色的消息
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

# 函数：检测地理位置
detect_location() {
    print_msg "$BLUE" "检测地理位置..."
    
    # 尝试通过多个服务检测位置
    for url in "http://ip-api.com/json/" "https://ipinfo.io/country" "http://ip.cn"; do
        if curl -s --connect-timeout 5 "$url" | grep -qi "china\|cn\|中国"; then
            echo "CN"
            return
        fi
    done
    
    # 检测是否能访问 Google
    if curl -s --connect-timeout 5 "https://www.google.com" > /dev/null 2>&1; then
        echo "INTL"
    else
        echo "CN"
    fi
}

# 函数：获取系统信息
get_system_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS_NAME="centos"
        OS_VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release)
    elif [ -f /etc/debian_version ]; then
        OS_NAME="debian"
        OS_VERSION=$(cat /etc/debian_version)
    else
        print_msg "$RED" "无法识别的操作系统"
        exit 1
    fi
    
    ARCH=$(uname -m)
    LOCATION=$(detect_location)
    
    print_msg "$GREEN" "系统信息: $OS_NAME $OS_VERSION ($ARCH) - 位置: $LOCATION"
}

# 函数：备份当前 Glibc
backup_glibc() {
    print_msg "$BLUE" "备份当前 Glibc..."
    
    BACKUP_DIR="/root/glibc_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # 获取当前 glibc 版本
    CURRENT_VERSION=$(ldd --version | head -n1 | awk '{print $NF}')
    echo "$CURRENT_VERSION" > "$BACKUP_DIR/version.txt"
    
    # 备份关键文件
    for lib in /lib64/libc.so.* /lib64/ld-linux*.so.* /lib/x86_64-linux-gnu/libc.so.* /lib/x86_64-linux-gnu/ld-linux*.so.*; do
        if [ -f "$lib" ]; then
            cp -p "$lib" "$BACKUP_DIR/" 2>/dev/null || true
        fi
    done
    
    print_msg "$GREEN" "备份完成: $BACKUP_DIR"
}

# 函数：配置 CentOS 7 Vault 仓库
setup_centos7_vault() {
    print_msg "$YELLOW" "CentOS 7 已停止维护，切换到 Vault 仓库..."
    
    # 备份原有 repo 文件
    mkdir -p /etc/yum.repos.d/backup
    mv /etc/yum.repos.d/CentOS-*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true
    
    # 创建 Vault 仓库配置
    cat > /etc/yum.repos.d/CentOS-Vault.repo << 'EOF'
[base-vault]
name=CentOS-7 - Base - Vault
baseurl=https://vault.centos.org/7.9.2009/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

[updates-vault]
name=CentOS-7 - Updates - Vault
baseurl=https://vault.centos.org/7.9.2009/updates/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

[extras-vault]
name=CentOS-7 - Extras - Vault
baseurl=https://vault.centos.org/7.9.2009/extras/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1
EOF
    
    # 如果在中国，添加镜像源
    if [ "$LOCATION" = "CN" ]; then
        sed -i 's|https://vault.centos.org|https://mirrors.aliyun.com/centos-vault|g' /etc/yum.repos.d/CentOS-Vault.repo
    fi
    
    yum clean all
    yum makecache
}

# 函数：配置镜像源
setup_mirrors() {
    local os=$1
    local version=$2
    
    if [ "$LOCATION" != "CN" ]; then
        print_msg "$BLUE" "使用默认官方源..."
        return
    fi
    
    print_msg "$BLUE" "配置中国镜像源..."
    
    case "$os" in
        "centos"|"rhel"|"rocky"|"almalinux")
            if [ "$os" = "centos" ] && [ "${version%%.*}" = "7" ]; then
                setup_centos7_vault
            else
                # 配置阿里云镜像
                sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/*.repo
                sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.aliyun.com|g' /etc/yum.repos.d/*.repo
            fi
            ;;
        "ubuntu")
            cp /etc/apt/sources.list /etc/apt/sources.list.bak
            sed -i 's|http://archive.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list
            sed -i 's|http://security.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list
            apt-get update
            ;;
        "debian")
            cp /etc/apt/sources.list /etc/apt/sources.list.bak
            sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list
            sed -i 's|security.debian.org|mirrors.aliyun.com/debian-security|g' /etc/apt/sources.list
            apt-get update
            ;;
    esac
}

# 函数：更新 Glibc (YUM/DNF 系统)
update_glibc_yum() {
    print_msg "$BLUE" "使用 YUM/DNF 更新 Glibc..."
    
    # 安装必要工具
    if command -v dnf &> /dev/null; then
        PKG_MGR="dnf"
    else
        PKG_MGR="yum"
    fi
    
    $PKG_MGR install -y epel-release 2>/dev/null || true
    $PKG_MGR install -y gcc gcc-c++ make wget bison
    
    # 检查可用的 glibc 更新
    print_msg "$BLUE" "检查 Glibc 更新..."
    $PKG_MGR check-update glibc
    
    # 更新 glibc
    $PKG_MGR update -y glibc glibc-common glibc-devel glibc-headers
    
    # 验证更新
    NEW_VERSION=$(ldd --version | head -n1 | awk '{print $NF}')
    print_msg "$GREEN" "Glibc 已更新到版本: $NEW_VERSION"
}

# 函数：更新 Glibc (APT 系统)
update_glibc_apt() {
    print_msg "$BLUE" "使用 APT 更新 Glibc..."
    
    # 更新包列表
    apt-get update
    
    # 安装必要工具
    apt-get install -y build-essential wget bison
    
    # 检查可用的 glibc 更新
    print_msg "$BLUE" "检查 Glibc 更新..."
    apt-cache policy libc6
    
    # 更新 glibc
    apt-get install -y --only-upgrade libc6 libc6-dev
    
    # 验证更新
    NEW_VERSION=$(ldd --version | head -n1 | awk '{print $NF}')
    print_msg "$GREEN" "Glibc 已更新到版本: $NEW_VERSION"
}

# 函数：从源码编译安装最新 Glibc（高级选项）
compile_glibc_from_source() {
    print_msg "$YELLOW" "警告: 从源码编译 Glibc 风险较高，建议仅在必要时使用"
    read -p "是否继续？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    # 获取最新版本
    GLIBC_VERSION="2.39"  # 可以修改为需要的版本
    
    print_msg "$BLUE" "准备编译 Glibc $GLIBC_VERSION..."
    
    # 创建工作目录
    WORK_DIR="/tmp/glibc_build"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # 下载源码
    if [ "$LOCATION" = "CN" ]; then
        MIRROR="https://mirrors.aliyun.com/gnu/glibc"
    else
        MIRROR="https://ftp.gnu.org/gnu/glibc"
    fi
    
    wget "$MIRROR/glibc-$GLIBC_VERSION.tar.gz"
    tar -xzf "glibc-$GLIBC_VERSION.tar.gz"
    
    # 创建构建目录
    mkdir build
    cd build
    
    # 配置
    ../glibc-$GLIBC_VERSION/configure \
        --prefix=/usr \
        --disable-profile \
        --enable-add-ons \
        --with-headers=/usr/include \
        --with-binutils=/usr/bin
    
    # 编译和安装
    make -j$(nproc)
    make install
    
    # 清理
    cd /
    rm -rf "$WORK_DIR"
    
    # 验证
    NEW_VERSION=$(ldd --version | head -n1 | awk '{print $NF}')
    print_msg "$GREEN" "Glibc 已编译安装到版本: $NEW_VERSION"
}

# 函数：安全检查
safety_check() {
    print_msg "$BLUE" "执行安全检查..."
    
    # 检查是否为 root
    if [ "$EUID" -ne 0 ]; then
        print_msg "$RED" "错误: 请使用 root 权限运行此脚本"
        exit 1
    fi
    
    # 检查系统关键进程
    if ! ps aux | grep -v grep | grep -q "systemd\|init"; then
        print_msg "$RED" "错误: 未检测到系统初始化进程"
        exit 1
    fi
    
    # 检查磁盘空间
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1048576 ]; then
        print_msg "$RED" "错误: 磁盘空间不足 (需要至少 1GB)"
        exit 1
    fi
}

# 函数：恢复备份
restore_backup() {
    print_msg "$YELLOW" "可用的备份:"
    ls -la /root/glibc_backup_* 2>/dev/null || {
        print_msg "$RED" "没有找到备份"
        return 1
    }
    
    read -p "请输入要恢复的备份目录名: " backup_dir
    
    if [ -d "/root/$backup_dir" ]; then
        print_msg "$BLUE" "恢复备份: $backup_dir"
        cp -fp /root/$backup_dir/*.so.* /lib64/ 2>/dev/null || \
        cp -fp /root/$backup_dir/*.so.* /lib/x86_64-linux-gnu/ 2>/dev/null
        
        ldconfig
        print_msg "$GREEN" "备份已恢复"
    else
        print_msg "$RED" "备份目录不存在"
    fi
}

# 主函数
main() {
    print_msg "$GREEN" "=== Glibc 更新脚本 ==="
    print_msg "$BLUE" "日志文件: $LOG_FILE"
    
    # 安全检查
    safety_check
    
    # 获取系统信息
    get_system_info
    
    # 配置镜像源
    setup_mirrors "$OS_NAME" "$OS_VERSION"
    
    # 备份当前 Glibc
    backup_glibc
    
    # 显示菜单
    echo
    print_msg "$BLUE" "请选择操作:"
    echo "1) 使用包管理器更新 Glibc (推荐)"
    echo "2) 从源码编译最新版 Glibc (高级)"
    echo "3) 恢复备份"
    echo "4) 退出"
    
    read -p "请输入选项 (1-4): " choice
    
    case $choice in
        1)
            case "$OS_NAME" in
                "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
                    update_glibc_yum
                    ;;
                "ubuntu"|"debian")
                    update_glibc_apt
                    ;;
                *)
                    print_msg "$RED" "不支持的操作系统: $OS_NAME"
                    exit 1
                    ;;
            esac
            ;;
        2)
            compile_glibc_from_source
            ;;
        3)
            restore_backup
            ;;
        4)
            print_msg "$BLUE" "退出脚本"
            exit 0
            ;;
        *)
            print_msg "$RED" "无效的选项"
            exit 1
            ;;
    esac
    
    # 重新加载动态链接库
    ldconfig
    
    print_msg "$GREEN" "=== 操作完成 ==="
    print_msg "$YELLOW" "建议重启系统以确保所有更改生效"
}

# 错误处理
trap 'print_msg "$RED" "错误: 脚本执行失败，请检查日志文件: $LOG_FILE"' ERR

# 执行主函数
main "$@"