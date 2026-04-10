#!/bin/bash
# remote_backup.sh — local backup with optional rsync/SSH transfer and retention
# Usage: sudo ./remote_backup.sh [-c CONFIG] [-n|--dry-run] [-q|--quiet]

set -euo pipefail

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=""
DRY_RUN=0
QUIET=0

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    if [ "$QUIET" -eq 0 ]; then
        echo -e "$msg"
    fi
    if [ -n "${LOG_FILE:-}" ]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE" 2>/dev/null || true
    fi
}

die() {
    echo -e "${RED}${BOLD}ERROR:${RESET} $*" >&2
    log "ERROR: $*"
    exit 1
}

usage() {
    cat <<EOF
${BOLD}remote_backup.sh${RESET}

  -c FILE     Path to backup.conf (default: try script dir, then /etc/system_scripts/backup.conf)
  -n, --dry-run   Show actions without writing archives or transferring
  -q, --quiet     Minimal console output (still logs if LOG_FILE is set)
  -h, --help      This help

EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -c)
            CONFIG_FILE="${2:?}"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

if [ -z "$CONFIG_FILE" ]; then
    if [ -f "$SCRIPT_DIR/backup.conf" ]; then
        CONFIG_FILE="$SCRIPT_DIR/backup.conf"
    elif [ -f "/etc/system_scripts/backup.conf" ]; then
        CONFIG_FILE="/etc/system_scripts/backup.conf"
    else
        die "No backup.conf found. Use -c /path/to/backup.conf or install backup.conf"
    fi
fi

[ -f "$CONFIG_FILE" ] || die "Config not found: $CONFIG_FILE"
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Defaults after sourcing
: "${BACKUP_NAME:=$(hostname -s)}"
: "${LOCAL_STAGING_DIR:=/var/backups/system_scripts_staging}"
: "${LOG_FILE:=}"
: "${BACKUP_MODE:=archive}"
: "${ARCHIVE_COMPRESS:=gzip}"
: "${ARCHIVE_FILENAME_PREFIX:=}"
: "${REMOTE_ENABLED:=no}"
: "${REMOTE_HOST:=}"
: "${REMOTE_USER:=root}"
: "${REMOTE_PORT:=22}"
: "${REMOTE_PATH:=/backups}"
: "${SSH_IDENTITY_FILE:=}"
: "${RSYNC_EXTRA_OPTS:=}"
: "${VERIFY_CHECKSUM:=yes}"
: "${RETENTION_DAYS_LOCAL:=7}"
: "${RETENTION_DAYS_REMOTE:=0}"
: "${PRE_BACKUP_HOOK:=}"
: "${POST_BACKUP_HOOK:=}"
: "${MYSQL_DUMP_ENABLED:=no}"
: "${MYSQL_DUMP_USER:=}"
: "${MYSQL_DEFAULTS_EXTRA_FILE:=}"
: "${MYSQL_DATABASES:=}"
: "${POSTGRES_DUMP_ENABLED:=no}"
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_DATABASES:=}"
: "${DB_DUMP_SUBDIR:=_db_dumps}"

# Allow minimal configs: default empty arrays if not declared
if ! declare -p BACKUP_SOURCES &>/dev/null; then
    declare -a BACKUP_SOURCES=()
fi
if ! declare -p BACKUP_EXCLUDES &>/dev/null; then
    declare -a BACKUP_EXCLUDES=()
fi

if [ "$QUIET" -eq 0 ]; then
    echo -e "${CYAN}${BOLD}Backup${RESET} using ${BLUE}$CONFIG_FILE${RESET}"
fi

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

run_hook() {
    local hook_path="$1"
    [ -z "$hook_path" ] && return 0
    [ -x "$hook_path" ] || die "Hook is not executable: $hook_path"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: would run hook $hook_path"
        return 0
    fi
    log "Running hook: $hook_path"
    "$hook_path" || die "Hook failed: $hook_path"
}

# Single string for rsync -e (paths safely quoted)
rsync_rsh_shell() {
    if [ -n "$SSH_IDENTITY_FILE" ]; then
        printf 'ssh -p %s -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i %q' "$REMOTE_PORT" "$SSH_IDENTITY_FILE"
    else
        printf 'ssh -p %s -o BatchMode=yes -o StrictHostKeyChecking=accept-new' "$REMOTE_PORT"
    fi
    echo
}

compress_tar_flag() {
    case "${ARCHIVE_COMPRESS,,}" in
        gzip|gz)  echo "z" ;;
        xz)       echo "J" ;;
        zstd|zst)
            require_cmd zstd
            echo "zstd" ;;
        none|"")  echo "" ;;
        *) die "Unknown ARCHIVE_COMPRESS: $ARCHIVE_COMPRESS (use gzip, xz, zstd, none)" ;;
    esac
}

archive_extension() {
    case "${ARCHIVE_COMPRESS,,}" in
        gzip|gz)  echo "tar.gz" ;;
        xz)       echo "tar.xz" ;;
        zstd|zst) echo "tar.zst" ;;
        none|"")  echo "tar" ;;
        *)        echo "tar.gz" ;;
    esac
}

mysql_dump_to() {
    local dest_dir="$1"
    require_cmd mysqldump
    mkdir -p "$dest_dir"
    local args=(--single-transaction --quick --routines --events)
    if [ -n "$MYSQL_DEFAULTS_EXTRA_FILE" ]; then
        args+=(--defaults-extra-file="$MYSQL_DEFAULTS_EXTRA_FILE")
    elif [ -n "$MYSQL_DUMP_USER" ]; then
        args+=(-u"$MYSQL_DUMP_USER")
    fi
    if [ -n "$MYSQL_DATABASES" ]; then
        local db
        for db in $MYSQL_DATABASES; do
            log "MySQL dump: $db"
            if [ "$DRY_RUN" -eq 1 ]; then
                continue
            fi
            mysqldump "${args[@]}" "$db" | gzip -c >"$dest_dir/mysql_${db}.sql.gz" || die "mysqldump failed for $db"
        done
    else
        log "MySQL dump: all databases"
        if [ "$DRY_RUN" -eq 0 ]; then
            mysqldump "${args[@]}" --all-databases | gzip -c >"$dest_dir/mysql_all.sql.gz" || die "mysqldump --all-databases failed"
        fi
    fi
}

postgres_dump_to() {
    local dest_dir="$1"
    mkdir -p "$dest_dir"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: PostgreSQL dump"
        return 0
    fi
    if [ -n "$POSTGRES_DATABASES" ]; then
        require_cmd pg_dump
        local db
        for db in $POSTGRES_DATABASES; do
            log "PostgreSQL dump: $db"
            sudo -u "$POSTGRES_USER" pg_dump "$db" | gzip -c >"$dest_dir/pg_${db}.sql.gz" || die "pg_dump failed for $db"
        done
    else
        require_cmd pg_dumpall
        log "PostgreSQL dump: all (pg_dumpall)"
        sudo -u "$POSTGRES_USER" pg_dumpall | gzip -c >"$dest_dir/pg_all.sql.gz" || die "pg_dumpall failed"
    fi
}

create_archive() {
    require_cmd tar
    local ts stamp workdir archive_path
    ts=$(date +%Y%m%d-%H%M%S)
    stamp="${ARCHIVE_FILENAME_PREFIX:+$ARCHIVE_FILENAME_PREFIX-}${BACKUP_NAME}-${ts}"
    workdir="$LOCAL_STAGING_DIR/work-${stamp}"
    archive_path="$LOCAL_STAGING_DIR/${stamp}.$(archive_extension)"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: would create $archive_path from sources (no full-tree copy; tar streams from paths)"
        echo "$archive_path"
        return 0
    fi

    mkdir -p "$workdir/$DB_DUMP_SUBDIR" "$LOCAL_STAGING_DIR"

    if [ "${MYSQL_DUMP_ENABLED,,}" = "yes" ]; then
        mysql_dump_to "$workdir/$DB_DUMP_SUBDIR"
    fi
    if [ "${POSTGRES_DUMP_ENABLED,,}" = "yes" ]; then
        postgres_dump_to "$workdir/$DB_DUMP_SUBDIR"
    fi

    local -a tar_args=()
    local ex
    for ex in "${BACKUP_EXCLUDES[@]}"; do
        [ -z "$ex" ] && continue
        tar_args+=(--exclude="$ex")
    done

    local dump_nonempty=0
    if [ -d "$workdir/$DB_DUMP_SUBDIR" ]; then
        local dump_glob
        shopt -s nullglob
        dump_glob=( "$workdir/$DB_DUMP_SUBDIR"/* )
        shopt -u nullglob
        [ ${#dump_glob[@]} -gt 0 ] && dump_nonempty=1
    fi
    if [ "$dump_nonempty" -eq 1 ]; then
        tar_args+=(-C "$workdir" "$DB_DUMP_SUBDIR")
    fi

    local src parent name
    for src in "${BACKUP_SOURCES[@]}"; do
        [ -z "$src" ] && continue
        [ -e "$src" ] || { log "${YELLOW}SKIP missing path:${RESET} $src"; continue; }
        if [ "$src" = "/" ]; then
            die "Refusing to archive '/' — set explicit paths in BACKUP_SOURCES instead"
        fi
        parent="$(dirname "$src")"
        name="$(basename "$src")"
        tar_args+=(-C "$parent" "$name")
    done

    if [ ${#tar_args[@]} -eq 0 ] && [ "$dump_nonempty" -eq 0 ]; then
        die "No backup sources and no database dumps — nothing to archive"
    fi

    local comp
    comp=$(compress_tar_flag)

    log "Creating archive: $archive_path"
    if [ "$comp" = "zstd" ]; then
        tar --zstd -cf "$archive_path" "${tar_args[@]}" || die "tar failed"
    elif [ -n "$comp" ]; then
        tar -c"${comp}"f "$archive_path" "${tar_args[@]}" || die "tar failed"
    else
        tar -cf "$archive_path" "${tar_args[@]}" || die "tar failed"
    fi

    rm -rf "$workdir"
    echo "$archive_path"
}

transfer_rsync() {
    local src="$1"
    require_cmd rsync
    [ "${REMOTE_ENABLED,,}" = "yes" ] || { log "Remote transfer disabled (REMOTE_ENABLED!=yes)"; return 0; }
    [ -n "$REMOTE_HOST" ] || die "REMOTE_HOST is empty"

    local ssh_cmd
    ssh_cmd="$(rsync_rsh_shell | tr -d '\n')"
    # shellcheck disable=SC2086
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: rsync $src -> ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"
        rsync -avn -e "$ssh_cmd" $RSYNC_EXTRA_OPTS "$src" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" || true
        return 0
    fi

    log "Rsync to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"
    ssh -p "$REMOTE_PORT" ${SSH_IDENTITY_FILE:+-i "$SSH_IDENTITY_FILE"} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p $(printf '%q' "$REMOTE_PATH")"

    rsync -av -e "$ssh_cmd" $RSYNC_EXTRA_OPTS "$src" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" || die "rsync failed"
}

transfer_archive_and_verify() {
    local archive_path="$1"
    local base
    base=$(basename "$archive_path")

    transfer_rsync "$archive_path"

    if [ "${REMOTE_ENABLED,,}" != "yes" ] || [ "$DRY_RUN" -eq 1 ]; then
        return 0
    fi
    if [ "${VERIFY_CHECKSUM,,}" != "yes" ]; then
        return 0
    fi

    require_cmd sha256sum
    local local_sum remote_sum
    local_sum=$(sha256sum "$archive_path" | awk '{print $1}')
    remote_sum=$(ssh -p "$REMOTE_PORT" ${SSH_IDENTITY_FILE:+-i "$SSH_IDENTITY_FILE"} -o BatchMode=yes \
        "${REMOTE_USER}@${REMOTE_HOST}" "sha256sum $(printf '%q' "${REMOTE_PATH}/${base}") 2>/dev/null" | awk '{print $1}')

    if [ "$local_sum" = "$remote_sum" ] && [ -n "$remote_sum" ]; then
        log "${GREEN}Checksum OK${RESET} $base"
    else
        die "Checksum mismatch for $base (local=$local_sum remote=$remote_sum)"
    fi
}

retention_local() {
    local days="$RETENTION_DAYS_LOCAL"
    [ "${days:-0}" -gt 0 ] 2>/dev/null || return 0
    [ -d "$LOCAL_STAGING_DIR" ] || return 0
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: prune local archives older than ${days}d in $LOCAL_STAGING_DIR"
        return 0
    fi
    log "Pruning local archives older than ${days} days"
    find "$LOCAL_STAGING_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.tar.xz" -o -name "*.tar.zst" -o -name "*.tar" \) -mtime "+$days" -delete 2>/dev/null || true
}

retention_remote() {
    local days="$RETENTION_DAYS_REMOTE"
    [ "${days:-0}" -gt 0 ] 2>/dev/null || return 0
    [ "${REMOTE_ENABLED,,}" = "yes" ] || return 0
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: prune remote archives older than ${days}d in $REMOTE_PATH"
        return 0
    fi
    log "Pruning remote archives older than ${days} days on $REMOTE_HOST"
    ssh -p "$REMOTE_PORT" ${SSH_IDENTITY_FILE:+-i "$SSH_IDENTITY_FILE"} -o BatchMode=yes \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "find $(printf '%q' "$REMOTE_PATH") -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.tar.zst' -o -name '*.tar' \) -mtime '+$days' -delete" || log "${YELLOW}Remote retention warning (ssh/find)${RESET}"
}

mode_rsync_direct() {
    require_cmd rsync
    [ "${REMOTE_ENABLED,,}" = "yes" ] || die "rsync mode requires REMOTE_ENABLED=yes"
    local ssh_cmd
    ssh_cmd="$(rsync_rsh_shell | tr -d '\n')"
    ssh -p "$REMOTE_PORT" ${SSH_IDENTITY_FILE:+-i "$SSH_IDENTITY_FILE"} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p $(printf '%q' "$REMOTE_PATH")"

    local -a exargs=()
    local a
    for a in "${BACKUP_EXCLUDES[@]}"; do
        [ -z "$a" ] && continue
        exargs+=(--exclude="$a")
    done
    local src
    for src in "${BACKUP_SOURCES[@]}"; do
        [ -z "$src" ] && continue
        [ -e "$src" ] || { log "${YELLOW}SKIP missing:${RESET} $src"; continue; }
        log "Rsync source: $src"
        # shellcheck disable=SC2086
        if [ "$DRY_RUN" -eq 1 ]; then
            rsync -avn -e "$ssh_cmd" $RSYNC_EXTRA_OPTS "${exargs[@]}" "$src" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" || true
        else
            rsync -av -e "$ssh_cmd" $RSYNC_EXTRA_OPTS "${exargs[@]}" "$src" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" || die "rsync failed for $src"
        fi
    done
}

require_cmd bash
run_hook "$PRE_BACKUP_HOOK"

case "${BACKUP_MODE,,}" in
    archive)
        ARCHIVE_FILE="$(create_archive)"
        if [ "$DRY_RUN" -eq 0 ] && [ -n "$ARCHIVE_FILE" ] && [ -f "$ARCHIVE_FILE" ]; then
            transfer_archive_and_verify "$ARCHIVE_FILE"
        fi
        ;;
    rsync)
        mode_rsync_direct
        ;;
    *)
        die "Unknown BACKUP_MODE: $BACKUP_MODE (use archive or rsync)"
        ;;
esac

retention_local
retention_remote

run_hook "$POST_BACKUP_HOOK"

if [ "$QUIET" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}Done${RESET}"
fi
log "Backup finished successfully"
