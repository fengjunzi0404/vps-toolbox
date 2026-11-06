#!/usr/bin/env bash
# ==============================================================================
# VPS 开源工具箱 Pro (Sing-box · FRP · WARP · 建站 · 全能短链版) | Official Edition
# ------------------------------------------------------------------------------
# 核心特色与安全准则：
# 1. 【纯净官方源】仅收录官方源与 GitHub 高 Star 原作者直链，零第三方反代 (ghproxy)、
#    零未知短链、零来路不明改版脚本，彻底杜绝供应链投毒。
# 2. 【源码级审计拦截】调用任何外部开源脚本前，自动展示原作者仓库、Raw 直链与执行命令
#    （可在设置中切换「安全确认模式 / 极速免确认模式」）。
# 3. 【原生运维与硬件跑分引擎】内置原生硬件性能基准测试看板 (CPU AES/ChaCha20 加密吞吐、
#    内存带宽、磁盘三轮 I/O 实测)、fatedier/frp 原生总控台、Caddy/NPM 反代建站向导、
#    XIU2 Cloudflare 优选 IP 测速、SSL 证书总控台。
# 4. 【全能长链接转短链接中心】支持：① 终端输入任意长链接（节点订阅/网页/脚本）实时转短链
#    （支持自定义后缀）；② 一键批量将工具箱内所有 20+ 个长脚本链接转为短链清单或生成全路由
#    Cloudflare Worker 短链网关；③ Docker 一键自建开源 Shlink 私人短链接平台。
# ==============================================================================

set -u

VERSION="2.4.0"
SHORTCUT_PATH="/usr/local/bin/vps"
AUDIT_MODE=1  # 1=开启外部脚本源地址审计确认(默认), 0=极速直连执行
SELF_UPDATE_URL="" # 部署到你的 GitHub 后，可填入你的短链或 https://raw.githubusercontent.com/<用户名>/<仓库>/main/vps-toolbox.sh

# 终端色彩定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ==============================================================================
# 基础通用函数
# ==============================================================================

check_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        echo -e "${RED}[错误] 请使用 root 权限运行本工具箱 (例如: sudo bash $0)${NC}"
        exit 1
    fi
}

detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
}

pkg_install() {
    local pkg_mgr
    pkg_mgr="$(detect_pkg_manager)"
    case "$pkg_mgr" in
        apt) apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        dnf) dnf install -y "$@" ;;
        yum) yum install -y "$@" ;;
        apk) apk add --no-cache "$@" ;;
        *) echo -e "${RED}[错误] 未识别当前系统的包管理器，请手动安装: $*${NC}"; return 1 ;;
    esac
}

check_dependencies() {
    local missing=()
    for cmd in curl wget tar openssl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}[初始化] 正在安装必要基础组件: ${missing[*]} ...${NC}"
        pkg_install "${missing[@]}" ca-certificates
    fi
}

pause_return() {
    echo ""
    read -rp "按回车键 (Enter) 继续..." _
}

# 透明审计执行器：支持审计确认与极速模式
run_verified_script() {
    local name="$1"
    local repo_url="$2"
    local raw_url="$3"
    local run_cmd="$4"

    echo ""
    echo -e "${CYAN}======================================================================${NC}"
    echo -e " ${BOLD}组件名称:${NC} ${GREEN}${name}${NC}"
    echo -e " ${BOLD}开源仓库:${NC} ${YELLOW}${repo_url}${NC}"
    echo -e " ${BOLD}官方直链:${NC} ${BLUE}${raw_url}${NC}"
    echo -e " ${BOLD}执行指令:${NC} ${run_cmd}"
    echo -e "${CYAN}======================================================================${NC}"

    if [[ "$AUDIT_MODE" -eq 1 ]]; then
        read -rp "确认从上述官方源拉取并执行吗？[Y/n]: " confirm
        confirm="${confirm:-Y}"
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}[已取消] 未执行该脚本。${NC}"
            pause_return
            return
        fi
    fi

    echo -e "${GREEN}[运行中] 正在连接官方源执行...${NC}"
    eval "$run_cmd"
    pause_return
}

# 顶部实时状态仪表盘 (一眼掌握核心状态与组件安装情况)
render_dashboard() {
    local os_name="Linux"
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_name="${PRETTY_NAME:-$NAME}"
    fi
    local kernel arch bbr_cc qdisc mem_info disk_info
    kernel="$(uname -r)"
    arch="$(uname -m)"
    bbr_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'unknown')"
    qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo 'unknown')"
    mem_info="$(free -m 2>/dev/null | awk '/Mem:/ {printf "%d/%d MB (%.0f%%)", $3, $2, ($2>0?$3*100/$2:0)}' || echo 'N/A')"
    disk_info="$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s/%s (%s)", $3, $2, $5}' || echo 'N/A')"

    local sb_badge="${RED}未装${NC}"
    if command -v sing-box >/dev/null 2>&1 || [[ -x /etc/sing-box/sing-box ]] || [[ -x /usr/local/bin/sing-box ]]; then
        sb_badge="${GREEN}就绪${NC}"
    fi

    local frp_badge="${RED}未装${NC}"
    if [[ -x /usr/local/bin/frps && -x /usr/local/bin/frpc ]]; then
        frp_badge="${GREEN}frps+frpc${NC}"
    elif [[ -x /usr/local/bin/frps ]] || command -v frps >/dev/null 2>&1; then
        frp_badge="${GREEN}frps${NC}"
    elif [[ -x /usr/local/bin/frpc ]] || command -v frpc >/dev/null 2>&1; then
        frp_badge="${GREEN}frpc${NC}"
    fi

    local warp_badge="${RED}未装${NC}"
    if ip link show wgcf >/dev/null 2>&1 || ip link show warp >/dev/null 2>&1 || command -v warp-cli >/dev/null 2>&1; then
        warp_badge="${GREEN}已启用${NC}"
    fi

    local web_badge="${RED}未装${NC}"
    if command -v caddy >/dev/null 2>&1; then
        web_badge="${GREEN}Caddy${NC}"
    elif command -v docker >/dev/null 2>&1 && docker ps 2>/dev/null | grep -qi "nginx-proxy-manager"; then
        web_badge="${GREEN}NPM${NC}"
    fi

    local docker_badge="${RED}未装${NC}"
    if command -v docker >/dev/null 2>&1; then
        docker_badge="${GREEN}就绪${NC}"
    fi

    local audit_badge="${GREEN}开启${NC}"
    [[ "$AUDIT_MODE" -eq 0 ]] && audit_badge="${YELLOW}免确认${NC}"

    echo -e "${BOLD}${BLUE}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}  VPS 开源工具箱 Pro v${VERSION} | Sing-box · FRP · WARP · 反代 · 短链中心${NC}"
    echo -e "${BOLD}${BLUE}======================================================================${NC}"
    echo -e " ${BOLD}系统:${NC} ${os_name} (${arch})  ${BOLD}内核:${NC} ${kernel}"
    echo -e " ${BOLD}内存:${NC} ${mem_info}  |  ${BOLD}硬盘:${NC} ${disk_info}  |  ${BOLD}加速:${NC} ${GREEN}${bbr_cc}+${qdisc}${NC}"
    echo -e " ${BOLD}组件:${NC} [Sing-box:${sb_badge}] [FRP:${frp_badge}] [WARP:${warp_badge}] [反代:${web_badge}] [Docker:${docker_badge}] [审计:${audit_badge}]"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
}

# ==============================================================================
# 原生内置硬件性能基准测试与可视化评分看板 (零外部脚本依赖，直观显示硬件性能)
# ==============================================================================
run_native_hardware_bench() {
    clear
    echo -e "${BOLD}${BLUE}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}       🚀 本机硬件性能基准实测看板 (CPU 加密 / 内存带宽 / 磁盘 I/O)${NC}"
    echo -e "${BOLD}${BLUE}======================================================================${NC}"

    local cpu_model cpu_cores cpu_freq virt_type aes_flag avx_flag
    cpu_model="$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^[ \t]*//')"
    [[ -z "$cpu_model" ]] && cpu_model="$(lscpu 2>/dev/null | awk -F: '/Model name:/ {print $2}' | sed 's/^[ \t]*//' || uname -p)"
    cpu_cores="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)"
    cpu_freq="$(awk -F: '/cpu MHz/ {printf "%.0f MHz", $2; exit}' /proc/cpuinfo 2>/dev/null)"
    virt_type="$(systemd-detect-virt 2>/dev/null || echo 'Dedicated/Unknown')"

    if grep -qi "aes" /proc/cpuinfo 2>/dev/null; then
        aes_flag="${GREEN}✔ 支持 (AES-NI 硬件加速已就绪)${NC}"
    else
        aes_flag="${RED}✘ 不支持 (AES 加密性能可能受限)${NC}"
    fi

    if grep -qi "avx2" /proc/cpuinfo 2>/dev/null; then
        avx_flag="${GREEN}✔ 支持 AVX2${NC}"
    elif grep -qi "avx" /proc/cpuinfo 2>/dev/null; then
        avx_flag="${YELLOW}✔ 支持 AVX${NC}"
    else
        avx_flag="${YELLOW}基础指令集${NC}"
    fi

    echo -e "${BOLD}${YELLOW}【一、处理器与虚拟化硬件拓扑】${NC}"
    echo -e "  ${BOLD}CPU 型号    :${NC} ${CYAN}${cpu_model}${NC}"
    echo -e "  ${BOLD}逻辑核心数  :${NC} ${GREEN}${cpu_cores} 核${NC} ${cpu_freq:+(主频: $cpu_freq)}  |  ${BOLD}虚拟化架构:${NC} ${PURPLE}${virt_type}${NC}"
    echo -e "  ${BOLD}AES-NI 加速 :${NC} ${aes_flag}  |  ${BOLD}向量指令集:${NC} ${avx_flag}"
    echo ""

    echo -e "${BOLD}${YELLOW}【二、CPU 代理协议加密吞吐量实测 (Sing-box / Reality / SS-2022 核心指标)】${NC}"
    echo -e "  正在执行 OpenSSL 硬件加密基准测试 (约需 6 秒)..."
    local aes_speed chacha_speed aes_mbps
    aes_speed="$(openssl speed -elapsed -evp aes-256-gcm 2>/dev/null | awk '/^aes-256-gcm/ {print $NF}')"
    chacha_speed="$(openssl speed -elapsed -evp chacha20-poly1305 2>/dev/null | awk '/^chacha20-poly1305/ {print $NF}')"

    if [[ -n "$aes_speed" ]]; then
        aes_mbps="$(awk -v k="${aes_speed%k}" 'BEGIN {printf "%.1f MB/s (约合 %.2f Gbps 代理吞吐极限)", k/1024, (k*8)/(1024*1024)}')"
        echo -e "  ${BOLD}AES-256-GCM 单核吞吐      :${NC} ${GREEN}${aes_mbps}${NC}"
    else
        echo -e "  ${BOLD}AES-256-GCM 单核吞吐      :${NC} N/A"
    fi

    if [[ -n "$chacha_speed" ]]; then
        local chacha_mbps
        chacha_mbps="$(awk -v k="${chacha_speed%k}" 'BEGIN {printf "%.1f MB/s (约合 %.2f Gbps 代理吞吐极限)", k/1024, (k*8)/(1024*1024)}')"
        echo -e "  ${BOLD}ChaCha20-Poly1305 单核吞吐:${NC} ${GREEN}${chacha_mbps}${NC}"
    fi
    echo ""

    echo -e "${BOLD}${YELLOW}【三、内存 (/dev/shm) 连续写入带宽实测】${NC}"
    if [[ -d /dev/shm ]]; then
        local mem_dd_out mem_speed
        mem_dd_out="$(dd if=/dev/zero of=/dev/shm/.vps_mem_bench bs=1M count=256 2>&1)"
        rm -f /dev/shm/.vps_mem_bench
        mem_speed="$(echo "$mem_dd_out" | awk '/copied/ {print $(NF-1), $NF}')"
        echo -e "  ${BOLD}内存读写速率 :${NC} ${GREEN}${mem_speed:-N/A}${NC}"
    fi
    echo ""

    echo -e "${BOLD}${YELLOW}【四、磁盘落盘 I/O 连续读写实测 (3 轮 128MB 真实落盘均值)】${NC}"
    local io1 io2 io3
    echo -ne "  第 1 轮测试中... "
    io1="$( (LANG=C dd if=/dev/zero of=/root/.vps_io_test bs=1M count=128 conv=fdatasync 2>&1) | awk '/copied/ {print $(NF-1), $NF}' )"
    rm -f /root/.vps_io_test
    echo -e "${GREEN}${io1:-N/A}${NC}"

    echo -ne "  第 2 轮测试中... "
    io2="$( (LANG=C dd if=/dev/zero of=/root/.vps_io_test bs=1M count=128 conv=fdatasync 2>&1) | awk '/copied/ {print $(NF-1), $NF}' )"
    rm -f /root/.vps_io_test
    echo -e "${GREEN}${io2:-N/A}${NC}"

    echo -ne "  第 3 轮测试中... "
    io3="$( (LANG=C dd if=/dev/zero of=/root/.vps_io_test bs=1M count=128 conv=fdatasync 2>&1) | awk '/copied/ {print $(NF-1), $NF}' )"
    rm -f /root/.vps_io_test
    echo -e "${GREEN}${io3:-N/A}${NC}"

    echo -e "${BOLD}${BLUE}======================================================================${NC}"
    pause_return
}

# ==============================================================================
# 模块 1：系统信息、网络状态与原生硬件性能实测中心
# ==============================================================================
menu_sysinfo() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [1] 系统详细体检与本机硬件性能实测中心 ===${NC}"
        echo ""
        local cpu_model cpu_cores load_avg tz_info ipv4_info ipv6_info warp_trace
        cpu_model="$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^[ \t]*//')"
        [[ -z "$cpu_model" ]] && cpu_model="$(uname -p)"
        cpu_cores="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)"
        load_avg="$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || echo 'N/A')"
        tz_info="$(timedatectl 2>/dev/null | awk '/Time zone:/ {print $3, $4}' || date '+%Z %z')"
        ipv4_info="$(curl -s4m 4 https://ipinfo.io/ip 2>/dev/null || echo '无 IPv4')"
        ipv6_info="$(curl -s6m 4 https://ip6.me/api/ 2>/dev/null | cut -d, -f2 || echo '无 IPv6')"
        warp_trace="$(curl -sm 4 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^warp=/ {print $2}' || echo 'off')"

        echo -e " ${BOLD}CPU 型号 :${NC} ${cpu_model} (${cpu_cores} 核)"
        echo -e " ${BOLD}系统负载 :${NC} ${load_avg}"
        echo -e " ${BOLD}系统时区 :${NC} ${tz_info} (当前时间: $(date '+%Y-%m-%d %H:%M:%S'))"
        echo -e " ${BOLD}公网 IPv4:${NC} ${GREEN}${ipv4_info}${NC}  |  ${BOLD}公网 IPv6:${NC} ${YELLOW}${ipv6_info}${NC}"
        echo -e " ${BOLD}WARP 状态:${NC} ${CYAN}warp=${warp_trace:-off}${NC} (off=未接管全局出站, on/plus=已接管)"
        echo ""
        echo -e "${BOLD}--- 内存与虚拟内存 (Swap) ---${NC}"
        free -h
        echo ""
        echo -e "${BOLD}--- 磁盘挂载与空间占用 ---${NC}"
        df -hT | grep -vE 'tmpfs|devtmpfs|overlay'
        echo ""
        echo -e "${BOLD}--- 当前监听中的高优端口 (前 12 项) ---${NC}"
        if command -v ss >/dev/null 2>&1; then
            ss -tulpn | head -n 13
        elif command -v netstat >/dev/null 2>&1; then
            netstat -tulpn | head -n 13
        fi
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e "  ${GREEN}1.${NC} 🚀 运行【原生硬件性能基准实测】 ${CYAN}(实时测试 CPU 加密吞吐 / 内存带宽 / 磁盘三轮 I/O)${NC}"
        echo -e "  ${GREEN}0.${NC} 返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择 [0-1]: " sys_sub
        case "$sys_sub" in
            1) run_native_hardware_bench ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

# ==============================================================================
# 模块 2：Sing-box 核心与主流多协议部署 (核心主打)
# ==============================================================================
menu_singbox() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [2] Sing-box 核心与高 Star 多协议一键部署 ===${NC}"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e "  ${GREEN}1.${NC} SagerNet 官方 Sing-box 稳定版内核 ${CYAN}(官方 Package 仓库一键安装)${NC}"
        echo -e "  ${GREEN}2.${NC} SagerNet 官方 Sing-box Beta 内核  ${CYAN}(尝鲜最新协议特性如 AnyTLS 等)${NC}"
        echo -e "  ${GREEN}3.${NC} F佬 (fscarmen) Sing-box 全家桶    ${CYAN}(交互式安装：Reality/Hy2/TUIC/Argo/WARP)${NC}"
        echo -e "  ${GREEN}4.${NC} F佬 (fscarmen) Sing-box 极速模式  ${CYAN}(无交互 -l 参数一键自动部署全协议)${NC}"
        echo -e "  ${GREEN}5.${NC} 勇哥 (yonggekkk) Sing-box-yg     ${CYAN}(9k+ Star 五合一精装桶，快捷键 sb)${NC}"
        echo -e "  ${GREEN}6.${NC} 勇哥 (yonggekkk) ArgoSBX 小钢炮  ${CYAN}(无交互多协议+Argo隧道，快捷键 agsbx)${NC}"
        echo -e "  ${GREEN}7.${NC} 233boy Sing-box 极简管理脚本      ${CYAN}(高 Star 经典脚本，自动配置 Reality/Hy2)${NC}"
        echo -e "  ${GREEN}8.${NC} 老王 (eooce) Sing-box 四合一脚本  ${CYAN}(Reality+Hy2+TUIC+Argo，支持 NAT 端口定义)${NC}"
        echo -e "  ${GREEN}9.${NC} Mack-a 八合一 (v2ray-agent)      ${CYAN}(20k+ Star，Sing-box + Xray 双核心自由组合)${NC}"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e "  ${YELLOW}10.${NC} [本地] 查看已安装 Sing-box 运行状态与版本"
        echo -e "  ${YELLOW}11.${NC} [本地] 重启 Sing-box 服务并查看最近 30 行日志"
        echo -e "  ${GREEN}0.${NC}  返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择 Sing-box 操作 [0-11]: " sb_choice

        case "$sb_choice" in
            1)
                run_verified_script \
                    "SagerNet Sing-box 官方稳定版内核" \
                    "https://github.com/SagerNet/sing-box" \
                    "https://sing-box.app/install.sh" \
                    "curl -fsSL https://sing-box.app/install.sh | sh"
                ;;
            2)
                run_verified_script \
                    "SagerNet Sing-box 官方 Beta 版内核" \
                    "https://github.com/SagerNet/sing-box" \
                    "https://sing-box.app/install.sh" \
                    "curl -fsSL https://sing-box.app/install.sh | sh -s -- --beta"
                ;;
            3)
                run_verified_script \
                    "F佬 (fscarmen) Sing-box 全家桶交互安装 (安装后输入 sb 管理)" \
                    "https://github.com/fscarmen/sing-box" \
                    "https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh" \
                    "bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh)"
                ;;
            4)
                run_verified_script \
                    "F佬 (fscarmen) Sing-box 中文极速无交互安装 (-l 参数)" \
                    "https://github.com/fscarmen/sing-box" \
                    "https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh" \
                    "bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh) -l"
                ;;
            5)
                run_verified_script \
                    "勇哥 (yonggekkk) Sing-box-yg 脚本 (安装后输入 sb 管理)" \
                    "https://github.com/yonggekkk/sing-box-yg" \
                    "https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh" \
                    "bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)"
                ;;
            6)
                run_verified_script \
                    "勇哥 (yonggekkk) ArgoSBX 小钢炮脚本 (安装后输入 agsbx 管理)" \
                    "https://github.com/yonggekkk/argosbx" \
                    "https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh" \
                    "bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)"
                ;;
            7)
                run_verified_script \
                    "233boy Sing-box 一键安装与管理脚本 (安装后输入 sb 管理)" \
                    "https://github.com/233boy/sing-box" \
                    "https://github.com/233boy/sing-box/raw/main/install.sh" \
                    "bash <(wget -qO- -o- https://github.com/233boy/sing-box/raw/main/install.sh)"
                ;;
            8)
                run_verified_script \
                    "老王 (eooce) Sing-box 四合一一键脚本 (支持 VPS 与 NAT 小鸡)" \
                    "https://github.com/eooce/Sing-box" \
                    "https://raw.githubusercontent.com/eooce/Sing-box/main/sing-box.sh" \
                    "bash <(curl -Ls https://raw.githubusercontent.com/eooce/Sing-box/main/sing-box.sh)"
                ;;
            9)
                run_verified_script \
                    "Mack-a 八合一一键脚本 (安装后输入 vasin 或 vasma 管理)" \
                    "https://github.com/mack-a/v2ray-agent" \
                    "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh" \
                    "wget -P /root -N --no-check-certificate https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh && chmod 700 /root/install.sh && /root/install.sh"
                ;;
            10)
                echo ""
                if command -v sing-box >/dev/null 2>&1; then
                    sing-box version
                elif [[ -x /etc/sing-box/sing-box ]]; then
                    /etc/sing-box/sing-box version
                else
                    echo -e "${YELLOW}[提示] 未检测到系统路径中的 sing-box 二进制文件。${NC}"
                fi
                systemctl status sing-box --no-pager 2>/dev/null || rc-service sing-box status 2>/dev/null || true
                pause_return
                ;;
            11)
                echo ""
                systemctl restart sing-box 2>/dev/null || rc-service sing-box restart 2>/dev/null || true
                echo -e "${GREEN}[完成] 已发送重启指令，最近运行日志如下：${NC}"
                journalctl -u sing-box -n 30 --no-pager 2>/dev/null || tail -n 30 /etc/sing-box/logs/box.log 2>/dev/null || true
                pause_return
                ;;
            0) return ;;
            *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 模块 3：SSL 证书申请与管理中心 (官方 acme.sh 原生总控 + 自签证书 + acme-yg)
# ==============================================================================
menu_ssl_cert() {
    local cert_dir="/etc/ssl/vps-certs"
    local acme_bin="$HOME/.acme.sh/acme.sh"

    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [3] SSL 证书申请与管理中心 (ACME 官方源 + 自签证书) ===${NC}"
        echo -e " 证书统一输出目录: ${YELLOW}${cert_dir}${NC} (可直接供 Sing-box / FRP / Xray / Nginx 引用)"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e "  ${GREEN}1.${NC} 安装/更新官方 acme.sh 核心     ${CYAN}(官方源 https://get.acme.sh，支持自动续期)${NC}"
        echo -e "  ${GREEN}2.${NC} 切换默认 CA 证书颁发机构       ${CYAN}(Let's Encrypt / ZeroSSL / Google / Buypass)${NC}"
        echo -e "  ${GREEN}3.${NC} 80 端口 HTTP 模式申请域名证书  ${CYAN}(Standalone 模式，自动释放/检测 80 端口)${NC}"
        echo -e "  ${GREEN}4.${NC} Cloudflare DNS API 申请泛域名  ${CYAN}(无需开放 80 端口，支持 *.example.com)${NC}"
        echo -e "  ${GREEN}5.${NC} 生成高强度自签 ECC 伪装证书    ${CYAN}(免域名！专为 Hysteria2 / TUIC 生成 10 年期证书)${NC}"
        echo -e "  ${GREEN}6.${NC} 查看已申请证书列表与到期时间   ${CYAN}(调用 acme.sh --list 并检查证书目录)${NC}"
        echo -e "  ${GREEN}7.${NC} 手动强制续期所有 ACME 证书     ${CYAN}(调用 acme.sh --cron -f)${NC}"
        echo -e "  ${GREEN}8.${NC} 勇哥 (yonggekkk) acme-yg 脚本  ${CYAN}(支持与 sing-box-yg / x-ui-yg 共享证书)${NC}"
        echo -e "  ${GREEN}0.${NC} 返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择证书管理操作 [0-8]: " cert_choice

        case "$cert_choice" in
            1)
                echo ""
                read -rp "请输入用于接收证书到期通知的邮箱 (留空自动生成随机邮箱): " acme_email
                [[ -z "$acme_email" ]] && acme_email="admin@$(hostname -f 2>/dev/null || echo 'vps.local')"
                pkg_install socat cron 2>/dev/null || true
                run_verified_script \
                    "acmesh-official/acme.sh 官方安装器" \
                    "https://github.com/acmesh-official/acme.sh" \
                    "https://get.acme.sh" \
                    "curl https://get.acme.sh | sh -s email=${acme_email}"
                ;;
            2)
                if [[ ! -x "$acme_bin" ]]; then
                    echo -e "${RED}[提示] 请先执行选项 1 安装官方 acme.sh！${NC}"
                    pause_return
                    continue
                fi
                echo ""
                echo "请选择默认 CA 机构:"
                echo "  1) Let's Encrypt (推荐，无需邮箱注册 EAB，最稳定)"
                echo "  2) ZeroSSL"
                echo "  3) Buypass"
                echo "  4) Google Public CA"
                read -rp "请输入编号 [1-4]: " ca_num
                case "$ca_num" in
                    1) "$acme_bin" --set-default-ca --server letsencrypt ;;
                    2) "$acme_bin" --set-default-ca --server zerossl ;;
                    3) "$acme_bin" --set-default-ca --server buypass ;;
                    4) "$acme_bin" --set-default-ca --server google ;;
                    *) echo -e "${RED}无效编号${NC}" ;;
                esac
                pause_return
                ;;
            3)
                if [[ ! -x "$acme_bin" ]]; then
                    echo -e "${YELLOW}[提示] 未检测到 acme.sh，正在为您安装官方 acme.sh...${NC}"
                    pkg_install socat 2>/dev/null || true
                    curl https://get.acme.sh | sh -s email="admin@vps.local"
                fi
                echo ""
                read -rp "请输入已解析到本机 IP 的域名 (如 node.example.com): " domain
                if [[ -z "$domain" ]]; then
                    echo -e "${RED}[错误] 域名不能为空！${NC}"
                    pause_return
                    continue
                fi
                pkg_install socat 2>/dev/null || true
                mkdir -p "$cert_dir/$domain"
                "$acme_bin" --set-default-ca --server letsencrypt
                echo -e "${GREEN}[执行中] 正在通过 80 端口 Standalone 模式申请 ECC 证书...${NC}"
                if "$acme_bin" --issue -d "$domain" --standalone --keylength ec-256 --force; then
                    "$acme_bin" --install-cert -d "$domain" --ecc \
                        --fullchain-file "${cert_dir}/${domain}/fullchain.crt" \
                        --key-file "${cert_dir}/${domain}/private.key"
                    chmod 600 "${cert_dir}/${domain}/private.key"
                    echo -e "${GREEN}[成功] 证书已签发并安装！${NC}"
                    echo -e "  公钥路径 (fullchain): ${YELLOW}${cert_dir}/${domain}/fullchain.crt${NC}"
                    echo -e "  私钥路径 (private)  : ${YELLOW}${cert_dir}/${domain}/private.key${NC}"
                else
                    echo -e "${RED}[失败] 请检查域名是否已正确解析到本机 IP，且 80 端口未被其他程序占用且已在防火墙放行。${NC}"
                fi
                pause_return
                ;;
            4)
                if [[ ! -x "$acme_bin" ]]; then
                    echo -e "${YELLOW}[提示] 未检测到 acme.sh，正在为您安装官方 acme.sh...${NC}"
                    curl https://get.acme.sh | sh -s email="admin@vps.local"
                fi
                echo ""
                read -rp "请输入主域名 (如 example.com，将自动同时申请 example.com 与 *.example.com): " cf_domain
                read -rp "请输入 Cloudflare Global API Key: " cf_key
                read -rp "请输入 Cloudflare 登录邮箱 (CF_Email): " cf_email
                if [[ -z "$cf_domain" || -z "$cf_key" || -z "$cf_email" ]]; then
                    echo -e "${RED}[错误] 域名、API Key 与邮箱均不能为空！${NC}"
                    pause_return
                    continue
                fi
                export CF_Key="$cf_key"
                export CF_Email="$cf_email"
                mkdir -p "$cert_dir/$cf_domain"
                "$acme_bin" --set-default-ca --server letsencrypt
                if "$acme_bin" --issue --dns dns_cf -d "$cf_domain" -d "*.${cf_domain}" --keylength ec-256; then
                    "$acme_bin" --install-cert -d "$cf_domain" --ecc \
                        --fullchain-file "${cert_dir}/${cf_domain}/fullchain.crt" \
                        --key-file "${cert_dir}/${cf_domain}/private.key"
                    chmod 600 "${cert_dir}/${cf_domain}/private.key"
                    echo -e "${GREEN}[成功] 泛域名证书已签发！${NC}"
                    echo -e "  公钥路径: ${YELLOW}${cert_dir}/${cf_domain}/fullchain.crt${NC}"
                    echo -e "  私钥路径: ${YELLOW}${cert_dir}/${cf_domain}/private.key${NC}"
                else
                    echo -e "${RED}[失败] 请检查 Cloudflare API Key 与邮箱是否正确。${NC}"
                fi
                pause_return
                ;;
            5)
                echo ""
                read -rp "请输入伪装域名 (回车默认 www.bing.com): " self_sni
                self_sni="${self_sni:-www.bing.com}"
                mkdir -p "${cert_dir}/self-signed"
                openssl ecparam -genkey -name prime256v1 -out "${cert_dir}/self-signed/private.key"
                openssl req -new -x509 -days 3650 -key "${cert_dir}/self-signed/private.key" \
                    -out "${cert_dir}/self-signed/cert.pem" \
                    -subj "/C=US/ST=California/L=LosAngeles/O=Cloudflare/CN=${self_sni}" \
                    -addext "subjectAltName=DNS:${self_sni}" 2>/dev/null || \
                openssl req -new -x509 -days 3650 -key "${cert_dir}/self-signed/private.key" \
                    -out "${cert_dir}/self-signed/cert.pem" \
                    -subj "/C=US/ST=California/L=LosAngeles/O=Cloudflare/CN=${self_sni}"
                chmod 600 "${cert_dir}/self-signed/private.key"
                local sha256_fp
                sha256_fp="$(openssl x509 -noout -fingerprint -sha256 -in "${cert_dir}/self-signed/cert.pem" 2>/dev/null | cut -d= -f2)"
                echo -e "${GREEN}[成功] 已生成 10 年期 prime256v1 ECC 自签证书 (适用于 Hysteria2 / TUIC)！${NC}"
                echo -e "  证书路径: ${YELLOW}${cert_dir}/self-signed/cert.pem${NC}"
                echo -e "  私钥路径: ${YELLOW}${cert_dir}/self-signed/private.key${NC}"
                echo -e "  SHA-256 指纹 (客户端防中间人校验可用): ${CYAN}${sha256_fp}${NC}"
                pause_return
                ;;
            6)
                echo ""
                if [[ -x "$acme_bin" ]]; then
                    echo -e "${BOLD}--- ACME 已签发证书列表 ---${NC}"
                    "$acme_bin" --list
                else
                    echo -e "${YELLOW}[提示] 尚未安装 acme.sh。${NC}"
                fi
                echo ""
                echo -e "${BOLD}--- 本地证书目录 (${cert_dir}) ---${NC}"
                ls -la "$cert_dir" 2>/dev/null || echo "目录暂无证书"
                pause_return
                ;;
            7)
                if [[ -x "$acme_bin" ]]; then
                    "$acme_bin" --cron -f
                else
                    echo -e "${RED}[提示] 请先安装 acme.sh！${NC}"
                fi
                pause_return
                ;;
            8)
                run_verified_script \
                    "勇哥 (yonggekkk) acme-yg 一键申请证书脚本" \
                    "https://github.com/yonggekkk/acme-yg" \
                    "https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh" \
                    "bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)"
                ;;
            0) return ;;
            *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 模块 4：FRP 内网穿透、Tailscale 异地组网与 Realm/GOST 端口中转中心
# ==============================================================================

download_official_frp_binaries() {
    local arch_raw frp_arch latest_tag ver_num download_url tmp_dir
    arch_raw="$(uname -m)"
    case "$arch_raw" in
        x86_64|amd64) frp_arch="amd64" ;;
        aarch64|arm64) frp_arch="arm64" ;;
        armv7l|armv7) frp_arch="arm" ;;
        riscv64) frp_arch="riscv64" ;;
        *)
            echo -e "${RED}[错误] 暂不支持当前 CPU 架构 (${arch_raw}) 自动下载 FRP。${NC}"
            return 1
            ;;
    esac

    echo -e "${YELLOW}[查询中] 正在从 GitHub 官方 API 获取 fatedier/frp 最新发行版本号...${NC}"
    latest_tag="$(curl -fsSL https://api.github.com/repos/fatedier/frp/releases/latest 2>/dev/null | awk -F'"' '/"tag_name":/ {print $4; exit}')"
    if [[ -z "$latest_tag" ]]; then
        latest_tag="v0.72.0"
        echo -e "${YELLOW}[提示] GitHub API 速率受限，回退使用已知稳定版: ${latest_tag}${NC}"
    else
        echo -e "${GREEN}[检测到官方最新版] fatedier/frp ${latest_tag}${NC}"
    fi
    ver_num="${latest_tag#v}"
    download_url="https://github.com/fatedier/frp/releases/download/${latest_tag}/frp_${ver_num}_linux_${frp_arch}.tar.gz"

    echo -e "${CYAN}官方下载直链: ${download_url}${NC}"
    tmp_dir="$(mktemp -d)"
    if ! curl -fL "$download_url" -o "${tmp_dir}/frp.tar.gz"; then
        echo -e "${RED}[错误] 从 GitHub Releases 下载 FRP 失败，请检查机器与 GitHub 的网络连通性。${NC}"
        rm -rf "$tmp_dir"
        return 1
    fi

    tar -xzf "${tmp_dir}/frp.tar.gz" -C "$tmp_dir"
    local extracted_dir="${tmp_dir}/frp_${ver_num}_linux_${frp_arch}"
    mkdir -p /etc/frp
    cp -f "${extracted_dir}/frps" /usr/local/bin/frps
    cp -f "${extracted_dir}/frpc" /usr/local/bin/frpc
    chmod +x /usr/local/bin/frps /usr/local/bin/frpc
    rm -rf "$tmp_dir"
    echo -e "${GREEN}[成功] 官方原版 frps 与 frpc (${latest_tag}) 已安装至 /usr/local/bin/！${NC}"
    return 0
}

install_official_frps() {
    echo ""
    echo -e "${BOLD}${GREEN}=== 部署官方 fatedier/frp 服务端 (frps) ===${NC}"
    echo -e "开源仓库: ${YELLOW}https://github.com/fatedier/frp${NC}"
    echo ""
    local bind_port dash_port dash_user dash_pwd auth_token vhost_http vhost_https
    read -rp "请输入 frps 监听端口 bindPort [默认 7000]: " bind_port
    bind_port="${bind_port:-7000}"

    read -rp "请输入 Dashboard 面板端口 webServer.port [默认 7500]: " dash_port
    dash_port="${dash_port:-7500}"

    read -rp "请输入 Dashboard 面板账号 [默认 admin]: " dash_user
    dash_user="${dash_user:-admin}"

    local rand_pwd rand_token
    rand_pwd="$(openssl rand -hex 6 2>/dev/null || echo 'frpadmin123')"
    rand_token="$(openssl rand -hex 12 2>/dev/null || echo 'frptoken123456')"

    read -rp "请输入 Dashboard 面板密码 [回车随机生成: ${rand_pwd}]: " dash_pwd
    dash_pwd="${dash_pwd:-$rand_pwd}"

    read -rp "请输入客户端连接鉴权密钥 auth.token [回车随机生成: ${rand_token}]: " auth_token
    auth_token="${auth_token:-$rand_token}"

    read -rp "请输入 HTTP 穿透虚拟主机端口 vhostHTTPPort [默认 8080]: " vhost_http
    vhost_http="${vhost_http:-8080}"

    read -rp "请输入 HTTPS 穿透虚拟主机端口 vhostHTTPSPort [默认 8443]: " vhost_https
    vhost_https="${vhost_https:-8443}"

    if ! download_official_frp_binaries; then
        pause_return
        return
    fi

    cat > /etc/frp/frps.toml << EOF
# Official fatedier/frp Server Configuration (TOML format)
bindAddr = "0.0.0.0"
bindPort = ${bind_port}
quicBindPort = ${bind_port}
vhostHTTPPort = ${vhost_http}
vhostHTTPSPort = ${vhost_https}

auth.method = "token"
auth.token = "${auth_token}"

webServer.addr = "0.0.0.0"
webServer.port = ${dash_port}
webServer.user = "${dash_user}"
webServer.password = "${dash_pwd}"

log.to = "/var/log/frps.log"
log.level = "info"
log.maxDays = 3
EOF
    chmod 600 /etc/frp/frps.toml

    cat > /etc/systemd/system/frps.service << 'EOF'
[Unit]
Description=FRP Server Service (Official fatedier/frp)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.toml
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    for p in "$bind_port" "$dash_port" "$vhost_http" "$vhost_https"; do
        command -v ufw >/dev/null 2>&1 && ufw allow "${p}/tcp" >/dev/null 2>&1 && ufw allow "${p}/udp" >/dev/null 2>&1 || true
        command -v iptables >/dev/null 2>&1 && iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || true
    done

    systemctl daemon-reload
    systemctl enable --now frps
    local pub_ip
    pub_ip="$(curl -s4m 4 https://ipinfo.io/ip 2>/dev/null || echo '<你的服务器公网IP>')"

    echo ""
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${GREEN}${BOLD}🎉 官方 FRPS 服务端部署完成并已启动！${NC}"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e " ${BOLD}服务器地址 (serverAddr):${NC} ${GREEN}${pub_ip}${NC}"
    echo -e " ${BOLD}服务端端口 (serverPort):${NC} ${GREEN}${bind_port}${NC} (TCP & QUIC)"
    echo -e " ${BOLD}鉴权密钥   (auth.token):${NC} ${YELLOW}${auth_token}${NC}"
    echo -e " ${BOLD}HTTP/HTTPS 穿透端口   :${NC} ${vhost_http} / ${vhost_https}"
    echo -e " ${BOLD}Web 监控面板地址      :${NC} ${BLUE}http://${pub_ip}:${dash_port}${NC}"
    echo -e " ${BOLD}Web 面板账号 / 密码   :${NC} ${GREEN}${dash_user}${NC} / ${YELLOW}${dash_pwd}${NC}"
    echo -e " ${BOLD}配置文件路径          :${NC} /etc/frp/frps.toml"
    echo -e "${CYAN}======================================================================${NC}"
    pause_return
}

install_official_frpc() {
    echo ""
    echo -e "${BOLD}${GREEN}=== 部署官方 fatedier/frp 客户端 (frpc) ===${NC}"
    echo -e "开源仓库: ${YELLOW}https://github.com/fatedier/frp${NC}"
    echo ""
    local srv_addr srv_port auth_token proxy_name proxy_type local_ip local_port remote_port
    read -rp "请输入远端 frps 服务端公网 IP 或域名 (serverAddr): " srv_addr
    if [[ -z "$srv_addr" ]]; then
        echo -e "${RED}[错误] 服务端地址不能为空！${NC}"
        pause_return
        return
    fi
    read -rp "请输入远端 frps 服务端端口 (serverPort) [默认 7000]: " srv_port
    srv_port="${srv_port:-7000}"

    read -rp "请输入远端 frps 鉴权密钥 (auth.token): " auth_token
    read -rp "请输入首条穿透规则名称 [默认 ssh-tunnel]: " proxy_name
    proxy_name="${proxy_name:-ssh-tunnel}"

    read -rp "请输入穿透协议类型 (tcp / udp) [默认 tcp]: " proxy_type
    proxy_type="${proxy_type:-tcp}"

    read -rp "请输入要暴露的本地 IP [默认 127.0.0.1]: " local_ip
    local_ip="${local_ip:-127.0.0.1}"

    read -rp "请输入要暴露的本地端口 (localPort) [默认 22]: " local_port
    local_port="${local_port:-22}"

    read -rp "请输入在服务端监听的远程端口 (remotePort) [默认 6000]: " remote_port
    remote_port="${remote_port:-6000}"

    if ! download_official_frp_binaries; then
        pause_return
        return
    fi

    cat > /etc/frp/frpc.toml << EOF
# Official fatedier/frp Client Configuration (TOML format)
serverAddr = "${srv_addr}"
serverPort = ${srv_port}

auth.method = "token"
auth.token = "${auth_token}"

log.to = "/var/log/frpc.log"
log.level = "info"
log.maxDays = 3

[[proxies]]
name = "${proxy_name}"
type = "${proxy_type}"
localIP = "${local_ip}"
localPort = ${local_port}
remotePort = ${remote_port}
EOF
    chmod 600 /etc/frp/frpc.toml

    cat > /etc/systemd/system/frpc.service << 'EOF'
[Unit]
Description=FRP Client Service (Official fatedier/frp)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/frpc -c /etc/frp/frpc.toml
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now frpc
    echo ""
    echo -e "${GREEN}[成功] 官方 FRPC 客户端已启动并设置开机自启！${NC}"
    echo -e "配置文件路径: ${YELLOW}/etc/frp/frpc.toml${NC} (如需添加更多穿透规则，编辑该文件后重启 frpc 即可)"
    systemctl status frpc --no-pager 2>/dev/null || true
    pause_return
}

menu_frp_relay() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [4] FRP 内网穿透、Tailscale 组网与 Realm/GOST 端口中转 ===${NC}"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e " ${BOLD}${YELLOW}【A. 官方原版 fatedier/frp 原生直连部署与管理 (85k+ Star 官方 Release)】${NC}"
        echo -e "  ${GREEN}1.${NC} [官方原生] 一键安装并配置 ${BOLD}FRPS 服务端${NC} ${CYAN}(自动拉取最新 Release + 生成 frps.toml + Dashboard)${NC}"
        echo -e "  ${GREEN}2.${NC} [官方原生] 一键安装并配置 ${BOLD}FRPC 客户端${NC} ${CYAN}(自动拉取最新 Release + 生成 frpc.toml + 守护进程)${NC}"
        echo -e "  ${GREEN}3.${NC} [官方原生] 查看 FRPS / FRPC 运行状态、配置信息与实时日志"
        echo -e "  ${GREEN}4.${NC} [官方原生] 在线编辑 `/etc/frp/frps.toml` 或 `frpc.toml` 并重启生效"
        echo -e "  ${GREEN}5.${NC} [官方原生] 一键升级 FRPS / FRPC 二进制内核至官方最新版 (保留原配置)"
        echo -e "  ${GREEN}6.${NC} [官方原生] 卸载本机 FRPS / FRPC 服务与配置"
        echo ""
        echo -e " ${BOLD}${YELLOW}【B. 异地组网 (Tailscale) 与端口中转 (Realm/GOST/MvsCode)】${NC}"
        echo -e "  ${GREEN}7.${NC} MvsCode Frps 一键安装管理脚本 ${CYAN}(GitHub 高 Star 经典 frps-onekey 脚本)${NC}"
        echo -e "  ${GREEN}8.${NC} Realm 全功能一键端口中转脚本  ${CYAN}(zywe03/realm-xwPF 终端可视化 TCP/UDP 中转/故障转移)${NC}"
        echo -e "  ${GREEN}9.${NC} GOST v3 官方一键安装脚本      ${CYAN}(go-gost/gost 官方加密隧道与多级中转核心)${NC}"
        echo -e "  ${GREEN}10.${NC} Tailscale 官方一键组网脚本   ${CYAN}(tailscale.com 官方源：VPS 与家里 NAS 零配置组网)${NC}"
        echo -e "  ${GREEN}0.${NC} 返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择穿透、组网或中转操作 [0-10]: " frp_choice

        case "$frp_choice" in
            1) install_official_frps ;;
            2) install_official_frpc ;;
            3)
                echo ""
                echo -e "${BOLD}--- FRPS 服务端状态 ---${NC}"
                systemctl status frps --no-pager 2>/dev/null || echo "frps 未运行"
                [[ -f /etc/frp/frps.toml ]] && echo -e "\n${YELLOW}[/etc/frp/frps.toml 内容]:${NC}" && cat /etc/frp/frps.toml
                echo ""
                echo -e "${BOLD}--- FRPC 客户端状态 ---${NC}"
                systemctl status frpc --no-pager 2>/dev/null || echo "frpc 未运行"
                [[ -f /etc/frp/frpc.toml ]] && echo -e "\n${YELLOW}[/etc/frp/frpc.toml 内容]:${NC}" && cat /etc/frp/frpc.toml
                pause_return
                ;;
            4)
                echo ""
                echo "1) 编辑 /etc/frp/frps.toml 并重启 frps"
                echo "2) 编辑 /etc/frp/frpc.toml 并重启 frpc"
                read -rp "请选择 [1-2]: " edit_num
                local editor="${EDITOR:-vi}"
                command -v nano >/dev/null 2>&1 && editor="nano"
                if [[ "$edit_num" == "1" && -f /etc/frp/frps.toml ]]; then
                    "$editor" /etc/frp/frps.toml
                    systemctl restart frps
                    echo -e "${GREEN}[已重启 frps]${NC}"
                elif [[ "$edit_num" == "2" && -f /etc/frp/frpc.toml ]]; then
                    "$editor" /etc/frp/frpc.toml
                    systemctl restart frpc
                    echo -e "${GREEN}[已重启 frpc]${NC}"
                else
                    echo -e "${RED}[提示] 对应配置文件不存在，请先安装！${NC}"
                fi
                pause_return
                ;;
            5)
                echo ""
                if download_official_frp_binaries; then
                    systemctl is-active --quiet frps && systemctl restart frps && echo -e "${GREEN}[已重启 frps 服务]${NC}"
                    systemctl is-active --quiet frpc && systemctl restart frpc && echo -e "${GREEN}[已重启 frpc 服务]${NC}"
                fi
                pause_return
                ;;
            6)
                echo ""
                read -rp "确认卸载本机 FRPS 与 FRPC 服务及 /etc/frp 配置吗？[y/N]: " del_frp
                if [[ "$del_frp" =~ ^[Yy]$ ]]; then
                    systemctl disable --now frps 2>/dev/null || true
                    systemctl disable --now frpc 2>/dev/null || true
                    rm -f /etc/systemd/system/frps.service /etc/systemd/system/frpc.service
                    rm -f /usr/local/bin/frps /usr/local/bin/frpc
                    rm -rf /etc/frp
                    systemctl daemon-reload
                    echo -e "${GREEN}[完成] 已彻底卸载 FRP 服务与配置文件。${NC}"
                fi
                pause_return
                ;;
            7)
                run_verified_script \
                    "MvsCode/frps-onekey 服务端一键配置脚本" \
                    "https://github.com/MvsCode/frps-onekey" \
                    "https://raw.githubusercontent.com/mvscode/frps-onekey/master/install-frps.sh" \
                    "wget https://raw.githubusercontent.com/mvscode/frps-onekey/master/install-frps.sh -O ./install-frps.sh && chmod 700 ./install-frps.sh && ./install-frps.sh install"
                ;;
            8)
                run_verified_script \
                    "zywe03 Realm 全功能一键中转脚本 (安装后输入 xwPF 管理)" \
                    "https://github.com/zywe03/realm-xwPF" \
                    "https://raw.githubusercontent.com/zywe03/realm-xwPF/main/xwPF.sh" \
                    "wget -qO- https://raw.githubusercontent.com/zywe03/realm-xwPF/main/xwPF.sh | bash -s install"
                ;;
            9)
                run_verified_script \
                    "go-gost/gost 官方 GOST v3 隧道工具一键安装" \
                    "https://github.com/go-gost/gost" \
                    "https://raw.githubusercontent.com/go-gost/gost/master/install.sh" \
                    "bash <(curl -fsSL https://raw.githubusercontent.com/go-gost/gost/master/install.sh)"
                ;;
            10)
                run_verified_script \
                    "Tailscale 官方 Linux 一键安装脚本 (安装后运行 tailscale up 登录)" \
                    "https://github.com/tailscale/tailscale" \
                    "https://tailscale.com/install.sh" \
                    "curl -fsSL https://tailscale.com/install.sh | sh"
                ;;
            0) return ;;
            *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 模块 5：Caddy / Nginx Proxy Manager 反代建站、节点面板与 Sub-Store
# ==============================================================================

install_and_config_caddy() {
    echo ""
    echo -e "${BOLD}${GREEN}=== Caddy v2 官方自动 HTTPS 反代服务器安装与配置 ===${NC}"
    echo -e "官方仓库: ${YELLOW}https://github.com/caddyserver/caddy${NC}"
    if ! command -v caddy >/dev/null 2>&1; then
        echo -e "${YELLOW}[安装中] 正在为您安装官方 Caddy v2...${NC}"
        local pm
        pm="$(detect_pkg_manager)"
        if [[ "$pm" == "apt" ]]; then
            apt-get update -y
            apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes 2>/dev/null || true
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
            apt-get update -y && apt-get install -y caddy
        elif [[ "$pm" == "dnf" || "$pm" == "yum" ]]; then
            pkg_install 'dnf-command(copr)' 2>/dev/null || true
            dnf copr enable -y @caddy/caddy 2>/dev/null || true
            pkg_install caddy
        elif [[ "$pm" == "apk" ]]; then
            apk add --no-cache caddy
        fi
    fi

    echo ""
    echo "1) 一键添加域名反向代理站点 (自动申请并续期 HTTPS 证书)"
    echo "2) 手动编辑 /etc/caddy/Caddyfile 并热重载"
    echo "3) 查看 Caddy 运行状态"
    echo "0) 返回上级菜单"
    read -rp "请选择 Caddy 操作 [0-3]: " cd_opt
    case "$cd_opt" in
        1)
            read -rp "请输入已解析到本机的域名 (如 panel.example.com): " cd_domain
            read -rp "请输入本机或内网反代目标地址 (如 127.0.0.1:3001 或 127.0.0.1:8080): " cd_target
            if [[ -n "$cd_domain" && -n "$cd_target" ]]; then
                mkdir -p /etc/caddy
                cat >> /etc/caddy/Caddyfile << EOF

${cd_domain} {
    encode gzip zstd
    reverse_proxy ${cd_target}
}
EOF
                systemctl enable --now caddy 2>/dev/null || true
                systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null || true
                echo -e "${GREEN}[成功] 已将 https://${cd_domain} 反代至 ${cd_target}，Caddy 将自动完成 SSL 证书签发！${NC}"
            fi
            ;;
        2)
            local editor="${EDITOR:-vi}"
            command -v nano >/dev/null 2>&1 && editor="nano"
            mkdir -p /etc/caddy
            "$editor" /etc/caddy/Caddyfile
            systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null || true
            echo -e "${GREEN}[已重载 Caddy 配置]${NC}"
            ;;
        3)
            systemctl status caddy --no-pager 2>/dev/null || true
            ;;
        *) return ;;
    esac
    pause_return
}

deploy_official_npm() {
    echo ""
    echo -e "${BOLD}${GREEN}=== 部署官方 Nginx Proxy Manager (NPM) 可视化反代建站面板 ===${NC}"
    echo -e "官方仓库: ${YELLOW}https://github.com/NginxProxyManager/nginx-proxy-manager${NC}"
    echo -e "官方镜像: ${BLUE}jc21/nginx-proxy-manager:latest${NC}"
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}[提示] 检测到尚未安装 Docker，正在先调用官方 get.docker.com 安装 Docker...${NC}"
        curl -fsSL https://get.docker.com | sh && systemctl enable --now docker 2>/dev/null || true
    fi
    read -rp "请输入 NPM 后台管理 Web 端口 [默认 81]: " npm_admin_port
    npm_admin_port="${npm_admin_port:-81}"

    mkdir -p /opt/npm/data /opt/npm/letsencrypt
    docker rm -f npm 2>/dev/null || true
    docker run -d \
        --name npm \
        --restart=always \
        -p 80:80 \
        -p "${npm_admin_port}:81" \
        -p 443:443 \
        -v /opt/npm/data:/data \
        -v /opt/npm/letsencrypt:/etc/letsencrypt \
        jc21/nginx-proxy-manager:latest

    local pub_ip
    pub_ip="$(curl -s4m 4 https://ipinfo.io/ip 2>/dev/null || echo '<你的服务器IP>')"
    echo ""
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${GREEN}${BOLD}🎉 官方 Nginx Proxy Manager (NPM) 部署成功！${NC}"
    echo -e " ${BOLD}后台管理地址:${NC} ${BLUE}http://${pub_ip}:${npm_admin_port}${NC}"
    echo -e " ${BOLD}初始管理员邮箱:${NC} ${GREEN}admin@example.com${NC}"
    echo -e " ${BOLD}初始管理员密码:${NC} ${YELLOW}changeme${NC} (首次登录后请立即修改)"
    echo -e " ${BOLD}数据持久化目录:${NC} /opt/npm/"
    echo -e "${CYAN}======================================================================${NC}"
    pause_return
}

menu_panels() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [5] 反代建站 (Caddy/NPM)、节点面板、探针与 Sub-Store ===${NC}"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e " ${BOLD}${YELLOW}【A. 反代建站与伪装站点神器 (配合 Sing-box Reality 回落或面板套域名)】${NC}"
        echo -e "  ${GREEN}1.${NC} Caddy v2 官方自动 HTTPS 反代建站  ${CYAN}(caddyserver/caddy 官方源 + 一键添加域名反代向导)${NC}"
        echo -e "  ${GREEN}2.${NC} Nginx Proxy Manager (NPM) 面板   ${CYAN}(NginxProxyManager 官方镜像：可视化反代 + 自动续签 SSL)${NC}"
        echo -e "  ${GREEN}3.${NC} 1Panel 现代化 Linux 运维建站面板  ${CYAN}(37k+ Star 开源容器/WordPress建站/防火墙/文件管理)${NC}"
        echo ""
        echo -e " ${BOLD}${YELLOW}【B. 可视化节点面板、订阅转换与服务器探针】${NC}"
        echo -e "  ${GREEN}4.${NC} S-UI 官方 Web 面板 (alireza0)    ${CYAN}(专为 SagerNet/Sing-box 打造的高级可视化面板)${NC}"
        echo -e "  ${GREEN}5.${NC} 3X-UI 官方 Web 面板 (MHSanaei)   ${CYAN}(30k+ Star 最流行面板，支持多协议多用户流量统计)${NC}"
        echo -e "  ${GREEN}6.${NC} 勇哥 X-UI-YG 精简修改版          ${CYAN}(支持 Hy2/Xhttp/Argo双隧道/Sing-box与Clash订阅)${NC}"
        echo -e "  ${GREEN}7.${NC} Sub-Store 官方 Docker 一键部署   ${CYAN}(sub-store-org 官方镜像：Sing-box/Clash 订阅聚合神器)${NC}"
        echo -e "  ${GREEN}8.${NC} 哪吒监控/探针 (Nezha 官方脚本)   ${CYAN}(nezhahq/nezha 官方 Dashboard 与 Agent 管理)${NC}"
        echo -e "  ${GREEN}0.${NC} 返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择要安装的反代、面板或应用 [0-8]: " panel_choice

        case "$panel_choice" in
            1) install_and_config_caddy ;;
            2) deploy_official_npm ;;
            3)
                run_verified_script \
                    "1Panel 现代化 Linux 运维管理面板 (官方 V2 在线安装脚本)" \
                    "https://github.com/1Panel-dev/1Panel" \
                    "https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh" \
                    "bash -c \"\$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)\""
                ;;
            4)
                run_verified_script \
                    "S-UI 官方 Sing-box 可视化面板 (alireza0)" \
                    "https://github.com/alireza0/s-ui" \
                    "https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh" \
                    "bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)"
                ;;
            5)
                run_verified_script \
                    "3X-UI 官方可视化面板 (MHSanaei)" \
                    "https://github.com/MHSanaei/3x-ui" \
                    "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh" \
                    "bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)"
                ;;
            6)
                run_verified_script \
                    "勇哥 (yonggekkk) X-UI-YG 精简修改版面板" \
                    "https://github.com/yonggekkk/x-ui-yg" \
                    "https://raw.githubusercontent.com/yonggekkk/x-ui-yg/main/install.sh" \
                    "bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/x-ui-yg/main/install.sh)"
                ;;
            7)
                echo ""
                if ! command -v docker >/dev/null 2>&1; then
                    echo -e "${RED}[提示] 请先在主菜单 [7] 安装 Docker 环境！${NC}"
                    pause_return
                    continue
                fi
                local sub_secret
                sub_secret="$(openssl rand -hex 12 2>/dev/null || echo 'substoresecret888')"
                read -rp "请输入 Sub-Store Web 监听端口 [默认 3001]: " sub_port
                sub_port="${sub_port:-3001}"
                run_verified_script \
                    "sub-store-org/Sub-Store 官方 Docker 容器一键部署" \
                    "https://github.com/sub-store-org/Sub-Store" \
                    "https://hub.docker.com/r/xream/sub-store" \
                    "mkdir -p /root/sub-store-data && docker rm -f sub-store 2>/dev/null || true && docker run -itd --restart=always -e SUB_STORE_FRONTEND_BACKEND_PATH=/${sub_secret} -p ${sub_port}:3001 -v /root/sub-store-data:/opt/app/data --name sub-store xream/sub-store && echo -e '\n[部署成功] 专属安全订阅管理入口: http://<服务器IP>:${sub_port}?api=http://<服务器IP>:${sub_port}/${sub_secret}'"
                ;;
            8)
                run_verified_script \
                    "哪吒监控 (Nezha Monitoring 官方安装脚本)" \
                    "https://github.com/nezhahq/nezha" \
                    "https://raw.githubusercontent.com/nezhahq/scripts/main/install.sh" \
                    "curl -L https://raw.githubusercontent.com/nezhahq/scripts/main/install.sh -o nezha.sh && chmod +x nezha.sh && ./nezha.sh"
                ;;
            0) return ;;
            *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 模块 6：Cloudflare WARP 全家桶、Cloudflare 优选 IP 测速 (XIU2) 与 BBR 加速
# ==============================================================================
enable_native_bbr_pro() {
    echo ""
    echo -e "${GREEN}[原生加速] 正在开启 Linux 内核 TCP BBR + FQ 并优化高并发网络参数...${NC}"
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null || true
    cat >> /etc/sysctl.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv4.tcp_fastopen = 3
EOF
    sysctl -p >/dev/null 2>&1 || true
    echo -e "${GREEN}[完成] 当前拥塞算法: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) | 队列: $(sysctl -n net.core.default_qdisc 2>/dev/null)${NC}"
    pause_return
}

toggle_ipv4_ipv6_priority() {
    echo ""
    echo "1) 设置 IPv4 优先出站 (取消 /etc/gai.conf 中 precedence ::ffff:0:0/96 100 注释)"
    echo "2) 恢复 IPv6 默认优先级"
    read -rp "请选择 [1-2]: " prio
    if [[ "$prio" == "1" ]]; then
        if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
            echo -e "${GREEN}[提示] 当前已是 IPv4 优先。${NC}"
        else
            echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
            echo -e "${GREEN}[成功] 已切换为 IPv4 优先出站！${NC}"
        fi
    elif [[ "$prio" == "2" ]]; then
        sed -i '/^precedence ::ffff:0:0\/96  100/d' /etc/gai.conf 2>/dev/null || true
        echo -e "${GREEN}[成功] 已恢复系统默认 IPv6 优先级！${NC}"
    fi
    echo -e "当前默认出站 IP 检测: $(curl -sm 4 https://ip.sb 2>/dev/null || echo '未知')"
    pause_return
}

run_xiu2_cfst() {
    echo ""
    echo -e "${BOLD}${GREEN}=== XIU2/CloudflareSpeedTest 官方 Cloudflare 优选 IP 测速 ===${NC}"
    echo -e "开源仓库: ${YELLOW}https://github.com/XIU2/CloudflareSpeedTest${NC}"
    local arch_raw cfst_arch latest_tag dl_url
    arch_raw="$(uname -m)"
    case "$arch_raw" in
        x86_64|amd64) cfst_arch="amd64" ;;
        aarch64|arm64) cfst_arch="arm64" ;;
        armv7l|armv7) cfst_arch="armv7" ;;
        *)
            echo -e "${RED}[错误] 暂不支持当前架构 (${arch_raw})。${NC}"
            pause_return
            return
            ;;
    esac

    latest_tag="$(curl -fsSL https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest 2>/dev/null | awk -F'"' '/"tag_name":/ {print $4; exit}')"
    [[ -z "$latest_tag" ]] && latest_tag="v2.3.4"
    dl_url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/${latest_tag}/CloudflareST_linux_${cfst_arch}.tar.gz"

    run_verified_script \
        "XIU2/CloudflareSpeedTest (${latest_tag}) 官方优选 IP 测速" \
        "https://github.com/XIU2/CloudflareSpeedTest" \
        "$dl_url" \
        "mkdir -p /opt/cfst && cd /opt/cfst && curl -fL '${dl_url}' -o cfst.tar.gz && tar -xzf cfst.tar.gz && chmod +x CloudflareST && ./CloudflareST -p 10"
}

menu_network() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [6] Cloudflare WARP 三剑客、CF 优选 IP 测速与 BBR 加速 ===${NC}"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e " ${BOLD}${YELLOW}【A. Cloudflare WARP 双栈 / SOCKS5 / 解锁分流 & 优选 IP】${NC}"
        echo -e "  ${GREEN}1.${NC} F佬 (fscarmen) WARP 官方脚本     ${CYAN}(最全面：支持 WGCF/WARP-GO/双栈/SOCKS5/链式分流，快捷键 warp)${NC}"
        echo -e "  ${GREEN}2.${NC} 勇哥 (yonggekkk) WARP-YG 脚本    ${CYAN}(支持 WARP+ 升级、无限生成 WireGuard 配置与解锁检测)${NC}"
        echo -e "  ${GREEN}3.${NC} P3TERX WARP 极简安装脚本         ${CYAN}(P3TERX/warp.sh 高 Star 经典非全局网卡/SOCKS5 脚本)${NC}"
        echo -e "  ${GREEN}4.${NC} XIU2 Cloudflare 优选 IP 测速     ${CYAN}(XIU2/CloudflareSpeedTest 20k+ Star 官方原版优选测速)${NC}"
        echo -e "  ${GREEN}5.${NC} [本地] 检测当前 VPS 的 Cloudflare WARP 生效状态与双栈出口 IP"
        echo ""
        echo -e " ${BOLD}${YELLOW}【B. TCP BBR 拥塞控制加速与双栈优先级】${NC}"
        echo -e "  ${GREEN}6.${NC} [原生] 一键开启 BBR + FQ + TCP FastOpen ${CYAN}(零外部脚本，Linux 内核原生直接生效)${NC}"
        echo -e "  ${GREEN}7.${NC} 秋水逸冰 (teddysun) BBR 一键脚本        ${CYAN}(经典高 Star 官方 BBR 脚本)${NC}"
        echo -e "  ${GREEN}8.${NC} [原生] 切换 IPv4 / IPv6 出站优先级       ${CYAN}(修改 /etc/gai.conf，无需重启服务器)${NC}"
        echo -e "  ${GREEN}0.${NC} 返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择 WARP、优选 IP 或网络加速工具 [0-8]: " net_choice

        case "$net_choice" in
            1)
                run_verified_script \
                    "F佬 (fscarmen) Cloudflare WARP 一键脚本 (安装后输入 warp 管理)" \
                    "https://github.com/fscarmen/warp-sh (主仓: https://gitlab.com/fscarmen/warp)" \
                    "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh" \
                    "wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh"
                ;;
            2)
                run_verified_script \
                    "勇哥 (yonggekkk) WARP-YG 多功能一键脚本" \
                    "https://github.com/yonggekkk/warp-yg" \
                    "https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh" \
                    "bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh)"
                ;;
            3)
                run_verified_script \
                    "P3TERX Cloudflare WARP 一键安装脚本" \
                    "https://github.com/P3TERX/warp.sh" \
                    "https://raw.githubusercontent.com/P3TERX/warp.sh/main/warp.sh" \
                    "bash <(curl -fsSL https://raw.githubusercontent.com/P3TERX/warp.sh/main/warp.sh) menu"
                ;;
            4) run_xiu2_cfst ;;
            5)
                echo ""
                echo -e "${BOLD}--- Cloudflare IPv4 Trace 状态 ---${NC}"
                curl -s4m 5 https://www.cloudflare.com/cdn-cgi/trace | grep -E "ip=|warp=|loc=|colo=" || echo "无 IPv4 连通"
                echo ""
                echo -e "${BOLD}--- Cloudflare IPv6 Trace 状态 ---${NC}"
                curl -s6m 5 https://www.cloudflare.com/cdn-cgi/trace | grep -E "ip=|warp=|loc=|colo=" || echo "无 IPv6 连通"
                echo ""
                echo -e "${BOLD}--- 本机 SOCKS5 (127.0.0.1:40000) WARP 端口检测 ---${NC}"
                curl -sx socks5h://127.0.0.1:40000 -m 4 https://www.cloudflare.com/cdn-cgi/trace | grep -E "ip=|warp=|loc=" || echo "未开启本地 40000 端口 WARP SOCKS5"
                pause_return
                ;;
            6) enable_native_bbr_pro ;;
            7)
                run_verified_script \
                    "秋水逸冰 (teddysun) BBR 一键安装脚本" \
                    "https://github.com/teddysun/across" \
                    "https://raw.githubusercontent.com/teddysun/across/master/bbr.sh" \
                    "wget --no-check-certificate -O bbr.sh https://raw.githubusercontent.com/teddysun/across/master/bbr.sh && chmod +x bbr.sh && ./bbr.sh"
                ;;
            8) toggle_ipv4_ipv6_priority ;;
            0) return ;;
            *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 模块 7：Docker 容器管理、常用自托管应用与母鸡开 NAT 小鸡
# ==============================================================================
menu_docker_nat() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [7] Docker 容器管理、热门应用与一键母鸡开 NAT 小鸡 ===${NC}"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e "  ${GREEN}1.${NC} Docker 官方一键安装脚本             ${CYAN}(get.docker.com 官方纯净通道，适合海外机)${NC}"
        echo -e "  ${GREEN}2.${NC} LinuxMirrors Docker 安装与换源脚本  ${CYAN}(SuperManito 开源，支持国内外镜像加速源选择)${NC}"
        echo -e "  ${GREEN}3.${NC} [本地] 查看所有运行中容器与资源占用 ${CYAN}(docker ps -a & docker stats --no-stream)${NC}"
        echo -e "  ${GREEN}4.${NC} [本地] 一键清理无用容器、镜像与缓存 ${CYAN}(docker system prune -af --volumes)${NC}"
        echo -e "  ${GREEN}5.${NC} 一键母鸡开 NAT 小鸡 (Incus 虚拟化)  ${CYAN}(oneclickvirt/incus 官方开源：切分 NAT 容器小鸡)${NC}"
        echo -e "  ${GREEN}6.${NC} 一键母鸡开 Docker NAT 小鸡          ${CYAN}(oneclickvirt/docker 官方开源：轻量容器小鸡)${NC}"
        echo -e "  ${GREEN}7.${NC} Aria2 Pro 官方一键安装脚本          ${CYAN}(P3TERX/aria2.sh 高 Star 离线下载神器)${NC}"
        echo -e "  ${GREEN}8.${NC} AList 官方一键安装脚本              ${CYAN}(AlistGo/alist 官方多网盘挂载程序)${NC}"
        echo -e "  ${GREEN}0.${NC} 返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择容器/虚拟化操作 [0-8]: " dk_choice

        case "$dk_choice" in
            1)
                run_verified_script \
                    "Docker 官方一键安装脚本" \
                    "https://github.com/docker/docker-install" \
                    "https://get.docker.com" \
                    "curl -fsSL https://get.docker.com | sh && systemctl enable --now docker 2>/dev/null || true"
                ;;
            2)
                run_verified_script \
                    "SuperManito LinuxMirrors Docker 安装与镜像加速配置" \
                    "https://github.com/SuperManito/LinuxMirrors" \
                    "https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/DockerInstallation.sh" \
                    "bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/DockerInstallation.sh)"
                ;;
            3)
                echo ""
                if command -v docker >/dev/null 2>&1; then
                    docker ps -a
                    echo ""
                    docker stats --no-stream
                else
                    echo -e "${RED}[提示] 当前尚未安装 Docker。${NC}"
                fi
                pause_return
                ;;
            4)
                echo ""
                if command -v docker >/dev/null 2>&1; then
                    docker system prune -af
                    echo -e "${GREEN}[完成] 已清理无用 Docker 镜像与停止的容器。${NC}"
                else
                    echo -e "${RED}[提示] 当前尚未安装 Docker。${NC}"
                fi
                pause_return
                ;;
            5)
                run_verified_script \
                    "oneclickvirt/incus 母鸡一键安装 Incus 开 NAT 小鸡" \
                    "https://github.com/oneclickvirt/incus" \
                    "https://raw.githubusercontent.com/oneclickvirt/incus/main/scripts/incus_install.sh" \
                    "curl -L https://raw.githubusercontent.com/oneclickvirt/incus/main/scripts/incus_install.sh -o incus_install.sh && chmod +x incus_install.sh && bash incus_install.sh"
                ;;
            6)
                run_verified_script \
                    "oneclickvirt/docker 母鸡一键批量开设 Docker NAT 小鸡" \
                    "https://github.com/oneclickvirt/docker" \
                    "https://raw.githubusercontent.com/oneclickvirt/docker/main/scripts/dockerinstall.sh" \
                    "curl -L https://raw.githubusercontent.com/oneclickvirt/docker/main/scripts/dockerinstall.sh -o dockerinstall.sh && chmod +x dockerinstall.sh && bash dockerinstall.sh"
                ;;
            7)
                run_verified_script \
                    "P3TERX Aria2 Pro 一键安装管理脚本" \
                    "https://github.com/P3TERX/aria2.sh" \
                    "https://raw.githubusercontent.com/P3TERX/aria2.sh/master/aria2.sh" \
                    "wget -N https://raw.githubusercontent.com/P3TERX/aria2.sh/master/aria2.sh && chmod +x aria2.sh && ./aria2.sh"
                ;;
            8)
                run_verified_script \
                    "AlistGo/alist 官方一键安装脚本" \
                    "https://github.com/AlistGo/alist" \
                    "https://raw.githubusercontent.com/AlistGo/alist/main/install.sh" \
                    "curl -fsSL https://raw.githubusercontent.com/AlistGo/alist/main/install.sh | bash -s install"
                ;;
            0) return ;;
            *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 模块 8：系统工具、安全加固、换源与一键 DD 重装系统
# ==============================================================================
manage_swap() {
    echo ""
    echo -e "${CYAN}=== 原生虚拟内存 (Swap) 管理 ===${NC}"
    free -h
    echo ""
    echo "1) 创建/扩容 1GB Swap (/swapfile)"
    echo "2) 创建/扩容 2GB Swap (/swapfile)"
    echo "3) 自定义大小 (单位 MB)"
    echo "4) 卸载并删除 /swapfile"
    echo "0) 返回上级菜单"
    read -rp "请选择操作 [0-4]: " swap_choice

    local size_mb=0
    case "$swap_choice" in
        1) size_mb=1024 ;;
        2) size_mb=2048 ;;
        3) read -rp "请输入 Swap 大小 (MB，如 4096): " size_mb ;;
        4)
            swapoff /swapfile 2>/dev/null || true
            rm -f /swapfile
            sed -i '\|/swapfile|d' /etc/fstab 2>/dev/null || true
            echo -e "${GREEN}[完成] 已移除 /swapfile。${NC}"
            free -h
            pause_return
            return
            ;;
        *) return ;;
    esac

    if [[ "$size_mb" =~ ^[0-9]+$ ]] && [[ "$size_mb" -gt 64 ]]; then
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
        echo -e "${YELLOW}[执行中] 正在分配 ${size_mb}MB 虚拟内存...${NC}"
        dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        fi
        echo -e "${GREEN}[完成] Swap 创建成功！${NC}"
        free -h
    else
        echo -e "${RED}[错误] 请输入合法的数值！${NC}"
    fi
    pause_return
}

change_ssh_port() {
    echo ""
    local current_port
    current_port="$(awk '/^Port / {print $2}' /etc/ssh/sshd_config 2>/dev/null || echo '22')"
    echo -e "当前 SSH 端口配置: ${GREEN}${current_port:-22}${NC}"
    read -rp "请输入新的 SSH 端口号 [1024-65535] (留空取消): " new_port
    if [[ -z "$new_port" ]]; then
        return
    fi
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 22 || "$new_port" -gt 65535 ]]; then
        echo -e "${RED}[错误] 端口号必须在 22 到 65535 之间！${NC}"
        pause_return
        return
    fi
    cp -f /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"
    if grep -q "^#*Port " /etc/ssh/sshd_config; then
        sed -i "s/^#*Port .*/Port ${new_port}/" /etc/ssh/sshd_config
    else
        echo "Port ${new_port}" >> /etc/ssh/sshd_config
    fi
    command -v ufw >/dev/null 2>&1 && ufw allow "${new_port}/tcp" >/dev/null 2>&1 || true
    command -v iptables >/dev/null 2>&1 && iptables -I INPUT -p tcp --dport "$new_port" -j ACCEPT 2>/dev/null || true
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null || true
    echo -e "${GREEN}[成功] SSH 端口已修改为 ${new_port}，并已在本地防火墙放行！${NC}"
    echo -e "${YELLOW}[重要提醒] 请勿立即关闭当前 SSH 窗口！请先在云厂商安全组放行 ${new_port} 端口，并新建连接测试成功后再退出。${NC}"
    pause_return
}

install_fail2ban() {
    echo ""
    echo -e "${GREEN}[安全防护] 正在安装并配置 Fail2ban SSH 防暴力破解...${NC}"
    pkg_install fail2ban
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 5

[sshd]
enabled = true
mode = normal
EOF
    systemctl enable --now fail2ban 2>/dev/null || service fail2ban restart 2>/dev/null || true
    echo -e "${GREEN}[完成] Fail2ban 已启动！连续输错 5 次密码将自动封禁攻击 IP 24 小时。${NC}"
    fail2ban-client status sshd 2>/dev/null || true
    pause_return
}

menu_systools() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [8] 系统工具、安全加固、换源与一键 DD 重装 ===${NC}"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e "  ${GREEN}1.${NC} [原生] 系统软件包全量更新与垃圾清理   ${CYAN}(自动适配 Debian/Ubuntu/CentOS/Alpine)${NC}"
        echo -e "  ${GREEN}2.${NC} GNU/Linux 一键更换系统软件源          ${CYAN}(SuperManito/LinuxMirrors 官方高 Star 脚本)${NC}"
        echo -e "  ${GREEN}3.${NC} [原生] 虚拟内存 (Swap) 创建与管理     ${CYAN}(支持 1G/2G/自定义大小，挽救小内存 VPS)${NC}"
        echo -e "  ${GREEN}4.${NC} [原生] 修改 SSH 端口 (带自动防火墙放行)${CYAN}(自动备份 sshd_config 防失联)${NC}"
        echo -e "  ${GREEN}5.${NC} [原生] 一键部署 Fail2ban SSH 防爆破   ${CYAN}(自动封禁暴力扫描 SSH 的恶意 IP)${NC}"
        echo -e "  ${GREEN}6.${NC} [原生] 同步系统时区为亚洲/上海时间    ${CYAN}(修复因时间误差导致的代理节点断连问题)${NC}"
        echo -e "  ${GREEN}7.${NC} 一键 DD 重装纯净系统 (bin456789)      ${CYAN}(GitHub 最高 Star 重装脚本，支持 Debian12/13 等)${NC}"
        echo -e "  ${GREEN}0.${NC} 返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择系统运维工具 [0-7]: " sys_choice

        case "$sys_choice" in
            1)
                echo ""
                local pm
                pm="$(detect_pkg_manager)"
                case "$pm" in
                    apt) apt-get update -y && apt-get upgrade -y && apt-get autoremove -y && apt-get clean ;;
                    dnf) dnf upgrade -y && dnf autoremove -y && dnf clean all ;;
                    yum) yum update -y && yum autoremove -y && yum clean all ;;
                    apk) apk update && apk upgrade ;;
                esac
                journalctl --vacuum-time=3d 2>/dev/null || true
                echo -e "${GREEN}[完成] 系统更新与日志清理完毕！${NC}"
                pause_return
                ;;
            2)
                run_verified_script \
                    "SuperManito LinuxMirrors 一键更换系统软件源" \
                    "https://github.com/SuperManito/LinuxMirrors" \
                    "https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh" \
                    "bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh)"
                ;;
            3) manage_swap ;;
            4) change_ssh_port ;;
            5) install_fail2ban ;;
            6)
                timedatectl set-timezone Asia/Shanghai 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
                timedatectl set-ntp true 2>/dev/null || true
                echo -e "${GREEN}[成功] 当前系统时间已同步为: $(date '+%Y-%m-%d %H:%M:%S %Z')${NC}"
                pause_return
                ;;
            7)
                echo ""
                echo -e "${RED}[高危操作提醒] DD 重装会彻底清空当前 VPS 硬盘所有数据！${NC}"
                echo "脚本下载后，您可以输入如: bash reinstall.sh debian 12 来重装纯净系统。"
                run_verified_script \
                    "bin456789/reinstall 官方一键 DD 重装脚本 (仅下载至当前目录并显示帮助)" \
                    "https://github.com/bin456789/reinstall" \
                    "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh" \
                    "curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh && chmod +x reinstall.sh && echo -e '\n[已下载 reinstall.sh] 请退出菜单后手动执行如: bash reinstall.sh debian 12'"
                ;;
            0) return ;;
            *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 模块 9：甲骨文云 (Oracle Cloud) 与云厂商救砖专区
# ==============================================================================
menu_oracle() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [9] 甲骨文云 (Oracle Cloud) 与云主机实用工具 ===${NC}"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e "  ${GREEN}1.${NC} [原生] 一键清空甲骨文云默认 iptables 阻断规则 ${CYAN}(解决节点/FRP搭好却无法连上的痛点)${NC}"
        echo -e "  ${GREEN}2.${NC} [原生] 开启 Root 用户密码 SSH 登录            ${CYAN}(适用于 Oracle / AWS / GCP 默认密钥机)${NC}"
        echo -e "  ${GREEN}0.${NC} 返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择操作 [0-2]: " oci_choice

        case "$oci_choice" in
            1)
                echo ""
                iptables -P INPUT ACCEPT 2>/dev/null || true
                iptables -P FORWARD ACCEPT 2>/dev/null || true
                iptables -P OUTPUT ACCEPT 2>/dev/null || true
                iptables -F 2>/dev/null || true
                netfilter-persistent save 2>/dev/null || service iptables save 2>/dev/null || true
                systemctl stop oracle-cloud-agent 2>/dev/null || true
                echo -e "${GREEN}[成功] 已放行主机内部所有 iptables 端口阻断规则！${NC}"
                pause_return
                ;;
            2)
                echo ""
                read -rsp "请输入要设置的 root 登录密码: " root_pwd
                echo ""
                if [[ -z "$root_pwd" ]]; then
                    echo -e "${RED}[错误] 密码不能为空！${NC}"
                    pause_return
                    continue
                fi
                echo "root:${root_pwd}" | chpasswd
                sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
                sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
                rm -f /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
                systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null || true
                echo -e "${GREEN}[成功] 已启用 root 密码 SSH 登录！${NC}"
                pause_return
                ;;
            0) return ;;
            *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 模块 10：原生硬件跑分、融合怪、NextTrace 三网回程与流媒体/AI 解锁测评
# ==============================================================================
menu_benchmark() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [10] 原生硬件跑分、NextTrace 三网回程与流媒体解锁测评 ===${NC}"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e "  ${GREEN}1.${NC} ${BOLD}[原生极速] 本机硬件性能实测看板${NC}   ${CYAN}(10秒内直接显示 CPU AES加密吞吐 / 内存带宽 / 磁盘三轮I/O)${NC}"
        echo -e "  ${GREEN}2.${NC} 融合怪综合测评脚本 (spiritLHLS)   ${CYAN}(国内最全：硬件跑分+三网回程路由+IP质量+解锁)${NC}"
        echo -e "  ${GREEN}3.${NC} NodeQuality 无痕沙箱测评 (LloydAsp)${CYAN}(NodeSeek 高人气颜值测评：测完自动清理不留垃圾)${NC}"
        echo -e "  ${GREEN}4.${NC} NextTrace 可视化三网回程路由追踪  ${CYAN}(nxtrace/NTrace-core 官方源：查 CN2 GIA/9929/CMIN2)${NC}"
        echo -e "  ${GREEN}5.${NC} YABS 国际标准基准测试 (masonr)    ${CYAN}(全球通用：FIO 磁盘读写 + iperf3 网络 + Geekbench)${NC}"
        echo -e "  ${GREEN}6.${NC} IPQuality IP 质量体检脚本 (xykt)  ${CYAN}(双栈检测：原生/广播IP、风险欺诈分、25端口邮局)${NC}"
        echo -e "  ${GREEN}7.${NC} 流媒体与 AI 解锁检测 (lmc999)     ${CYAN}(Netflix / Disney+ / YouTube / TikTok / ChatGPT)${NC}"
        echo -e "  ${GREEN}8.${NC} 秋水逸冰 Bench.sh 经典测速        ${CYAN}(快速查看基础硬件配置与全球多节点下载速度)${NC}"
        echo -e "  ${GREEN}0.${NC} 返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择测评或路由追踪工具 [0-8]: " bench_choice

        case "$bench_choice" in
            1) run_native_hardware_bench ;;
            2)
                run_verified_script \
                    "spiritLHLS 融合怪 VPS 综合测评脚本" \
                    "https://github.com/spiritLHLS/ecs" \
                    "https://raw.githubusercontent.com/spiritLHLS/ecs/main/ecs.sh" \
                    "bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/spiritLHLS/ecs/main/ecs.sh)"
                ;;
            3)
                run_verified_script \
                    "LloydAsp/NodeQuality 无痕沙箱综合测评脚本" \
                    "https://github.com/LloydAsp/NodeQuality" \
                    "https://run.NodeQuality.com" \
                    "bash <(curl -sL https://run.NodeQuality.com)"
                ;;
            4)
                run_verified_script \
                    "NextTrace (nxtrace/NTrace-core) 官方安装并追踪目标 IP" \
                    "https://github.com/nxtrace/NTrace-core" \
                    "https://nxtrace.org/nt" \
                    "curl -sL https://nxtrace.org/nt | bash && read -rp '请输入要测试回程的目标 IP (如国内电信/联通/移动 IP): ' nt_ip && [[ -n \"\$nt_ip\" ]] && nexttrace \"\$nt_ip\""
                ;;
            5)
                run_verified_script \
                    "YABS (Yet-Another-Bench-Script) 国际基准测试" \
                    "https://github.com/masonr/yet-another-bench-script" \
                    "https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/yabs.sh" \
                    "curl -sL https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/yabs.sh | bash"
                ;;
            6)
                run_verified_script \
                    "xykt IPQuality IP 质量体检脚本" \
                    "https://github.com/xykt/IPQuality" \
                    "https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh" \
                    "bash <(curl -Ls https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh)"
                ;;
            7)
                run_verified_script \
                    "lmc999 流媒体与 AI 区域限制解锁检测" \
                    "https://github.com/lmc999/RegionRestrictionCheck" \
                    "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh" \
                    "bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)"
                ;;
            8)
                run_verified_script \
                    "秋水逸冰 (teddysun) Bench.sh 硬件与网络测速" \
                    "https://github.com/teddysun/across" \
                    "https://raw.githubusercontent.com/teddysun/across/master/bench.sh" \
                    "wget -qO- https://raw.githubusercontent.com/teddysun/across/master/bench.sh | bash"
                ;;
            0) return ;;
            *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 模块 11：全能长链接转短链接中心 (单条/批量任意长链转短链 + 全脚本短链网关 + 自建短链服务)
# ==============================================================================

# 辅助函数：调用公开无广告短链 API (is.gd / v.gd / TinyURL) 将任意长链接转为短链
shorten_single_url() {
    local long_url="$1"
    local custom_slug="${2:-}"
    local short_res=""

    if [[ -n "$custom_slug" ]]; then
        short_res="$(curl -fsSL -G --data-urlencode "url=${long_url}" --data-urlencode "shorturl=${custom_slug}" "https://is.gd/create.php?format=simple" 2>/dev/null || true)"
    fi
    if [[ -z "$short_res" || "$short_res" == Error* ]]; then
        short_res="$(curl -fsSL -G --data-urlencode "url=${long_url}" "https://is.gd/create.php?format=simple" 2>/dev/null || true)"
    fi
    if [[ -z "$short_res" || "$short_res" == Error* ]]; then
        short_res="$(curl -fsSL -G --data-urlencode "url=${long_url}" "https://tinyurl.com/api-create.php" 2>/dev/null || true)"
    fi
    if [[ -z "$short_res" || "$short_res" == Error* ]]; then
        short_res="$(curl -fsSL -G --data-urlencode "url=${long_url}" "https://v.gd/create.php?format=simple" 2>/dev/null || true)"
    fi
    echo "$short_res"
}

# 11.1 交互式任意长链接 / 多条长链接转短链接工具
interactive_url_shortener() {
    echo ""
    echo -e "${BOLD}${GREEN}=== [全能短链转换器] 输入任意长链接一键变短链接 ===${NC}"
    echo -e "适用场景：超长的 Sing-box/Clash 订阅链接、GitHub Raw 脚本长链接、分享网址等。"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "请输入要缩短的长链接 (支持 http:// 或 https://): " input_url
    if [[ -z "$input_url" ]]; then
        echo -e "${RED}[错误] 链接不能为空！${NC}"
        pause_return
        return
    fi
    read -rp "可选：输入你想要的自定义短链后缀 (如 myvps123，留空则随机生成最短后缀): " input_slug

    echo -e "${YELLOW}[转换中] 正在请求短链接口生成短链接...${NC}"
    local res_isgd res_tiny
    res_isgd="$(shorten_single_url "$input_url" "$input_slug")"
    res_tiny="$(curl -fsSL -G --data-urlencode "url=${input_url}" "https://tinyurl.com/api-create.php" 2>/dev/null || echo 'N/A')"

    echo ""
    echo -e "${CYAN}======================================================================${NC}"
    echo -e " ${BOLD}原始长链接:${NC} ${input_url}"
    echo -e " ${BOLD}短链接通道 1 (is.gd 直链):${NC} ${GREEN}${BOLD}${res_isgd:-生成失败}${NC}"
    echo -e " ${BOLD}短链接通道 2 (TinyURL)  :${NC} ${YELLOW}${BOLD}${res_tiny:-生成失败}${NC}"
    if [[ "$input_url" == *.sh* ]]; then
        echo -e " ${BOLD}缩短后一键运行指令      :${NC} ${CYAN}bash <(curl -Ls ${res_isgd})${NC}"
    fi
    echo -e "${CYAN}======================================================================${NC}"
    pause_return
}

# 11.2 批量将工具箱内所有 20+ 个官方长脚本链接全部转换成短链接对照表
batch_shorten_all_toolbox_scripts() {
    echo ""
    echo -e "${BOLD}${GREEN}=== 批量将工具箱所有长脚本链接一键转换为短链接清单 ===${NC}"
    echo -e "正在为您把所有收录的高 Star 官方长链接实时生成短链接并保存至 ${YELLOW}/root/vps-shortlinks.txt${NC} ..."
    echo ""

    local entries=(
        "F佬_Sing-box全家桶|https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh"
        "勇哥_Sing-box-yg|https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh"
        "勇哥_ArgoSBX小钢炮|https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"
        "233boy_Sing-box|https://github.com/233boy/sing-box/raw/main/install.sh"
        "老王_eooce_Sing-box|https://raw.githubusercontent.com/eooce/Sing-box/main/sing-box.sh"
        "Mack-a_八合一脚本|https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh"
        "S-UI_官方Sing-box面板|https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh"
        "3X-UI_官方面板|https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
        "勇哥_X-UI-YG面板|https://raw.githubusercontent.com/yonggekkk/x-ui-yg/main/install.sh"
        "勇哥_ACME证书脚本|https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh"
        "F佬_WARP官方脚本|https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh"
        "勇哥_WARP-YG脚本|https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh"
        "P3TERX_WARP脚本|https://raw.githubusercontent.com/P3TERX/warp.sh/main/warp.sh"
        "MvsCode_Frps一键脚本|https://raw.githubusercontent.com/mvscode/frps-onekey/master/install-frps.sh"
        "Realm_端口中转脚本|https://raw.githubusercontent.com/zywe03/realm-xwPF/main/xwPF.sh"
        "GOST_v3官方脚本|https://raw.githubusercontent.com/go-gost/gost/master/install.sh"
        "LinuxMirrors_系统换源|https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh"
        "bin456789_一键DD重装|https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
        "spiritLHLS_融合怪测评|https://raw.githubusercontent.com/spiritLHLS/ecs/main/ecs.sh"
        "YABS_国际基准测评|https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/yabs.sh"
        "xykt_IPQuality体检|https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh"
        "lmc999_流媒体解锁检测|https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh"
    )

    local out_file="/root/vps-shortlinks.txt"
    echo "# VPS 常用高 Star 脚本短链接速查表 (生成时间: $(date '+%Y-%m-%d %H:%M:%S'))" > "$out_file"
    printf "%-24s | %-28s | %s\n" "脚本名称" "生成的短链接" "极简一键运行命令"
    echo "------------------------------------------------------------------------------------------------"

    local item title long_u short_u
    for item in "${entries[@]}"; do
        title="${item%%|*}"
        long_u="${item#*|}"
        short_u="$(shorten_single_url "$long_u")"
        [[ -z "$short_u" ]] && short_u="$long_u"
        printf "%-24s | ${GREEN}%-28s${NC} | bash <(curl -Ls %s)\n" "$title" "$short_u" "$short_u"
        printf "%-24s | %-28s | bash <(curl -Ls %s) | 原链: %s\n" "$title" "$short_u" "$short_u" "$long_u" >> "$out_file"
    done

    echo "------------------------------------------------------------------------------------------------"
    echo -e "${GREEN}[完成] 所有长链接已批量转换为短链接，并持久化保存在: ${YELLOW}${out_file}${NC}"
    pause_return
}

# 11.3 生成包含所有脚本短路由的 Cloudflare Worker 全能短链网关代码
generate_cf_worker_all_routes() {
    clear
    echo -e "${BOLD}${CYAN}=== 一键生成【所有脚本全路由短链网关】Cloudflare Worker 代码 ===${NC}"
    echo -e "说明：部署此 Worker 并绑定你的域名 (如 ${GREEN}s.你的域名.com${NC}) 后，不仅你的主脚本变成短链，"
    echo -e "工具箱里的 ${BOLD}所有 20+ 个长链接脚本、甚至任意外部长链接${NC} 都能通过你的专属域名直接变成短链！"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "请输入你的 GitHub 用户名 (如 myuser): " gh_user
    read -rp "请输入你的 GitHub 仓库名 (如 vps): " gh_repo
    gh_user="${gh_user:-<你的用户名>}"
    gh_repo="${gh_repo:-<你的仓库名>}"

    cat << EOF > /root/cf-shortlink-worker.js
// ============================================================================
// VPS 全脚本短链接路由网关 + 通用长链代理 Worker (复制粘贴到 Cloudflare Workers)
// ============================================================================
const ROUTES = {
  "/":      "https://raw.githubusercontent.com/${gh_user}/${gh_repo}/main/vps-toolbox.sh",
  "/vps":   "https://raw.githubusercontent.com/${gh_user}/${gh_repo}/main/vps-toolbox.sh",
  "/sb":    "https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh",
  "/yg":    "https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh",
  "/agsbx": "https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh",
  "/233":   "https://github.com/233boy/sing-box/raw/main/install.sh",
  "/eooce": "https://raw.githubusercontent.com/eooce/Sing-box/main/sing-box.sh",
  "/macka": "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh",
  "/sui":   "https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh",
  "/3xui":  "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh",
  "/xuiyg": "https://raw.githubusercontent.com/yonggekkk/x-ui-yg/main/install.sh",
  "/warp":  "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh",
  "/warpyg":"https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh",
  "/frps":  "https://raw.githubusercontent.com/mvscode/frps-onekey/master/install-frps.sh",
  "/realm": "https://raw.githubusercontent.com/zywe03/realm-xwPF/main/xwPF.sh",
  "/gost":  "https://raw.githubusercontent.com/go-gost/gost/master/install.sh",
  "/bbr":   "https://raw.githubusercontent.com/teddysun/across/master/bbr.sh",
  "/dd":    "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh",
  "/ecs":   "https://raw.githubusercontent.com/spiritLHLS/ecs/main/ecs.sh",
  "/yabs":  "https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/yabs.sh",
  "/ip":    "https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh",
  "/media": "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh"
};

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const target = ROUTES[url.pathname];
    if (target) {
      const res = await fetch(target);
      return new Response(res.body, {
        status: res.status,
        headers: { "content-type": "text/plain; charset=utf-8" }
      });
    }
    return new Response("Available short routes: " + Object.keys(ROUTES).join(", "), { status: 404 });
  }
};
EOF

    echo -e "${GREEN}[已生成] 完整代码已保存至 ${YELLOW}/root/cf-shortlink-worker.js${NC}，内容如下：${NC}"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    cat /root/cf-shortlink-worker.js
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "部署后，你所有的长脚本链接都会变成极简短命令，例如："
    echo -e "  • 启动你的总工具箱 : ${GREEN}bash <(curl -Ls s.你的域名.com)${NC}"
    echo -e "  • 直接跑 F佬全家桶 : ${GREEN}bash <(curl -Ls s.你的域名.com/sb)${NC}"
    echo -e "  • 直接跑 勇哥脚本  : ${GREEN}bash <(curl -Ls s.你的域名.com/yg)${NC}"
    echo -e "  • 直接跑 融合怪测评: ${GREEN}bash <(curl -Ls s.你的域名.com/ecs)${NC}"
    pause_return
}

# 11.4 一键在 VPS 上通过 Docker 自建开源 YOURLS / Shlink 私人短链系统
deploy_selfhosted_shlink() {
    echo ""
    echo -e "${BOLD}${GREEN}=== 部署官方 Shlink 开源自托管私人短链接服务 (Docker) ===${NC}"
    echo -e "开源仓库: ${YELLOW}https://github.com/shlinkio/shlink${NC}"
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}[提示] 请先在主菜单 [7] 安装 Docker 环境！${NC}"
        pause_return
        return
    fi
    local sh_domain sh_port
    read -rp "请输入短链服务绑定的域名或本机 IP (如 s.example.com): " sh_domain
    [[ -z "$sh_domain" ]] && sh_domain="$(curl -s4m 4 https://ipinfo.io/ip 2>/dev/null || echo 'localhost')"
    read -rp "请输入短链服务监听端口 [默认 8085]: " sh_port
    sh_port="${sh_port:-8085}"

    docker rm -f shlink 2>/dev/null || true
    docker run -d \
        --name shlink \
        --restart=always \
        -p "${sh_port}:8080" \
        -e DEFAULT_DOMAIN="${sh_domain}:${sh_port}" \
        -e IS_HTTPS_ENABLED="false" \
        shlinkio/shlink:stable

    echo -e "${GREEN}[成功] 官方 Shlink 短链接引擎已启动！可通过下方命令随时将任意长链生成你自己的短链：${NC}"
    echo -e "  ${CYAN}docker exec -it shlink shlink short-url:create${NC}"
    pause_return
}

menu_settings() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== [11] 全能长链接转短链接中心、自建短链服务与全局快捷键 ===${NC}"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e " ${BOLD}${YELLOW}【A. 长链接转短链接工具箱 (支持任意长链接 & 全脚本批量转短链)】${NC}"
        echo -e "  ${GREEN}1.${NC} 🔗 ${BOLD}[实时转换] 输入任意长链接一键转短链接${NC}   ${CYAN}(支持订阅链接/网页/脚本 + 自定义短后缀)${NC}"
        echo -e "  ${GREEN}2.${NC} 📋 ${BOLD}[批量转换] 将本脚本内所有 22 个长链接全部转成短链清单${NC} ${CYAN}(保存至 /root/vps-shortlinks.txt)${NC}"
        echo -e "  ${GREEN}3.${NC} ☁️  ${BOLD}[全路由网关] 生成包含所有脚本短路由的 CF Worker 代码${NC} ${CYAN}(如 s.域名/sb、s.域名/yg、s.域名/ecs)${NC}"
        echo -e "  ${GREEN}4.${NC} 🏠 [自建短链] Docker 一键部署官方 Shlink 私人短链服务 ${CYAN}(shlinkio/shlink 官方镜像)${NC}"
        echo ""
        echo -e " ${BOLD}${YELLOW}【B. 工具箱全局快捷键与安全审计设置】${NC}"
        echo -e "  ${GREEN}5.${NC} 安装全局快捷命令 [vps]        ${CYAN}(复制本脚本至 ${SHORTCUT_PATH}，随时输入 vps 启动)${NC}"
        echo -e "  ${GREEN}6.${NC} 切换外部脚本【安全审计模式】  ${CYAN}(当前状态: $([[ "$AUDIT_MODE" -eq 1 ]] && echo '开启二次确认' || echo '极速免确认'))${NC}"
        echo -e "  ${GREEN}7.${NC} 卸载全局快捷命令 [vps]        ${CYAN}(移除 ${SHORTCUT_PATH})${NC}"
        echo -e "  ${GREEN}0.${NC} 返回主菜单"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        read -rp "请选择短链接或设置项 [0-7]: " set_choice

        case "$set_choice" in
            1) interactive_url_shortener ;;
            2) batch_shorten_all_toolbox_scripts ;;
            3) generate_cf_worker_all_routes ;;
            4) deploy_selfhosted_shlink ;;
            5)
                echo ""
                local script_real
                script_real="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
                if [[ -f "$script_real" ]]; then
                    cp -f "$script_real" "$SHORTCUT_PATH"
                    chmod +x "$SHORTCUT_PATH"
                    echo -e "${GREEN}[成功] 已将工具箱安装至 ${SHORTCUT_PATH}！${NC}"
                    echo -e "今后在终端任意位置输入 ${BOLD}${GREEN}vps${NC} 即可随时呼出本工具箱。"
                elif [[ -n "$SELF_UPDATE_URL" ]]; then
                    curl -fsSL "$SELF_UPDATE_URL" -o "$SHORTCUT_PATH" && chmod +x "$SHORTCUT_PATH"
                    echo -e "${GREEN}[成功] 已从您的 GitHub 仓库拉取并注册快捷指令 vps！${NC}"
                else
                    echo -e "${YELLOW}[提示] 当前通过管道流运行。请先保存为文件 (curl -fsSL <你的直链> -o /usr/local/bin/vps && chmod +x /usr/local/bin/vps) 或在脚本顶部填入 SELF_UPDATE_URL。${NC}"
                fi
                pause_return
                ;;
            6)
                if [[ "$AUDIT_MODE" -eq 1 ]]; then
                    AUDIT_MODE=0
                    echo -e "${YELLOW}[已切换] 当前为【极速免确认模式】，仍会打印源地址但不再暂停询问。${NC}"
                else
                    AUDIT_MODE=1
                    echo -e "${GREEN}[已切换] 当前为【安全审计确认模式】，执行外部脚本前需确认官方源。${NC}"
                fi
                sleep 1
                ;;
            7)
                rm -f "$SHORTCUT_PATH"
                echo -e "${GREEN}[完成] 已移除快捷命令 ${SHORTCUT_PATH}。${NC}"
                pause_return
                ;;
            0) return ;;
            *) echo -e "${RED}无效选项！${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 双栏主菜单与入口循环 (融合实时状态仪表盘与十一大核心模块)
# ==============================================================================
show_main_menu() {
    clear
    render_dashboard
    echo -e "  ${GREEN}1.${NC} 系统体检与原生硬件跑分 ▷  ${GREEN}7.${NC} Docker/Aria2/AList/NAT小鸡 ▷"
    echo -e "  ${GREEN}2.${NC} ${BOLD}Sing-box 节点与多协议 ▷${NC}   ${GREEN}8.${NC} 系统工具/安全/换源/DD重装 ▷"
    echo -e "  ${GREEN}3.${NC} ${BOLD}SSL 证书申请与管理 ▷${NC}      ${GREEN}9.${NC} 甲骨文云 (OCI) 救砖专区 ▷"
    echo -e "  ${GREEN}4.${NC} ${BOLD}FRP/Tailscale/中转隧道 ▷${NC}  ${GREEN}10.${NC} 硬件跑分/融合怪/NextTrace ▷"
    echo -e "  ${GREEN}5.${NC} ${BOLD}Caddy/NPM反代/节点面板 ▷${NC}  ${GREEN}11.${NC} ${BOLD}长链转短链中心 & 快捷键 [vps] ▷${NC}"
    echo -e "  ${GREEN}6.${NC} ${BOLD}WARP三剑客/CF优选IP/BBR ▷${NC} ${GREEN}0.${NC}  退出工具箱"
    echo -e "${BOLD}${BLUE}======================================================================${NC}"
}

main() {
    check_root
    check_dependencies

    while true; do
        show_main_menu
        read -rp "请输入主菜单分类编号 [0-11]: " main_choice
        case "$main_choice" in
            1) menu_sysinfo ;;
            2) menu_singbox ;;
            3) menu_ssl_cert ;;
            4) menu_frp_relay ;;
            5) menu_panels ;;
            6) menu_network ;;
            7) menu_docker_nat ;;
            8) menu_systools ;;
            9) menu_oracle ;;
            10) menu_benchmark ;;
            11) menu_settings ;;
            0)
                echo -e "${GREEN}已退出 VPS 开源工具箱 Pro，祝使用愉快！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[错误] 请输入有效的分类编号 [0-11]！${NC}"
                sleep 1
                ;;
        esac
    done
}

main "$@"