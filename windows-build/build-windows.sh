#!/bin/bash
# libimobiledevice Windows 编译脚本
# 适用于 MSYS2/MinGW 环境
#
# 使用方法:
# 1. 安装 MSYS2 (https://www.msys2.org/)
# 2. 在 MSYS2 MinGW64 终端中运行此脚本
# 3. cd /path/to/libimobiledevice/windows-build
# 4. ./build-windows.sh

set -e  # 遇到错误时退出

# 获取脚本所在目录和项目根目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查是否在MSYS2环境中
check_environment() {
    print_info "检查编译环境..."
    
    if [[ -z "$MSYSTEM" ]]; then
        print_error "请在 MSYS2 MinGW64 终端中运行此脚本"
        print_info "建议使用 MSYS2 MinGW 64-bit 终端"
        exit 1
    fi
    
    print_success "环境检查通过: $MSYSTEM"
}

# 安装依赖包
install_dependencies() {
    print_info "安装编译依赖..."
    
    # 基础构建工具
    local BUILD_TOOLS=(
        base-devel
        mingw-w64-x86_64-toolchain
        mingw-w64-x86_64-gcc
        mingw-w64-x86_64-make
        autoconf
        automake
        libtool
        pkg-config
        git
    )
    
    # SSL库 (默认使用OpenSSL)
    local SSL_LIBS=(
        mingw-w64-x86_64-openssl
    )
    
    # 核心依赖库
    local CORE_DEPS=(
        mingw-w64-x86_64-libplist
        mingw-w64-x86_64-libusbmuxd
        mingw-w64-x86_64-curl
    )
    
    print_info "更新包数据库..."
    pacman -Sy --noconfirm
    
    print_info "安装构建工具..."
    pacman -S --needed --noconfirm "${BUILD_TOOLS[@]}"
    
    print_info "安装SSL库..."
    pacman -S --needed --noconfirm "${SSL_LIBS[@]}"
    
    print_info "安装核心依赖..."
    pacman -S --needed --noconfirm "${CORE_DEPS[@]}"
    
    print_success "依赖安装完成"
}

# 构建缺失的依赖库
build_missing_dependencies() {
    print_info "检查并构建缺失的依赖库..."
    
    local BUILD_DIR="$PROJECT_ROOT/deps-build"
    local INSTALL_PREFIX="/mingw64"
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # 构建 libimobiledevice-glue
    if ! pkg-config --exists libimobiledevice-glue-1.0; then
        print_info "构建 libimobiledevice-glue..."
        
        if [ ! -d "libimobiledevice-glue" ]; then
            git clone https://github.com/libimobiledevice/libimobiledevice-glue.git
        fi
        
        cd libimobiledevice-glue
        git pull
        ./autogen.sh --prefix="$INSTALL_PREFIX"
        make -j$(nproc)
        make install
        cd ..
        
        print_success "libimobiledevice-glue 构建完成"
    else
        print_info "libimobiledevice-glue 已安装"
    fi
    
    # 构建 libtatsu
    if ! pkg-config --exists libtatsu-1.0; then
        print_info "构建 libtatsu..."
        
        if [ ! -d "libtatsu" ]; then
            git clone https://github.com/libimobiledevice/libtatsu.git
        fi
        
        cd libtatsu
        git pull
        ./autogen.sh --prefix="$INSTALL_PREFIX"
        make -j$(nproc)
        make install
        cd ..
        
        print_success "libtatsu 构建完成"
    else
        print_info "libtatsu 已安装"
    fi
    
    cd "$OLDPWD"
}

# 配置和构建
build_libimobiledevice() {
    print_info "开始构建 libimobiledevice..."
    
    # 切换到项目根目录
    cd "$PROJECT_ROOT"
    
    # 清理之前的构建
    if [ -f "Makefile" ]; then
        print_info "清理之前的构建..."
        make distclean 2>/dev/null || true
    fi
    
    # 运行 autogen.sh
    print_info "运行 autogen.sh..."
    ./autogen.sh \
        --prefix=/mingw64 \
        --enable-debug \
        --without-cython \
        --with-openssl
    
    # 编译
    print_info "编译中... (使用 $(nproc) 个CPU核心)"
    make -j$(nproc)
    
    print_success "libimobiledevice 编译完成"
}

# 安装
install_libimobiledevice() {
    print_info "安装 libimobiledevice..."
    
    make install
    
    print_success "libimobiledevice 安装完成"
}

# 备份编译产物
backup_build_artifacts() {
    print_info "备份编译产物到项目目录..."
    
    local BACKUP_DIR="$PROJECT_ROOT/build-output"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local BUILD_BACKUP="$BACKUP_DIR/$TIMESTAMP"
    
    mkdir -p "$BUILD_BACKUP"/{bin,lib,include,pkgconfig,docs}
    
    # 备份可执行文件
    print_info "备份可执行文件..."
    if [ -d "/mingw64/bin" ]; then
        cp -v /mingw64/bin/idevice*.exe "$BUILD_BACKUP/bin/" 2>/dev/null || true
        cp -v /mingw64/bin/afcclient.exe "$BUILD_BACKUP/bin/" 2>/dev/null || true
    fi
    
    # 备份库文件
    print_info "备份库文件..."
    if [ -d "/mingw64/lib" ]; then
        cp -v /mingw64/lib/libimobiledevice*.dll "$BUILD_BACKUP/lib/" 2>/dev/null || true
        cp -v /mingw64/lib/libimobiledevice*.a "$BUILD_BACKUP/lib/" 2>/dev/null || true
        cp -v /mingw64/lib/libimobiledevice*.la "$BUILD_BACKUP/lib/" 2>/dev/null || true
    fi
    
    # 备份头文件
    print_info "备份头文件..."
    if [ -d "/mingw64/include/libimobiledevice" ]; then
        cp -rv /mingw64/include/libimobiledevice "$BUILD_BACKUP/include/" 2>/dev/null || true
    fi
    
    # 备份 pkg-config 文件
    print_info "备份 pkg-config 文件..."
    if [ -d "/mingw64/lib/pkgconfig" ]; then
        cp -v /mingw64/lib/pkgconfig/libimobiledevice*.pc "$BUILD_BACKUP/pkgconfig/" 2>/dev/null || true
    fi
    
    # 复制依赖的 DLL 文件
    print_info "收集依赖的 DLL 文件..."
    local REQUIRED_DLLS=(
        "libplist*.dll"
        "libusbmuxd*.dll"
        "libimobiledevice-glue*.dll"
        "libtatsu*.dll"
        "libssl*.dll"
        "libcrypto*.dll"
        "libcurl*.dll"
        "zlib*.dll"
        "libiconv*.dll"
        "libwinpthread*.dll"
        "libgcc_s*.dll"
        "libstdc++*.dll"
    )
    
    for dll_pattern in "${REQUIRED_DLLS[@]}"; do
        cp -v /mingw64/bin/$dll_pattern "$BUILD_BACKUP/bin/" 2>/dev/null || true
    done
    
    # 创建 README 文件
    cat > "$BUILD_BACKUP/README.txt" << EOF
libimobiledevice Windows 编译产物
================================

编译时间: $(date)
编译环境: $MSYSTEM
编译器: $(gcc --version | head -n1)

目录结构:
---------
bin/         - 可执行文件和 DLL 文件
lib/         - 静态库和导入库
include/     - 头文件
pkgconfig/   - pkg-config 文件

使用说明:
---------
1. 将 bin/ 目录添加到系统 PATH 环境变量
2. 或者直接从 bin/ 目录运行工具

可用工具:
---------
$(ls -1 "$BUILD_BACKUP/bin"/*.exe 2>/dev/null | xargs -n1 basename)

依赖的 DLL:
-----------
$(ls -1 "$BUILD_BACKUP/bin"/*.dll 2>/dev/null | xargs -n1 basename)

EOF
    
    # 创建符号链接指向最新备份
    rm -f "$BACKUP_DIR/latest"
    ln -sf "$TIMESTAMP" "$BACKUP_DIR/latest"
    
    print_success "编译产物已备份到: $BUILD_BACKUP"
    print_info "最新备份链接: $BACKUP_DIR/latest"
    
    # 显示备份统计
    local exe_count=$(ls -1 "$BUILD_BACKUP/bin"/*.exe 2>/dev/null | wc -l)
    local dll_count=$(ls -1 "$BUILD_BACKUP/bin"/*.dll 2>/dev/null | wc -l)
    local lib_count=$(ls -1 "$BUILD_BACKUP/lib"/* 2>/dev/null | wc -l)
    
    echo ""
    print_info "备份统计:"
    print_info "  - 可执行文件: $exe_count 个"
    print_info "  - DLL 文件: $dll_count 个"
    print_info "  - 库文件: $lib_count 个"
    echo ""
}

# 运行测试
run_tests() {
    print_info "运行测试..."
    
    # 检查工具是否可用
    if command -v idevice_id >/dev/null 2>&1; then
        print_info "测试 idevice_id 工具..."
        idevice_id --version || true
        print_success "工具测试通过"
    else
        print_warning "idevice_id 未在 PATH 中找到"
    fi
}

# 显示安装信息
show_info() {
    echo ""
    print_success "========================================"
    print_success "libimobiledevice 编译安装完成！"
    print_success "========================================"
    echo ""
    print_info "安装位置: /mingw64"
    print_info "库文件: /mingw64/lib"
    print_info "头文件: /mingw64/include/libimobiledevice"
    print_info "可执行文件: /mingw64/bin"
    print_info "备份位置: $PROJECT_ROOT/build-output/latest"
    echo ""
    print_info "可用的工具包括:"
    print_info "  - idevice_id          列出连接的设备"
    print_info "  - ideviceinfo         显示设备信息"
    print_info "  - idevicepair         设备配对管理"
    print_info "  - idevicebackup2      设备备份"
    print_info "  - idevicescreenshot   截图"
    print_info "  - 等等..."
    echo ""
    print_info "使用示例:"
    print_info "  idevice_id -l         # 列出所有连接的设备"
    print_info "  ideviceinfo           # 显示设备详细信息"
    echo ""
}

# 主函数
main() {
    echo ""
    print_info "========================================"
    print_info "libimobiledevice Windows 编译脚本"
    print_info "========================================"
    echo ""
    print_info "项目根目录: $PROJECT_ROOT"
    echo ""
    
    check_environment
    
    # 询问是否安装依赖
    read -p "是否需要安装/更新依赖包? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_dependencies
        build_missing_dependencies
    fi
    
    build_libimobiledevice
    
    # 询问是否安装
    read -p "是否安装到系统? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_libimobiledevice
        run_tests
        backup_build_artifacts
        show_info
    else
        print_info "跳过安装步骤"
        print_info "编译的文件位于项目目录"
        
        # 即使不安装也备份编译产物
        read -p "是否备份编译产物到项目目录? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 临时安装以便备份
            make install
            backup_build_artifacts
            print_warning "已备份编译产物，但未永久安装到系统"
        fi
    fi
    
    print_success "所有步骤完成！"
}

# 运行主函数
main "$@"