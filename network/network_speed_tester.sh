#!/bin/bash
set -uo pipefail

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'

SCRIPT_START=$(date +%s)
REPORT=""
DO_CURL=1
DO_SPEEDTEST_CLI=1
DO_IPERF=0
DO_SSH=0
IPERF_HOST=""
IPERF_PORT="5201"
IPERF_SECS="8"
SSH_TARGET=""
SSH_IDENTITY=""
CURL_URLS=(
    "https://proof.ovh.net/files/10Mb.dat"
    "https://speed.hetzner.de/10MB.bin"
    "http://speedtest.tele2.net/10MB.zip"
)
UPLOAD_URL="https://httpbin.org/post"
UPLOAD_BYTES=$((4 * 1024 * 1024))

declare -a REPORT_LINES

log_line() {
    REPORT_LINES+=("$1")
}

fmt_mbps() {
    awk -v b="${1:-0}" -v t="${2:-1}" 'BEGIN { if (t <= 0) t = 1; printf "%.2f", (b * 8) / (t * 1000000) }'
}

section() {
    local t="$1"
    echo -e "\n${CYAN}${BOLD}${t}${RESET}"
    log_line ""
    log_line "=== ${t} ==="
}

ok() {
    echo -e "  ${GREEN}✓${RESET} $*"
}

warn() {
    echo -e "  ${YELLOW}!${RESET} $*" >&2
}

fail() {
    echo -e "  ${RED}✗${RESET} $*" >&2
}

usage() {
    cat <<'U'
Usage: network_speed_tester.sh [options]

  -o FILE           Write report to FILE (default: /tmp/network_speed_report_HOST_TS.txt)
  --no-curl         Skip HTTP download/upload probes
  --no-speedtest    Skip speedtest-cli if present
  --iperf HOST      Run iperf3 TCP upload + download against HOST
  --iperf-port P    iperf3 port (default 5201)
  --iperf-time S    Seconds per iperf3 stream (default 8)
  --ssh USER@HOST   SCP upload+download loop test via SSH
  --identity FILE   SSH private key for --ssh

  -h, --help        Show this help

Requires: curl. Optional: iperf3, speedtest-cli, scp/ssh for remote tests.
U
}

while [ $# -gt 0 ]; do
    case "$1" in
        -o)
            REPORT="${2:?}"
            shift 2
            ;;
        --no-curl)
            DO_CURL=0
            shift
            ;;
        --no-speedtest)
            DO_SPEEDTEST_CLI=0
            shift
            ;;
        --iperf)
            DO_IPERF=1
            IPERF_HOST="${2:?}"
            shift 2
            ;;
        --iperf-port)
            IPERF_PORT="${2:?}"
            shift 2
            ;;
        --iperf-time)
            IPERF_SECS="${2:?}"
            shift 2
            ;;
        --ssh)
            DO_SSH=1
            SSH_TARGET="${2:?}"
            shift 2
            ;;
        --identity)
            SSH_IDENTITY="${2:?}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1"
            usage
            exit 2
            ;;
    esac
done

HOSTNAME_S=$(hostname -f 2>/dev/null || hostname)
TS=$(date +%Y%m%d_%H%M%S)
if [ -z "$REPORT" ]; then
    REPORT="/tmp/network_speed_report_${HOSTNAME_S}_${TS}.txt"
fi

write_report_file() {
    {
        echo "Network Speed Test Report"
        echo "Generated: $(date -Iseconds 2>/dev/null || date)"
        echo "Host: ${HOSTNAME_S}"
        echo "Kernel: $(uname -r)"
        for line in "${REPORT_LINES[@]}"; do
            echo "$line"
        done
        echo ""
        echo "Duration_seconds: $(($(date +%s) - SCRIPT_START))"
        echo "Report_end"
    } >"$REPORT"
}

trap 'write_report_file 2>/dev/null || true' EXIT

section "Environment"
echo -e "${DIM}Report file: ${REPORT}${RESET}"
log_line "Report_file: $REPORT"
if command -v curl >/dev/null 2>&1; then
    ok "curl: $(command -v curl)"
    log_line "curl: $(curl --version 2>/dev/null | head -1)"
else
    fail "curl not installed"
    log_line "curl: MISSING"
    write_report_file
    exit 1
fi

run_curl_download() {
    local url="$1" label="$2"
    local out time_s bytes mbps
    out=$(curl -sS -L --connect-timeout 12 --max-time 120 -o /dev/null -w '%{time_total} %{size_download} %{http_code}' "$url" 2>/dev/null) || return 1
    time_s=$(echo "$out" | awk '{print $1}')
    bytes=$(echo "$out" | awk '{print $2}')
    local code
    code=$(echo "$out" | awk '{print $3}')
    if [ "$code" != "200" ] && [ "$code" != "206" ]; then
        return 1
    fi
    mbps=$(fmt_mbps "$bytes" "$time_s")
    echo "$mbps|$bytes|$time_s|$label|$url"
    return 0
}

run_curl_upload() {
    local url="$1"
    local tmpf time_s speed_up
    tmpf=$(mktemp)
    if ! dd if=/dev/zero of="$tmpf" bs=1M count=$((UPLOAD_BYTES / 1048576)) status=none 2>/dev/null; then
        rm -f "$tmpf"
        return 1
    fi
    local out
    out=$(curl -sS -L --connect-timeout 15 --max-time 180 -X POST -H "Content-Type: application/octet-stream" --data-binary "@${tmpf}" -o /dev/null -w '%{time_total} %{speed_upload}' "$url" 2>/dev/null) || true
    rm -f "$tmpf"
    time_s=$(echo "$out" | awk '{print $1}')
    speed_up=$(echo "$out" | awk '{print $2}')
    if [ -z "$time_s" ] || [ "$time_s" = "0.000000" ]; then
        return 1
    fi
    echo "$time_s|$speed_up"
    return 0
}

if [ "$DO_CURL" -eq 1 ]; then
    section "Internet HTTP (curl)"
    curl_got=0
    for url in "${CURL_URLS[@]}"; do
        res=$(run_curl_download "$url" "GET") || continue
        curl_got=1
        mbps=$(echo "$res" | cut -d'|' -f1)
        bytes=$(echo "$res" | cut -d'|' -f2)
        t=$(echo "$res" | cut -d'|' -f3)
        lab=$(echo "$res" | cut -d'|' -f4)
        echo -e "  ${lab} ${DIM}${url}${RESET}"
        echo -e "    ${GREEN}${mbps} Mbit/s${RESET}  (${bytes} bytes in ${t}s)"
        log_line "curl_download_Mbit_s: ${mbps} url=${url} bytes=${bytes} time_s=${t}"
        break
    done
    if [ "$curl_got" -eq 0 ]; then
        warn "All download URLs failed or returned non-200"
        log_line "curl_download: FAILED all endpoints"
    fi
    up=$(run_curl_upload "$UPLOAD_URL") || true
    if [ -n "$up" ]; then
        ut=$(echo "$up" | cut -d'|' -f1)
        uu=$(echo "$up" | cut -d'|' -f2)
        uu_mbps=$(awk -v u="$uu" 'BEGIN { printf "%.2f", u / 125000 }')
        echo -e "  POST ${DIM}${UPLOAD_URL}${RESET}"
        echo -e "    ${GREEN}${uu_mbps} Mbit/s${RESET} (curl speed_upload B/s=${uu}, time=${ut}s)"
        log_line "curl_upload_Mbit_s: ${uu_mbps} speed_upload_Bps=${uu} time_s=${ut} url=${UPLOAD_URL}"
    else
        warn "HTTP upload probe failed"
        log_line "curl_upload: FAILED"
    fi
else
    log_line "curl_tests: SKIPPED"
fi

if [ "$DO_SPEEDTEST_CLI" -eq 1 ] && command -v speedtest-cli >/dev/null 2>&1; then
    section "speedtest-cli (Ookla public mesh)"
    st_out=$(speedtest-cli --simple 2>/dev/null) || st_out=""
    if [ -n "$st_out" ]; then
        echo "$st_out" | sed 's/^/  /'
        log_line "speedtest-cli_raw:"
        while IFS= read -r line; do
            log_line "  $line"
        done <<< "$st_out"
        ping_ms=$(echo "$st_out" | awk -F': ' '/^Ping:/{gsub(/ ms/,"",$2); print $2}')
        down_m=$(echo "$st_out" | awk -F': ' '/^Download:/{print $2}')
        up_m=$(echo "$st_out" | awk -F': ' '/^Upload:/{print $2}')
        log_line "speedtest_parse: ping_ms=${ping_ms} download_Mbit_s=${down_m} upload_Mbit_s=${up_m}"
    else
        warn "speedtest-cli run failed"
        log_line "speedtest-cli: FAILED"
    fi
elif [ "$DO_SPEEDTEST_CLI" -eq 1 ]; then
    log_line "speedtest-cli: NOT_INSTALLED"
fi

if [ "$DO_IPERF" -eq 1 ]; then
    section "iperf3 (TCP to ${IPERF_HOST}:${IPERF_PORT})"
    if command -v iperf3 >/dev/null 2>&1; then
        up_line=$(iperf3 -c "$IPERF_HOST" -p "$IPERF_PORT" -t "$IPERF_SECS" -f m 2>/dev/null | awk '/sender$/{l=$0} END{print l}') || up_line=""
        down_line=$(iperf3 -c "$IPERF_HOST" -p "$IPERF_PORT" -t "$IPERF_SECS" -R -f m 2>/dev/null | awk '/receiver$/{l=$0} END{print l}') || down_line=""
        if [ -n "$up_line" ]; then
            echo "  upload (client TX):   $up_line"
            log_line "iperf3_upload: $up_line"
        else
            warn "iperf3 upload failed"
            log_line "iperf3_upload: FAILED"
        fi
        if [ -n "$down_line" ]; then
            echo "  download (client RX): $down_line"
            log_line "iperf3_download: $down_line"
        else
            warn "iperf3 reverse (download) failed"
            log_line "iperf3_download: FAILED"
        fi
    else
        warn "iperf3 not installed"
        log_line "iperf3: NOT_INSTALLED"
    fi
else
    log_line "iperf3: SKIPPED"
fi

if [ "$DO_SSH" -eq 1 ]; then
    section "Remote SSH (scp round-trip)"
    if command -v scp >/dev/null 2>&1 && command -v ssh >/dev/null 2>&1; then
        ssh_tmp=$(mktemp)
        dd if=/dev/urandom of="$ssh_tmp" bs=1M count=8 status=none 2>/dev/null || true
        ssh_sz=$(stat -c%s "$ssh_tmp" 2>/dev/null || wc -c <"$ssh_tmp")
        ssh_rpath=".network_speed_tester_${TS}.bin"
        ssh_id_args=()
        [ -n "$SSH_IDENTITY" ] && ssh_id_args=(-i "$SSH_IDENTITY")
        t0=$(date +%s.%N 2>/dev/null || date +%s)
        if scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${ssh_id_args[@]}" -q "$ssh_tmp" "${SSH_TARGET}:~/${ssh_rpath}" 2>/dev/null; then
            t1=$(date +%s.%N 2>/dev/null || date +%s)
            up_t=$(awk -v a="$t0" -v b="$t1" 'BEGIN{print b-a}')
            up_mbps=$(fmt_mbps "$ssh_sz" "$up_t")
            echo -e "  scp upload:   ${GREEN}${up_mbps} Mbit/s${RESET} (${ssh_sz} B in ${up_t}s)"
            log_line "scp_upload_Mbit_s: ${up_mbps} bytes=${ssh_sz} time_s=${up_t} target=${SSH_TARGET}"
            ssh_tmp2=$(mktemp)
            t2=$(date +%s.%N 2>/dev/null || date +%s)
            if scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${ssh_id_args[@]}" -q "${SSH_TARGET}:~/${ssh_rpath}" "$ssh_tmp2" 2>/dev/null; then
                t3=$(date +%s.%N 2>/dev/null || date +%s)
                dn_t=$(awk -v a="$t2" -v b="$t3" 'BEGIN{print b-a}')
                dn_mbps=$(fmt_mbps "$ssh_sz" "$dn_t")
                echo -e "  scp download: ${GREEN}${dn_mbps} Mbit/s${RESET} (${ssh_sz} B in ${dn_t}s)"
                log_line "scp_download_Mbit_s: ${dn_mbps} bytes=${ssh_sz} time_s=${dn_t} target=${SSH_TARGET}"
            else
                warn "scp download from ${SSH_TARGET} failed"
                log_line "scp_download: FAILED"
                rm -f "$ssh_tmp2"
            fi
            ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${ssh_id_args[@]}" -q "${SSH_TARGET}" "rm -f ~/${ssh_rpath}" 2>/dev/null || true
            rm -f "$ssh_tmp" "$ssh_tmp2"
        else
            warn "scp upload to ${SSH_TARGET} failed"
            log_line "scp_upload: FAILED target=${SSH_TARGET}"
            rm -f "$ssh_tmp"
        fi
    else
        warn "scp or ssh not available"
        log_line "scp: NOT_INSTALLED"
    fi
else
    log_line "scp_remote: SKIPPED"
fi

section "Summary"
echo -e "  ${DIM}Full report: ${REPORT}${RESET}"
log_line ""
log_line "=== Summary ==="
log_line "Completed: $(date -Iseconds 2>/dev/null || date)"
ok "Report written"

trap - EXIT
write_report_file
echo -e "\n${GREEN}${BOLD}Done${RESET}"
