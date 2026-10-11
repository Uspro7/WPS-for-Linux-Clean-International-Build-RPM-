#!/bin/bash
# ==============================================================================
# build-rpm.sh: WPS Office Linux 纯净版 Fedora RPM 一键构建脚本
# 特性：
# 1. 底包采用官方国际版 (International Edition)，并删除已知云端、更新和推广组件
# 2. 注入中文资源与模板，显式设置中文界面并补齐六种公式符号字体
# 3. 彻底清除金山流氓菜单: 剔除 /etc/xdg/menus/ 等配置，图标归入系统标准【办公 (Office)】
# 4. 适配 Wayland 下 Fcitx5 输入法兼容
# 5. 命令前缀优化: et -> wpset, wpp -> wpswpp (避免命令冲突)
# 6. 原生 RPM 打包: 完全针对 Fedora 44 (KDE Plasma) 等 RPM 系统优化
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}/build"
DOWNLOAD_DIR="${BASE_DIR}/raw"
EXTRACT_DIR="${BASE_DIR}/extracted"
REPACK_DIR="${BASE_DIR}/repack"
DIST_DIR="${BASE_DIR}/dist"
RPM_TOPDIR="${BASE_DIR}/rpmbuild"

mkdir -p "${DOWNLOAD_DIR}" "${EXTRACT_DIR}" "${REPACK_DIR}" "${DIST_DIR}"

# 颜色输出
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# 1. 检查必备构建工具
check_deps() {
    info "检查构建依赖工具..."
    local missing=()
    for cmd in rpmbuild rpm rpm2cpio cpio wget curl unzip sha256sum python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        error "缺少必要工具: ${missing[*]}，请使用 sudo dnf install ${missing[*]} 安装。"
    fi
    success "所有构建依赖就绪。"
}

# 2. 确定版本与下载地址。优先使用仓库内已经准备好的官方 RPM，避免无意义下载。
resolve_sources() {
    local int_local chn_local
    int_local=$(find "${DOWNLOAD_DIR}" -maxdepth 1 -type f -name 'wps-office-*.XA-*.x86_64.rpm' | sort | head -n 1)
    chn_local=$(find "${DOWNLOAD_DIR}" -maxdepth 1 -type f -name 'wps-office-*.Personal-*.x86_64.rpm' | sort | head -n 1)

    if [ -n "$int_local" ]; then
        INT_RPM_FILE="$int_local"
        INT_RPM_NAME="$(basename "$INT_RPM_FILE")"
        INT_RPM_URL=''
    else
        INT_VER='11.1.0.11723.XA'
        INT_BUILD='11723'
        INT_RPM_NAME="wps-office-${INT_VER}-1.x86_64.rpm"
        INT_RPM_FILE="${DOWNLOAD_DIR}/${INT_RPM_NAME}"
        INT_RPM_URL="https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/${INT_BUILD}/${INT_RPM_NAME}"
    fi

    if [ -n "$chn_local" ]; then
        CHN_RPM_FILE="$chn_local"
        CHN_RPM_NAME="$(basename "$CHN_RPM_FILE")"
        CHN_RPM_URL=''
    else
        local chn_rpm_raw_url download_page
        download_page=$(curl -fsSL 'https://linux.wps.cn' 2>/dev/null || true)
        chn_rpm_raw_url=$(echo "$download_page" | grep -Po "(?<=['\"])http[^'\"]+?\.x86_64\.rpm(?=['\"])" | head -n 1 || true)
        [ -n "$chn_rpm_raw_url" ] || chn_rpm_raw_url='https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2023/28080/wps-office-12.1.2.28080.AK.preread.sw.Personal-1-765475.x86_64.rpm'
        local uri security_key timestamp10 md5hash
        uri="${chn_rpm_raw_url#https://wps-linux-personal.wpscdn.cn}"
        security_key='7f8faaaa468174dc1c9cd62e5f218a5b'
        timestamp10=$(date '+%s')
        md5hash=$(printf '%s%s%s' "$security_key" "$uri" "$timestamp10" | md5sum | cut -d' ' -f1)
        CHN_RPM_URL="${chn_rpm_raw_url}?t=${timestamp10}&k=${md5hash}"
        CHN_RPM_NAME="$(basename "$chn_rpm_raw_url")"
        CHN_RPM_FILE="${DOWNLOAD_DIR}/${CHN_RPM_NAME}"
    fi

    info "国际版底包源: ${INT_RPM_NAME}"
    info "中文资源源: ${CHN_RPM_NAME}"
}

load_rpm_metadata() {
    local int_meta chn_meta
    int_meta=$(rpm -qp --qf '%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}' "$INT_RPM_FILE" 2>/dev/null || true)
    chn_meta=$(rpm -qp --qf '%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}' "$CHN_RPM_FILE" 2>/dev/null || true)
    [ -n "$int_meta" ] || error "无法读取国际版 RPM 元数据: $INT_RPM_FILE"
    [ -n "$chn_meta" ] || error "无法读取中文资源 RPM 元数据: $CHN_RPM_FILE"
    IFS='|' read -r INT_NAME INT_VER INT_RELEASE INT_ARCH <<< "$int_meta"
    IFS='|' read -r CHN_NAME CHN_VER CHN_RELEASE CHN_ARCH <<< "$chn_meta"
    [ "$INT_NAME" = 'wps-office' ] && [ "$CHN_NAME" = 'wps-office' ] || error '输入包不是 wps-office RPM'
    [ "$INT_ARCH" = 'x86_64' ] && [ "$CHN_ARCH" = 'x86_64' ] || error '当前脚本只支持 x86_64 RPM'

    info "国际版底包: ${INT_VER}-${INT_RELEASE} (${INT_RPM_NAME})"
    info "中文资源源: ${CHN_VER}-${CHN_RELEASE} (${CHN_RPM_NAME})"
    if [ "$INT_VER" != "$CHN_VER" ]; then
        warn "国际版与中文资源版本不同：${INT_VER} vs ${CHN_VER}；将仅覆盖 mui/templates，并保留底包版本。"
    fi
}

# 3. 下载软件包
download_file() {
    local url="$1"
    local output="$2"
    if [ -f "$output" ]; then
        info "文件已存在，跳过下载: $(basename "$output")"
        return 0
    fi
    info "正在下载: $(basename "$output") ..."
    wget -c -q --show-progress --progress=bar:force:noscroll -O "$output" "$url" || error "下载失败: $url"
}

# 4. 解压提取
extract_rpm() {
    local rpm_file="$1"
    local target_dir="$2"
    shift 2 || true
    local patterns=("$@")

    if [ -d "$target_dir" ] && [ "$(ls -A "$target_dir")" ]; then
        info "解压目录已存在，跳过解压: $target_dir"
        return 0
    fi
    info "正在解包 $(basename "$rpm_file") ..."
    mkdir -p "$target_dir"
    if [ ${#patterns[@]} -gt 0 ]; then
        (cd "$target_dir" && rpm2cpio "$rpm_file" | cpio -idm "${patterns[@]}" >/dev/null 2>&1)
    else
        rpm2cpio "$rpm_file" | cpio -idm -D "$target_dir" >/dev/null 2>&1
    fi
    success "解包完成: $target_dir"
}

# 固定字体归档及校验值；这些是曾随 WPS Linux 分发的专有符号字体。
install_symbol_fonts() {
    local archive="${DOWNLOAD_DIR}/wps_symbol_fonts.zip"
    local expected_sha256='01e965dc81167ae816b3bbd7076986bf2fb64a2c456a077df677f8882dabcbe2'
    local destination="${REPACK_DIR}/usr/share/fonts/wps-office"
    download_file 'https://github.com/Rongronggg9/wps-fonts/releases/download/publish/wps_symbol_fonts.zip' "$archive"
    printf '%s  %s\n' "$expected_sha256" "$archive" | sha256sum -c - || error "符号字体归档校验失败: $archive"
    mkdir -p "$destination"
    unzip -jo "$archive" symbol.ttf wingding.ttf WINGDNG2.ttf WINGDNG3.ttf WEBDINGS.TTF mtextra.ttf -d "$destination" >/dev/null
    chmod 644 "$destination"/*.ttf "$destination"/*.TTF
    success '六种公式符号字体已加入 RPM。'
}

# 5. 核心定制与净化
repack_and_sanitize() {
    local base_extracted="${EXTRACT_DIR}/int_base"
    local chn_extracted="${EXTRACT_DIR}/chn_l10n"

    info "正在初始化纯净构建目录..."
    rm -rf "${REPACK_DIR}"
    mkdir -p "${REPACK_DIR}"
    cp -a "${base_extracted}/." "${REPACK_DIR}/"

    # [1] 注入中文语言包与模板 (+mui)
    info "[1/5] 正在注入国内版简体中文语言包与模板..."
    local int_mui="${REPACK_DIR}/opt/kingsoft/wps-office/office6/mui"
    local int_templates="${REPACK_DIR}/opt/kingsoft/wps-office/templates"
    local chn_mui="${chn_extracted}/opt/kingsoft/wps-office/office6/mui"
    local chn_templates="${chn_extracted}/opt/kingsoft/wps-office/templates"

    if [ -d "$chn_mui" ]; then
        # 保留国际版自己的 default/en_US 皮肤及核心资源，仅注入简体中文。
        rm -rf "$int_mui/zh_CN"
        cp -a "$chn_mui/zh_CN" "$int_mui/zh_CN"
    fi
    if [ -d "$chn_templates" ]; then
        rm -rf "$int_templates"
        cp -a "$chn_templates" "$int_templates"
    fi
    [ -d "$int_mui/zh_CN" ] || error '中文语言资源缺失，终止构建。'
    python3 "${SCRIPT_DIR}/src/wps_qm_compat.py" "${REPACK_DIR}/opt/kingsoft/wps-office/office6"
    install_symbol_fonts
    cp "${SCRIPT_DIR}/src/wps-locale.sh" "${REPACK_DIR}/opt/kingsoft/wps-office/office6/wps-locale.sh"
    success "简体中文资源与启动语言设置已准备。"

    # [2] 删除云端、更新器、推广入口和官方安装钩子；不碰核心编辑/渲染组件。
    info "[2/5] 正在删除云端、更新、推广和官方安装钩子..."
    rm -rf "${REPACK_DIR}/opt/kingsoft/wps-office/INSTALL"
    rm -rf "${REPACK_DIR}/opt/kingsoft/wps-office/office6/wpscloudsvr"
    rm -rf "${REPACK_DIR}/opt/kingsoft/wps-office/office6/wpsd"
    rm -rf "${REPACK_DIR}/opt/kingsoft/wps-office/office6/addons/cloudpushsdk"
    rm -rf "${REPACK_DIR}/opt/kingsoft/wps-office/office6/addons/kappcenter"
    rm -rf "${REPACK_DIR}/opt/kingsoft/wps-office/office6/addons/kcloudfiledialog"
    rm -rf "${REPACK_DIR}/opt/kingsoft/wps-office/office6/addons/kclouddocs"
    rm -rf "${REPACK_DIR}/opt/kingsoft/wps-office/office6/addons/qing"
    rm -rf "${REPACK_DIR}/opt/kingsoft/wps-office/office6/addons/jsapi"
    rm -f "${REPACK_DIR}/opt/kingsoft/wps-office/office6/"ksowebstartup*
    # 这些共享库会被 WPS 主程序的 ELF NEEDED 直接引用，保留它们可避免
    # 安装时产生错误依赖、启动时崩溃；真正的服务进程和插件目录已在上面移除。
    rm -f "${REPACK_DIR}/opt/kingsoft/wps-office/office6/libwpscloudsvrimp.so"
    rm -f "${REPACK_DIR}/opt/kingsoft/wps-office/desktops/wps-office-prometheus.desktop"
    rm -f "${REPACK_DIR}/usr/share/applications/wps-office-prometheus.desktop"
    rm -f "${REPACK_DIR}/etc/cron.d/wpsupdatetask"
    rm -f "${REPACK_DIR}/etc/logrotate.d/wps-office"
    find "${REPACK_DIR}/etc/xdg/autostart" -type f -iname '*wps*' -delete 2>/dev/null || true
    rm -rf "${REPACK_DIR}/etc/xdg/menus" "${REPACK_DIR}/usr/share/desktop-directories"
    # 删除独立 WPS PDF 程序与桌面/PDF 关联入口；保留共享渲染库以免破坏文档导出 PDF。
    rm -f "${REPACK_DIR}/usr/bin/wpspdf" \
        "${REPACK_DIR}/opt/kingsoft/wps-office/office6/wpspdf" \
        "${REPACK_DIR}/opt/kingsoft/wps-office/desktops/wps-office-pdf.desktop" \
        "${REPACK_DIR}/usr/share/applications/wps-office-pdf.desktop"
    success "云端、更新、推广、官方安装脚本及独立 WPS PDF 已移除。"

    # [3] 清理私有分类和金山协议入口
    info "[3/5] 正在清理'金山软件'独立菜单..."

    # 处理所有 .desktop 文件，规范归入系统的【办公】分类
    for desktop in "${REPACK_DIR}/usr/share/applications"/*.desktop "${REPACK_DIR}/opt/kingsoft/wps-office/desktops"/*.desktop; do
        [ -f "$desktop" ] || continue
        # 移除私有分类
        sed -i 's/X-Kingsoft-Office;//g' "$desktop"
        sed -i 's/;X-Kingsoft-Office//g' "$desktop"
        sed -i 's/X-Kingsoft-Office//g' "$desktop"

        # 确保包含标准 Office 分类
        if ! grep -q "Categories=.*Office" "$desktop"; then
            sed -i '/^Categories=/s/$/Office;/' "$desktop"
        fi

        # 补全中文名称显示
        case "$(basename "$desktop")" in
            *wps.desktop)
                grep -q "Name\[zh_CN\]" "$desktop" || sed -i '/^Name=/a Name[zh_CN]=WPS 文字' "$desktop"
                ;;
            *et.desktop)
                grep -q "Name\[zh_CN\]" "$desktop" || sed -i '/^Name=/a Name[zh_CN]=WPS 表格' "$desktop"
                ;;
            *wpp.desktop)
                grep -q "Name\[zh_CN\]" "$desktop" || sed -i '/^Name=/a Name[zh_CN]=WPS 演示' "$desktop"
                ;;
            *pdf.desktop)
                grep -q "Name\[zh_CN\]" "$desktop" || sed -i '/^Name=/a Name[zh_CN]=WPS PDF' "$desktop"
                ;;
        esac
    done
    # 去掉 WPS 专有协议入口，保留普通文档 MIME 关联。
    find "${REPACK_DIR}" -type f \( -name '*.desktop' -o -name '*.xml' \) -print0 2>/dev/null | xargs -0r sed -i '/x-scheme-handler\/ksoqing/d'
    success "流氓菜单已清理，普通组件归入【办公 (Office)】。"

    # [4] 命令重命名防冲突 (+prefixed)
    info "[4/5] 正在处理命令重命名 (et -> wpset, wpp -> wpswpp)..."
    for comp in "et" "wpp"; do
        if [ -f "${REPACK_DIR}/usr/bin/${comp}" ]; then
            mv "${REPACK_DIR}/usr/bin/${comp}" "${REPACK_DIR}/usr/bin/wps${comp}"
            for df in "${REPACK_DIR}/usr/share/applications/wps-office-${comp}.desktop" "${REPACK_DIR}/opt/kingsoft/wps-office/desktops/wps-office-${comp}.desktop"; do
                [ -f "$df" ] && sed -i "s#/usr/bin/${comp}#/usr/bin/wps${comp}#g" "$df"
            done
        fi
    done
    for bin in wps wpset wpswpp; do
        sed -i "1a\. '/opt/kingsoft/wps-office/office6/wps-locale.sh'" "${REPACK_DIR}/usr/bin/$bin"
    done
    success "命令防冲突处理与中文启动设置完成。"

    # [5] 注入 Wayland / Fcitx5 修复脚本
    info "[5/5] 正在注入 Wayland / Fcitx5 输入法补丁..."
    local fcitx_src="${SCRIPT_DIR}/src/fcitx5xwayland.sh"
    local fcitx_dest="${REPACK_DIR}/opt/kingsoft/wps-office/office6/fcitx5xwayland.sh"
    if [ -f "$fcitx_src" ]; then
        cp "$fcitx_src" "$fcitx_dest"
        chmod +x "$fcitx_dest"
        for bin in "${REPACK_DIR}/usr/bin"/wps*; do
            [ -f "$bin" ] || continue
            sed -i "1a\. '/opt/kingsoft/wps-office/office6/fcitx5xwayland.sh'" "$bin"
        done
        success "Fcitx5 Wayland 输入法补丁已注入。"
    fi
    # 只保留可能有用的系统配置目录；清除净化后遗留的空目录。
    find "${REPACK_DIR}/etc" -depth -type d -empty -delete 2>/dev/null || true
}

# 6. 原生 RPM 打包
build_rpm() {
    info "正在准备 Fedora 原生 RPM 构建环境..."
    rm -rf "${RPM_TOPDIR}"
    mkdir -p "${RPM_TOPDIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

    local pkg_version="${INT_VER}"
    local pkg_release="4.linuxwps%{?dist}"
    local spec_file="${RPM_TOPDIR}/SPECS/wps-office.spec"

    mkdir -p "${RPM_TOPDIR}/SOURCES/root"
    cp -a "${REPACK_DIR}/." "${RPM_TOPDIR}/SOURCES/root/"

    # 编写 RPM SPEC 文件
    info "正在生成 wps-office.spec..."
    cat > "$spec_file" << EOF
Name:           wps-office
Version:        ${pkg_version}
Release:        ${pkg_release}
Summary:        Kingsoft WPS Office (Clean International Edition with zh_CN)
License:        Proprietary
Group:          Applications/Productivity
AutoReqProv:    no
URL:            https://linux.wps.cn
Provides:       wps-office = %{version}-%{release}
Requires:       fontconfig, freetype, libX11, libXext, libXrender, glibc

%define _build_id_links none
%define __strip /bin/true
%define _strip_mode none
%define __os_install_post %{nil}
# Fedora 原生支持 zstd，使用低压缩级加快本地重打包。
%define _binary_payload w3.zstdio

%description
WPS Office for Linux, repackaged from the official International RPM.
- Known cloud, updater, promotion, and installer-hook components removed.
- zh_CN localization and templates injected; Chinese UI explicitly selected.
- Six formula symbol fonts bundled; standalone WPS PDF application removed.
- Desktop entries cleaned up and placed under the standard Office category.
- Wayland Fcitx5 input method fixes included.

%prep

%build

%install
cp -a %{_sourcedir}/root/* %{buildroot}/

%post
/usr/bin/fc-cache -f /usr/share/fonts/wps-office &>/dev/null || :
/bin/touch --no-create /usr/share/icons/hicolor &>/dev/null || :
/usr/bin/update-desktop-database &>/dev/null || :
/usr/bin/update-mime-database /usr/share/mime &>/dev/null || :

%postun
/usr/bin/fc-cache -f &>/dev/null || :
/bin/touch --no-create /usr/share/icons/hicolor &>/dev/null || :
/usr/bin/update-desktop-database &>/dev/null || :
/usr/bin/update-mime-database /usr/share/mime &>/dev/null || :

%files
/opt/kingsoft
/usr/bin/wps*
/usr/share/applications/wps-office-*.desktop
/usr/share/fonts/wps-office
/usr/share/icons/hicolor/*/*/*
/usr/share/mime/packages/wps-office-*.xml
/usr/share/templates/*
/usr/share/templates/.source

%changelog
* Mon Oct 12 2026 LinuxWPS <local@localhost> - ${pkg_version}-${pkg_release}
- Fix Chinese UI selection and missing symbol fonts; remove standalone PDF app
EOF

    info "正在使用 rpmbuild 编译 RPM 安装包 (这可能需要 1~2 分钟)..."
    rpmbuild --define "_topdir ${RPM_TOPDIR}" -bb "$spec_file"

    # 移动产物；避免旧 RPM 与新 RPM 一起被用户的通配符误装。
    find "${DIST_DIR}" -maxdepth 1 -type f -name '*.rpm' -delete
    local generated_rpm
    generated_rpm=$(find "${RPM_TOPDIR}/RPMS" -name "*.rpm" | head -n 1)
    if [ -z "$generated_rpm" ] || [ ! -f "$generated_rpm" ]; then
        error "RPM 构建失败，未能生成 .rpm 文件！"
    fi

    cp "$generated_rpm" "${DIST_DIR}/"
    local final_rpm="${DIST_DIR}/$(basename "$generated_rpm")"

    success "============================================================"
    success "Fedora 原生纯净版 RPM 构建成功！"
    success "输出文件: ${final_rpm}"
    success "安装命令: sudo dnf install ${final_rpm}"
    success "============================================================"
}

main() {
    check_deps
    resolve_sources
    [ -z "${INT_RPM_URL:-}" ] || download_file "$INT_RPM_URL" "$INT_RPM_FILE"
    [ -z "${CHN_RPM_URL:-}" ] || download_file "$CHN_RPM_URL" "$CHN_RPM_FILE"
    load_rpm_metadata
    extract_rpm "$INT_RPM_FILE" "${EXTRACT_DIR}/int_base"
    extract_rpm "$CHN_RPM_FILE" "${EXTRACT_DIR}/chn_l10n" "*opt/kingsoft/wps-office/office6/mui*" "*opt/kingsoft/wps-office/templates*"
    repack_and_sanitize
    build_rpm
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
