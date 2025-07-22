#!/bin/bash

# .NET 8 SDK 通用Linux自动安装脚本
# 支持CentOS/RHEL全版本和Ubuntu全版本
# 智能选择国内外镜像源，解决GLIBC依赖问题
# 版本: 2.0

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 全局变量
USE_CHINA_MIRROR=false
SYSTEM_ARCH=""

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root权限运行此脚本"
        log_info "使用方法: sudo $0"
        exit 1
    fi
}

# 检查网络连接并判断使用国内外源
check_network_and_region() {
    log_info "检查网络连接并判断最佳源..."
    
    # 测试基本网络连接
    if ! timeout 10 ping -c 1 8.8.8.8 >/dev/null 2>&1 && ! timeout 10 ping -c 1 114.114.114.114 >/dev/null 2>&1; then
        log_error "网络连接失败，请检查网络设置"
        exit 1
    fi
    
    # 通过ping延迟判断使用国内外源
    log_info "测试网络延迟以选择最佳镜像源..."
    
    # 测试Google DNS延迟(国外)
    GOOGLE_PING=$(timeout 5 ping -c 3 8.8.8.8 2>/dev/null | grep 'avg' | awk -F'/' '{print $5}' | awk -F'.' '{print $1}' || echo "999")
    
    # 测试阿里DNS延迟(国内)
    ALIYUN_PING=$(timeout 5 ping -c 3 223.5.5.5 2>/dev/null | grep 'avg' | awk -F'/' '{print $5}' | awk -F'.' '{print $1}' || echo "999")
    
    log_info "Google DNS延迟: ${GOOGLE_PING}ms"
    log_info "阿里云DNS延迟: ${ALIYUN_PING}ms"
    
    # 如果阿里云延迟明显更低，使用国内源
    if [ "$ALIYUN_PING" -lt "$GOOGLE_PING" ] && [ "$ALIYUN_PING" -lt 100 ]; then
        USE_CHINA_MIRROR=true
        log_success "检测到国内网络环境，将使用国内镜像源"
    else
        USE_CHINA_MIRROR=false
        log_success "检测到国外网络环境，将使用官方源"
    fi
}

# 检测系统类型、版本和架构
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        CODENAME=${VERSION_CODENAME:-}
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
        VER=$(cat /etc/redhat-release | sed 's/.*release //;s/ .*//' | cut -d. -f1)
    elif [ -f /etc/debian_version ]; then
        OS="ubuntu"
        VER=$(cat /etc/debian_version)
    else
        log_error "无法检测系统类型"
        exit 1
    fi

    # 检测系统架构
    SYSTEM_ARCH=$(uname -m)
    case $SYSTEM_ARCH in
        x86_64) SYSTEM_ARCH="x64" ;;
        aarch64|arm64) SYSTEM_ARCH="arm64" ;;
        armv7l) SYSTEM_ARCH="arm" ;;
        *) log_error "不支持的系统架构: $SYSTEM_ARCH"; exit 1 ;;
    esac

    log_info "检测到系统: $OS $VER ($SYSTEM_ARCH)"
}

# 备份原有源配置
backup_sources() {
    log_info "备份原有源配置..."
    
    case $OS in
        centos|rhel|rocky|almalinux)
            if [ -d /etc/yum.repos.d ]; then
                cp -r /etc/yum.repos.d /etc/yum.repos.d.backup.$(date +%Y%m%d_%H%M%S)
            fi
            ;;
        ubuntu|debian)
            cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)
            ;;
    esac
}

# 配置镜像源
configure_mirrors() {
    if [ "$USE_CHINA_MIRROR" = true ]; then
        log_info "配置国内镜像源..."
        configure_china_mirrors
    else
        log_info "使用官方源..."
    fi
}

# 配置国内镜像源
configure_china_mirrors() {
    case $OS in
        centos|rhel)
            if [ "$VER" = "7" ]; then
                configure_centos7_china_mirror
            elif [ "$VER" = "8" ]; then
                configure_centos8_china_mirror
            fi
            ;;
        ubuntu|debian)
            configure_ubuntu_china_mirror
            ;;
    esac
}

# CentOS 7 国内镜像配置
configure_centos7_china_mirror() {
    cat > /etc/yum.repos.d/CentOS-Base.repo << 'EOF'
[base]
name=CentOS-$releasever - Base - mirrors.aliyun.com
baseurl=http://mirrors.aliyun.com/centos/$releasever/os/$basearch/
        http://mirrors.tuna.tsinghua.edu.cn/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-$releasever - Updates - mirrors.aliyun.com
baseurl=http://mirrors.aliyun.com/centos/$releasever/updates/$basearch/
        http://mirrors.tuna.tsinghua.edu.cn/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-$releasever - Extras - mirrors.aliyun.com
baseurl=http://mirrors.aliyun.com/centos/$releasever/extras/$basearch/
        http://mirrors.tuna.tsinghua.edu.cn/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7
EOF
}

# Ubuntu国内镜像配置
configure_ubuntu_china_mirror() {
    if [ -n "$CODENAME" ]; then
        cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/ubuntu/ $CODENAME main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $CODENAME-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $CODENAME-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $CODENAME-backports main restricted universe multiverse
EOF
    fi
}

# 安装系统依赖和开发工具
install_system_dependencies() {
    log_info "安装系统依赖和开发工具..."
    
    case $OS in
        centos|rhel|rocky|almalinux)
            # 启用EPEL和PowerTools/CodeReady仓库
            if [ "$VER" = "7" ]; then
                yum install -y epel-release
                yum groupinstall -y "Development Tools"
                yum install -y centos-release-scl
                yum install -y devtoolset-7-gcc devtoolset-7-gcc-c++
            elif [ "$VER" = "8" ]; then
                dnf install -y epel-release
                dnf config-manager --set-enabled powertools || dnf config-manager --set-enabled PowerTools
                dnf groupinstall -y "Development Tools"
                dnf install -y gcc-toolset-9-gcc gcc-toolset-9-gcc-c++
            elif [ "$VER" = "9" ]; then
                dnf install -y epel-release
                dnf config-manager --set-enabled crb
                dnf groupinstall -y "Development Tools"
            fi
            
            # 安装基础依赖
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y curl wget gpg ca-certificates libicu krb5-libs libssl1.1 openssl-libs zlib
            else
                yum install -y curl wget gnupg2 ca-certificates libicu krb5-libs openssl-libs zlib
            fi
            ;;
        ubuntu|debian)
            apt-get update
            apt-get install -y curl wget gnupg2 software-properties-common apt-transport-https \
                ca-certificates build-essential libicu-dev libssl-dev zlib1g-dev \
                libc6-dev libgcc1 libgssapi-krb5-2 libstdc++6
            ;;
    esac
}

# 升级系统库以解决GLIBC问题
upgrade_system_libraries() {
    log_info "检查并升级系统库以解决GLIBC依赖问题..."
    
    case $OS in
        centos|rhel|rocky|almalinux)
            if [ "$VER" = "7" ]; then
                log_info "CentOS 7 检测到，升级GLIBC和libstdc++..."
                
                # 启用SCL仓库中的newer GCC
                yum install -y centos-release-scl
                yum install -y devtoolset-7-libstdc++-devel
                
                # 创建软链接指向更新的libstdc++
                DEVTOOLSET_LIBDIR="/opt/rh/devtoolset-7/root/usr/lib64"
                if [ -f "$DEVTOOLSET_LIBDIR/libstdc++.so.6" ]; then
                    cp /lib64/libstdc++.so.6 /lib64/libstdc++.so.6.backup.$(date +%Y%m%d_%H%M%S)
                    cp "$DEVTOOLSET_LIBDIR/libstdc++.so.6"* /lib64/
                    log_success "已升级libstdc++库"
                fi
            elif [ "$VER" = "8" ]; then
                dnf update -y glibc libstdc++ gcc-toolset-9-libstdc++-devel
                source /opt/rh/gcc-toolset-9/enable
            else
                if command -v dnf >/dev/null 2>&1; then
                    dnf update -y glibc libstdc++
                else
                    yum update -y glibc libstdc++
                fi
            fi
            ;;
        ubuntu|debian)
            apt-get update
            apt-get install -y libc6 libstdc++6 gcc-multilib
            ;;
    esac
}

# 添加Microsoft软件源
add_microsoft_repo() {
    log_info "添加Microsoft软件源..."
    
    # 选择Microsoft源地址
    if [ "$USE_CHINA_MIRROR" = true ]; then
        MS_BASE_URL="https://packages.microsoft.com"
    else
        MS_BASE_URL="https://packages.microsoft.com"
    fi
    
    case $OS in
        centos|rhel|rocky|almalinux)
            # 添加Microsoft GPG密钥
            rpm --import $MS_BASE_URL/keys/microsoft.asc 2>/dev/null || {
                log_warning "直接导入GPG密钥失败，尝试下载后导入..."
                curl -sSL $MS_BASE_URL/keys/microsoft.asc -o /tmp/microsoft.asc
                rpm --import /tmp/microsoft.asc
            }
            
            # 创建Microsoft软件源
            cat > /etc/yum.repos.d/microsoft-prod.repo << EOF
[packages-microsoft-com-prod]
name=packages-microsoft-com-prod
baseurl=$MS_BASE_URL/rhel/$VER/prod/
enabled=1
gpgcheck=1
gpgkey=$MS_BASE_URL/keys/microsoft.asc
EOF
            ;;
        ubuntu|debian)
            # 获取Microsoft GPG密钥
            curl -sSL $MS_BASE_URL/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg
            install -o root -g root -m 644 /tmp/microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
            
            # 添加Microsoft软件源
            if [ -n "$CODENAME" ]; then
                echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/microsoft.gpg] $MS_BASE_URL/ubuntu/$VER/prod $CODENAME main" > /etc/apt/sources.list.d/microsoft-prod.list
            fi
            
            apt-get update
            ;;
    esac
}

# 更新软件包列表
update_packages() {
    log_info "更新软件包列表..."
    
    case $OS in
        centos|rhel|rocky|almalinux)
            if command -v dnf >/dev/null 2>&1; then
                dnf clean all && dnf makecache
            else
                yum clean all && yum makecache
            fi
            ;;
        ubuntu|debian)
            apt-get update
            ;;
    esac
}

# 安装.NET 8 SDK
install_dotnet_sdk() {
    log_info "安装.NET 8 SDK..."
    
    # 尝试通过包管理器安装
    local package_install_success=false
    
    case $OS in
        centos|rhel|rocky|almalinux)
            if command -v dnf >/dev/null 2>&1; then
                if dnf install -y dotnet-sdk-8.0; then
                    package_install_success=true
                fi
            else
                if yum install -y dotnet-sdk-8.0; then
                    package_install_success=true
                fi
            fi
            ;;
        ubuntu|debian)
            if apt-get install -y dotnet-sdk-8.0; then
                package_install_success=true
            fi
            ;;
    esac
    
    # 如果包管理器安装失败，使用官方安装脚本
    if [ "$package_install_success" = false ]; then
        log_warning "包管理器安装失败，使用官方安装脚本..."
        manual_install_dotnet
    fi
}

# 手动安装.NET SDK
manual_install_dotnet() {
    log_info "使用官方安装脚本安装.NET 8 SDK..."
    
    # 下载安装脚本
    curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    
    # 安装.NET 8 SDK
    /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet
    
    # 创建符号链接
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
    
    # 设置环境变量
    cat > /etc/profile.d/dotnet.sh << 'EOF'
export DOTNET_ROOT=/usr/share/dotnet
export PATH=$PATH:/usr/share/dotnet
EOF
    
    chmod +x /etc/profile.d/dotnet.sh
    source /etc/profile.d/dotnet.sh
}

# 解决.NET运行时依赖问题
fix_dotnet_dependencies() {
    log_info "检查并修复.NET运行时依赖问题..."
    
    # 设置环境变量
    export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
    echo 'export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1' >> /etc/profile.d/dotnet.sh
    
    # 创建.NET配置文件
    mkdir -p /usr/share/dotnet/shared/Microsoft.NETCore.App
    
    # 测试.NET是否能正常运行
    if ! /usr/local/bin/dotnet --version >/dev/null 2>&1; then
        log_warning ".NET存在依赖问题，尝试修复..."
        
        case $OS in
            centos|rhel|rocky|almalinux)
                # 安装额外的运行时依赖
                if command -v dnf >/dev/null 2>&1; then
                    dnf install -y icu libssl1.1 krb5-libs zlib
                else
                    yum install -y libicu openssl-libs krb5-libs zlib
                fi
                
                # 对于CentOS 7，可能需要手动处理libssl
                if [ "$VER" = "7" ]; then
                    if [ ! -f /usr/lib64/libssl.so.1.1 ]; then
                        ln -sf /usr/lib64/libssl.so.10 /usr/lib64/libssl.so.1.1 2>/dev/null || true
                        ln -sf /usr/lib64/libcrypto.so.10 /usr/lib64/libcrypto.so.1.1 2>/dev/null || true
                    fi
                fi
                ;;
            ubuntu|debian)
                apt-get install -y libicu-dev libssl-dev
                ;;
        esac
    fi
}

# 验证安装
verify_installation() {
    log_info "验证.NET 8 SDK安装..."
    
    # 重新加载环境变量
    source /etc/profile.d/dotnet.sh 2>/dev/null || true
    
    # 检查dotnet命令是否可用
    if command -v dotnet >/dev/null 2>&1; then
        local dotnet_version
        dotnet_version=$(dotnet --version 2>/dev/null || echo "获取版本失败")
        
        if [[ $dotnet_version == *"8."* ]]; then
            log_success ".NET 8 SDK安装成功!"
            log_success "版本: $dotnet_version"
            
            # 测试SDK功能
            log_info "测试SDK功能..."
            if dotnet --list-sdks >/dev/null 2>&1; then
                log_success "SDK功能测试通过"
                echo "已安装的SDK:"
                dotnet --list-sdks
            fi
            
            # 创建测试项目验证
            local test_dir="/tmp/dotnet-test-$(date +%s)"
            mkdir -p "$test_dir"
            cd "$test_dir"
            
            if dotnet new console -n TestApp >/dev/null 2>&1; then
                cd TestApp
                if dotnet build >/dev/null 2>&1; then
                    log_success "项目创建和编译测试通过"
                else
                    log_warning "项目编译失败，但SDK已安装"
                fi
            fi
            
            # 清理测试项目
            rm -rf "$test_dir"
            
            return 0
        else
            log_error "安装的.NET版本不正确: $dotnet_version"
            return 1
        fi
    else
        log_error ".NET SDK未正确安装或配置"
        return 1
    fi
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    rm -f /tmp/microsoft.gpg
    rm -f /tmp/microsoft.asc
    rm -f /tmp/dotnet-install.sh
}

# 显示使用说明
show_usage_info() {
    echo "========================================"
    log_success "安装完成！"
    echo "========================================"
    log_info "使用方法："
    log_info "  dotnet --version          # 查看版本"
    log_info "  dotnet --list-sdks        # 查看已安装的SDK"
    log_info "  dotnet new console -n MyApp  # 创建新控制台应用"
    log_info "  dotnet run                # 运行应用"
    echo ""
    log_info "如果遇到权限问题，请运行："
    log_info "  source /etc/profile.d/dotnet.sh"
    echo ""
    log_info "环境变量已设置："
    log_info "  DOTNET_ROOT=/usr/share/dotnet"
    log_info "  PATH包含/usr/share/dotnet"
    echo "========================================"
}

# 主函数
main() {
    echo "========================================"
    echo "    .NET 8 SDK 智能安装脚本 v2.0"
    echo "========================================"
    
    # 基础检查
    check_root
    check_network_and_region
    detect_system
    
    # 系统准备
    backup_sources
    configure_mirrors
    update_packages
    
    # 安装依赖和解决兼容性问题
    install_system_dependencies
    upgrade_system_libraries
    
    # 安装.NET SDK
    add_microsoft_repo
    install_dotnet_sdk
    fix_dotnet_dependencies
    
    # 验证和清理
    if verify_installation; then
        cleanup
        show_usage_info
    else
        log_error "安装验证失败，请检查错误信息"
        exit 1
    fi
}

# 错误处理
trap 'log_error "安装过程中发生错误"; cleanup; exit 1' ERR

# 运行主函数
main "$@"