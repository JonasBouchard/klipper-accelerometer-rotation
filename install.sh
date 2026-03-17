#!/bin/bash
set -e

KLIPPER_PATH="${HOME}/klipper"
KLIPPER_SERVICE_NAME="klipper"
MOONRAKER_SERVICE_NAME="moonraker"
MOONRAKER_CONFIG_DIR="${HOME}/printer_data/config"
BACKUP_DIR_NAME=".accelerometer_rotation_backup"
MODULES=(adxl345.py lis2dw.py mpu9250.py icm20948.py bmi160.py)

usage() {
    echo "Usage: $0 [-k <klipper path>] [-s <klipper service name>] [-m <moonraker service name>] [-c <configuration path>] [-u]" 1>&2
    exit 1
}

while getopts "k:s:m:c:uh" arg; do
    case $arg in
        k) KLIPPER_PATH="$OPTARG" ;;
        s) KLIPPER_SERVICE_NAME="$OPTARG" ;;
        m) MOONRAKER_SERVICE_NAME="$OPTARG" ;;
        c) MOONRAKER_CONFIG_DIR="$OPTARG" ;;
        u) UNINSTALL=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

SRCDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/src" && pwd)"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRAS_DIR="${KLIPPER_PATH}/klippy/extras"
BACKUP_DIR="${EXTRAS_DIR}/${BACKUP_DIR_NAME}"
MOONRAKER_CONFIG_FILE="${MOONRAKER_CONFIG_DIR}/moonraker.conf"
UPDATER_TEMPLATE="${REPO_DIR}/file_templates/moonraker_update.txt"
REPO_ORIGIN="$(git -C "${REPO_DIR}" config --get remote.origin.url 2>/dev/null || true)"

verify_ready() {
    if [ "$EUID" -eq 0 ]; then
        echo "[ERROR] This script must not run as root."
        exit 1
    fi
}

check_services() {
    if ! sudo systemctl list-units --full -all -t service --no-legend \
        | grep -Fq "${KLIPPER_SERVICE_NAME}.service"; then
        echo "[ERROR] Klipper service ${KLIPPER_SERVICE_NAME}.service not found."
        exit 1
    fi
    if ! sudo systemctl list-units --full -all -t service --no-legend \
        | grep -Fq "${MOONRAKER_SERVICE_NAME}.service"; then
        echo "[WARN] Moonraker service ${MOONRAKER_SERVICE_NAME}.service not found."
        SKIP_MOONRAKER=1
    fi
}

check_folders() {
    if [ ! -d "${EXTRAS_DIR}" ]; then
        echo "[ERROR] Klipper extras directory not found at ${EXTRAS_DIR}."
        exit 1
    fi
    if [ ! -d "${MOONRAKER_CONFIG_DIR}" ]; then
        if [ "${MOONRAKER_CONFIG_DIR}" = "${HOME}/printer_data/config" ] \
            && [ -d "${HOME}/klipper_config" ]; then
            MOONRAKER_CONFIG_DIR="${HOME}/klipper_config"
            MOONRAKER_CONFIG_FILE="${MOONRAKER_CONFIG_DIR}/moonraker.conf"
        else
            echo "[WARN] Moonraker config directory not found at ${MOONRAKER_CONFIG_DIR}."
            SKIP_MOONRAKER=1
        fi
    fi
    if [ ! -f "${MOONRAKER_CONFIG_FILE}" ]; then
        echo "[WARN] moonraker.conf not found at ${MOONRAKER_CONFIG_FILE}."
        SKIP_MOONRAKER=1
    fi
}

stop_klipper() {
    echo "[INFO] Stopping ${KLIPPER_SERVICE_NAME}..."
    sudo systemctl stop "${KLIPPER_SERVICE_NAME}"
}

start_klipper() {
    echo "[INFO] Starting ${KLIPPER_SERVICE_NAME}..."
    sudo systemctl start "${KLIPPER_SERVICE_NAME}"
}

restart_moonraker() {
    if [ "${SKIP_MOONRAKER:-0}" -eq 1 ]; then
        return
    fi
    echo "[INFO] Restarting ${MOONRAKER_SERVICE_NAME}..."
    sudo systemctl restart "${MOONRAKER_SERVICE_NAME}"
}

record_git_exclude() {
    local file="$1"
    local exclude_file="${KLIPPER_PATH}/.git/info/exclude"
    if [ -f "${exclude_file}" ] \
        && ! grep -Fq "klippy/extras/${file}" "${exclude_file}"; then
        echo "klippy/extras/${file}" >> "${exclude_file}"
    fi
}

install_modules() {
    mkdir -p "${BACKUP_DIR}"
    for file in "${MODULES[@]}"; do
        local target="${EXTRAS_DIR}/${file}"
        local source="${SRCDIR}/${file}"
        local backup="${BACKUP_DIR}/${file}"
        if [ ! -f "${source}" ]; then
            echo "[ERROR] Source file not found: ${source}"
            exit 1
        fi
        if [ -L "${target}" ] && [ "$(readlink -f "${target}")" = "${source}" ]; then
            echo "[SKIP] ${file} already linked."
            continue
        fi
        if [ ! -e "${backup}" ] && [ -e "${target}" ]; then
            cp -a "${target}" "${backup}"
        fi
        rm -f "${target}"
        ln -s "${source}" "${target}"
        record_git_exclude "${file}"
        echo "[OK] Linked ${file}"
    done
}

restore_modules() {
    for file in "${MODULES[@]}"; do
        local target="${EXTRAS_DIR}/${file}"
        local source="${SRCDIR}/${file}"
        local backup="${BACKUP_DIR}/${file}"
        if [ -L "${target}" ] && [ "$(readlink -f "${target}")" = "${source}" ]; then
            rm -f "${target}"
            echo "[OK] Removed link for ${file}"
        fi
        if [ -e "${backup}" ]; then
            cp -a "${backup}" "${target}"
            rm -f "${backup}"
            echo "[OK] Restored original ${file}"
        fi
    done
    rmdir "${BACKUP_DIR}" 2>/dev/null || true
}

add_updater() {
    if [ "${SKIP_MOONRAKER:-0}" -eq 1 ]; then
        return
    fi
    if grep -Fq "[update_manager accelerometer_rotation]" "${MOONRAKER_CONFIG_FILE}"; then
        echo "[SKIP] Moonraker update_manager entry already exists."
        return
    fi
    echo >> "${MOONRAKER_CONFIG_FILE}"
    sed \
        -e "s#__REPO_PATH__#${REPO_DIR}#g" \
        -e "s#__REPO_ORIGIN__#${REPO_ORIGIN:-__SET_YOUR_GIT_REMOTE__}#g" \
        "${UPDATER_TEMPLATE}" \
        >> "${MOONRAKER_CONFIG_FILE}"
    echo >> "${MOONRAKER_CONFIG_FILE}"
    echo "[OK] Added Moonraker update_manager entry"
}

remove_updater() {
    if [ "${SKIP_MOONRAKER:-0}" -eq 1 ] || [ ! -f "${MOONRAKER_CONFIG_FILE}" ]; then
        return
    fi
    python3 - "${MOONRAKER_CONFIG_FILE}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
out = []
skip = False
for line in lines:
    stripped = line.strip()
    if stripped == "[update_manager accelerometer_rotation]":
        skip = True
        continue
    if skip and stripped.startswith("[") and stripped.endswith("]"):
        skip = False
    if not skip:
        out.append(line)
path.write_text("\n".join(out).rstrip() + "\n")
PY
    echo "[OK] Removed Moonraker update_manager entry"
}

verify_ready
check_services
check_folders
stop_klipper
if [ "${UNINSTALL:-0}" -eq 1 ]; then
    restore_modules
    remove_updater
else
    install_modules
    add_updater
fi
start_klipper
restart_moonraker
