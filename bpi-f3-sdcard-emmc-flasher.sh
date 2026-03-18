#!/usr/bin/env bash

# ==============================================================================
# BPI-F3 SD Card to eMMC Flasher for openSUSE Tumbleweed
#
# Credits:
# - Banana Pi BPI-F3 / SpacemiT K1 platform
# - openSUSE Tumbleweed riscv64 SD-card image workflow
# - Bianbu firmware bundle for the K1 boot chain
# ==============================================================================

set -euo pipefail

SCRIPT_VERSION="1.0.0"
DEFAULT_FIRMWARE_DIR="/root/Downloads/bianbu-23.10-nas-k1-v1.0rc1-release-20240429192450"
DEFAULT_OS_IMAGE="/root/Downloads/2024-09-09-openSUSE-Tumbleweed-RISC-V-LXQT.riscv64-rootfs.riscv64-2024.09.02-Build1.9.tar.xz-bpi-f3-7356MB.img"

FIRMWARE_DIR="${DEFAULT_FIRMWARE_DIR}"
OS_IMAGE="${DEFAULT_OS_IMAGE}"
EMMC_DEVICE="/dev/mmcblk2"
BOOT0_DEVICE="/dev/mmcblk2boot0"
BOOT_MOUNT="/mnt/bpi-f3-emmc-boot"
ROOT_MOUNT="/mnt/bpi-f3-emmc-root"

ASSUME_YES=0
POWER_OFF_WHEN_DONE=1
LANG_CHOICE=""
LOOP_DEVICE=""

EMMC_ENV_PART=""
EMMC_OPENSBI_PART=""
EMMC_UBOOT_PART=""
EMMC_BOOT_PART=""
EMMC_ROOT_PART=""
BOOT_PART_NAME=""
ROOT_PART_NAME=""

usage() {
    cat <<'EOF'
Usage:
  bpi-f3-sdcard-emmc-flasher.sh [options]

Options:
  --yes                    Run non-interactively where possible.
  --lang en|ko             Force installer language.
  --firmware-dir <path>    Override the Bianbu firmware directory.
  --os-image <path>        Override the openSUSE disk image path.
  --emmc-device <device>   Override the target eMMC block device.
  --boot0-device <device>  Override the target eMMC boot0 device.
  --no-poweroff            Skip automatic poweroff after flashing.
  --help                   Show this help.
EOF
}

say() {
    if [[ "${LANG_CHOICE}" == "ko" ]]; then
        printf '%s\n' "$2"
    else
        printf '%s\n' "$1"
    fi
}

die() {
    say "$1" "$2" >&2
    exit 1
}

confirm() {
    local prompt_en="$1"
    local prompt_ko="$2"

    if [[ "${ASSUME_YES}" -eq 1 ]]; then
        return 0
    fi

    local reply=""
    if [[ "${LANG_CHOICE}" == "ko" ]]; then
        read -r -p "${prompt_ko} [y/N]: " reply
    else
        read -r -p "${prompt_en} [y/N]: " reply
    fi

    [[ "${reply}" == "y" || "${reply}" == "Y" ]]
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die \
        "Missing required command: $1" \
        "필수 명령어가 없습니다: $1"
}

part_path() {
    local device="$1"
    local part_number="$2"

    case "${device}" in
        *[0-9]) printf '%sp%s\n' "${device}" "${part_number}" ;;
        *) printf '%s%s\n' "${device}" "${part_number}" ;;
    esac
}

cleanup() {
    set +e

    if mountpoint -q "${ROOT_MOUNT}" 2>/dev/null; then
        umount "${ROOT_MOUNT}"
    fi

    if mountpoint -q "${BOOT_MOUNT}" 2>/dev/null; then
        umount "${BOOT_MOUNT}"
    fi

    if [[ -n "${LOOP_DEVICE}" ]] && losetup "${LOOP_DEVICE}" >/dev/null 2>&1; then
        losetup -d "${LOOP_DEVICE}"
    fi
}

trap 'status=$?; cleanup; exit "$status"' EXIT

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes)
                ASSUME_YES=1
                shift
                ;;
            --lang)
                [[ $# -ge 2 ]] || die \
                    "--lang requires a value" \
                    "--lang 옵션에는 값이 필요합니다."
                LANG_CHOICE="$2"
                shift 2
                ;;
            --firmware-dir)
                [[ $# -ge 2 ]] || die \
                    "--firmware-dir requires a value" \
                    "--firmware-dir 옵션에는 값이 필요합니다."
                FIRMWARE_DIR="$2"
                shift 2
                ;;
            --os-image)
                [[ $# -ge 2 ]] || die \
                    "--os-image requires a value" \
                    "--os-image 옵션에는 값이 필요합니다."
                OS_IMAGE="$2"
                shift 2
                ;;
            --emmc-device)
                [[ $# -ge 2 ]] || die \
                    "--emmc-device requires a value" \
                    "--emmc-device 옵션에는 값이 필요합니다."
                EMMC_DEVICE="$2"
                shift 2
                ;;
            --boot0-device)
                [[ $# -ge 2 ]] || die \
                    "--boot0-device requires a value" \
                    "--boot0-device 옵션에는 값이 필요합니다."
                BOOT0_DEVICE="$2"
                shift 2
                ;;
            --no-poweroff)
                POWER_OFF_WHEN_DONE=0
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1" "알 수 없는 옵션입니다: $1"
                ;;
        esac
    done
}

select_language() {
    if [[ -n "${LANG_CHOICE}" ]]; then
        case "${LANG_CHOICE}" in
            en|ko) return 0 ;;
            *)
                die "Invalid language: ${LANG_CHOICE}" "잘못된 언어 값입니다: ${LANG_CHOICE}"
                ;;
        esac
    fi

    if [[ "${ASSUME_YES}" -eq 1 ]]; then
        LANG_CHOICE="en"
        return 0
    fi

    clear || true
    printf '%s\n' "========================================================"
    printf '%s\n' " BPI-F3 SD Card to eMMC Flasher ${SCRIPT_VERSION}"
    printf '%s\n' "========================================================"
    read -r -p "Select language / 언어를 선택하세요 (1: English, 2: 한국어) [1/2]: " LANG_CHOICE
    if [[ "${LANG_CHOICE}" == "2" ]]; then
        LANG_CHOICE="ko"
    else
        LANG_CHOICE="en"
    fi
}

print_banner() {
    say \
        "========================================================" \
        "========================================================"
    say \
        " BPI-F3 SD Card to eMMC Flasher ${SCRIPT_VERSION}" \
        " BPI-F3 SD 카드 -> eMMC 플래셔 ${SCRIPT_VERSION}"
    say \
        " Target board: Banana Pi BPI-F3 / SpacemiT K1" \
        " 대상 보드: Banana Pi BPI-F3 / SpacemiT K1"
    say \
        " Validated workflow host: openSUSE Tumbleweed on SD card" \
        " 검증 기준 호스트: SD 카드로 부팅한 openSUSE Tumbleweed"
    say \
        "========================================================" \
        "========================================================"
}

check_root() {
    [[ "${EUID}" -eq 0 ]] || die \
        "This script must be run as root." \
        "이 스크립트는 root 권한으로 실행해야 합니다."
}

check_commands() {
    need_cmd uname
    need_cmd wipefs
    need_cmd sgdisk
    need_cmd partprobe
    need_cmd losetup
    need_cmd dd
    need_cmd mount
    need_cmd umount
    need_cmd mountpoint
    need_cmd sed
    need_cmd sync
    need_cmd findmnt
    need_cmd lsblk
    need_cmd basename
    need_cmd seq
    need_cmd poweroff
}

check_platform() {
    local arch=""

    arch="$(uname -m)"
    if [[ "${arch}" != "riscv64" ]]; then
        confirm \
            "This machine is ${arch}, not riscv64. Continue anyway?" \
            "현재 시스템 아키텍처는 ${arch}이며 riscv64가 아닙니다. 계속하시겠습니까?" || exit 1
    fi

    if [[ ! -f /etc/os-release ]]; then
        confirm \
            "/etc/os-release is missing. Continue anyway?" \
            "/etc/os-release 파일이 없습니다. 계속하시겠습니까?" || exit 1
        return 0
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "opensuse-tumbleweed" && "${PRETTY_NAME:-}" != *"openSUSE Tumbleweed"* ]]; then
        confirm \
            "This does not look like openSUSE Tumbleweed (${PRETTY_NAME:-unknown}). Continue anyway?" \
            "이 시스템은 openSUSE Tumbleweed로 보이지 않습니다 (${PRETTY_NAME:-알 수 없음}). 계속하시겠습니까?" || exit 1
    fi
}

prompt_for_existing_path() {
    local candidate="$1"
    local kind="$2"
    local prompt_en="$3"
    local prompt_ko="$4"
    local reply=""

    while true; do
        if [[ "${kind}" == "dir" && -d "${candidate}" ]]; then
            printf '%s' "${candidate}"
            return 0
        fi

        if [[ "${kind}" == "file" && -f "${candidate}" ]]; then
            printf '%s' "${candidate}"
            return 0
        fi

        if [[ "${ASSUME_YES}" -eq 1 ]]; then
            if [[ "${kind}" == "dir" ]]; then
                die "Directory not found: ${candidate}" "디렉터리를 찾을 수 없습니다: ${candidate}"
            else
                die "File not found: ${candidate}" "파일을 찾을 수 없습니다: ${candidate}"
            fi
        fi

        if [[ "${LANG_CHOICE}" == "ko" ]]; then
            read -r -e -p "${prompt_ko} [${candidate}]: " reply
        else
            read -r -e -p "${prompt_en} [${candidate}]: " reply
        fi

        [[ -n "${reply}" ]] && candidate="${reply}"
    done
}

prepare_device_paths() {
    EMMC_ENV_PART="$(part_path "${EMMC_DEVICE}" 1)"
    EMMC_OPENSBI_PART="$(part_path "${EMMC_DEVICE}" 2)"
    EMMC_UBOOT_PART="$(part_path "${EMMC_DEVICE}" 3)"
    EMMC_BOOT_PART="$(part_path "${EMMC_DEVICE}" 4)"
    EMMC_ROOT_PART="$(part_path "${EMMC_DEVICE}" 5)"
    BOOT_PART_NAME="$(basename "${EMMC_BOOT_PART}")"
    ROOT_PART_NAME="$(basename "${EMMC_ROOT_PART}")"
}

verify_inputs() {
    local required_file=""
    local root_source=""
    local boot_source=""

    FIRMWARE_DIR="$(
        prompt_for_existing_path \
            "${FIRMWARE_DIR}" \
            "dir" \
            "Enter the Bianbu firmware directory" \
            "Bianbu 펌웨어 디렉터리를 입력하세요"
    )"

    OS_IMAGE="$(
        prompt_for_existing_path \
            "${OS_IMAGE}" \
            "file" \
            "Enter the openSUSE disk image path" \
            "openSUSE 디스크 이미지 경로를 입력하세요"
    )"

    [[ -b "${EMMC_DEVICE}" ]] || die \
        "Target eMMC device is missing: ${EMMC_DEVICE}" \
        "대상 eMMC 장치를 찾을 수 없습니다: ${EMMC_DEVICE}"

    [[ -b "${BOOT0_DEVICE}" ]] || die \
        "Target boot0 device is missing: ${BOOT0_DEVICE}" \
        "대상 boot0 장치를 찾을 수 없습니다: ${BOOT0_DEVICE}"

    for required_file in env.bin fw_dynamic.itb u-boot.itb bootinfo_emmc.bin FSBL.bin; do
        [[ -f "${FIRMWARE_DIR}/${required_file}" ]] || die \
            "Required firmware file is missing: ${FIRMWARE_DIR}/${required_file}" \
            "필수 펌웨어 파일이 없습니다: ${FIRMWARE_DIR}/${required_file}"
    done

    root_source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
    boot_source="$(findmnt -n -o SOURCE /boot 2>/dev/null || true)"

    if [[ -n "${root_source}" && "${root_source}" == "${EMMC_DEVICE}"* ]]; then
        die \
            "The running root filesystem is already on ${EMMC_DEVICE}. Refusing to wipe it." \
            "현재 실행 중인 루트 파일시스템이 이미 ${EMMC_DEVICE} 위에 있습니다. 삭제를 중단합니다."
    fi

    if [[ -n "${boot_source}" && "${boot_source}" == "${EMMC_DEVICE}"* ]]; then
        die \
            "The running boot filesystem is already on ${EMMC_DEVICE}. Refusing to wipe it." \
            "현재 실행 중인 부트 파일시스템이 이미 ${EMMC_DEVICE} 위에 있습니다. 삭제를 중단합니다."
    fi
}

print_summary() {
    printf '\n'
    say "Input summary:" "입력 요약:"
    say "  Firmware directory: ${FIRMWARE_DIR}" "  펌웨어 디렉터리: ${FIRMWARE_DIR}"
    say "  OS image: ${OS_IMAGE}" "  OS 이미지: ${OS_IMAGE}"
    say "  Target eMMC device: ${EMMC_DEVICE}" "  대상 eMMC 장치: ${EMMC_DEVICE}"
    say "  Target boot0 device: ${BOOT0_DEVICE}" "  대상 boot0 장치: ${BOOT0_DEVICE}"
    printf '\n'
}

unmount_target_partitions() {
    local device=""
    local mountpoint_path=""

    while read -r device mountpoint_path; do
        [[ -n "${mountpoint_path}" ]] || continue
        umount "${device}" || die \
            "Could not unmount ${device} from ${mountpoint_path}" \
            "${mountpoint_path} 에서 ${device} 를 언마운트할 수 없습니다."
    done < <(lsblk -nrpo NAME,MOUNTPOINT "${EMMC_DEVICE}" 2>/dev/null || true)
}

wait_for_block_device() {
    local device="$1"
    local attempt=0

    for attempt in $(seq 1 15); do
        [[ -b "${device}" ]] && return 0
        sleep 1
    done

    die "Block device did not appear: ${device}" "블록 장치가 나타나지 않았습니다: ${device}"
}

partition_emmc() {
    say \
        "[1/5] Wiping and repartitioning ${EMMC_DEVICE}..." \
        "[1/5] ${EMMC_DEVICE} 를 초기화하고 파티션을 다시 만듭니다..."

    unmount_target_partitions

    wipefs -a "${EMMC_DEVICE}"
    sgdisk --zap-all "${EMMC_DEVICE}"
    sgdisk -o "${EMMC_DEVICE}"
    sgdisk -a 1 -n 1:768:895 -c 1:env "${EMMC_DEVICE}"
    sgdisk -a 1 -n 2:2048:4095 -c 2:opensbi "${EMMC_DEVICE}"
    sgdisk -a 1 -n 3:4096:8191 -c 3:uboot "${EMMC_DEVICE}"
    sgdisk -a 1 -n 4:8192:532479 -c 4:bootfs "${EMMC_DEVICE}"
    sgdisk -a 1 -n 5:532480:0 -c 5:rootfs "${EMMC_DEVICE}"
    partprobe "${EMMC_DEVICE}"

    if command -v udevadm >/dev/null 2>&1; then
        udevadm settle
    else
        sleep 2
    fi

    wait_for_block_device "${EMMC_ENV_PART}"
    wait_for_block_device "${EMMC_OPENSBI_PART}"
    wait_for_block_device "${EMMC_UBOOT_PART}"
    wait_for_block_device "${EMMC_BOOT_PART}"
    wait_for_block_device "${EMMC_ROOT_PART}"
}

flash_bootloaders() {
    say \
        "[2/5] Flashing env, OpenSBI, and U-Boot partitions..." \
        "[2/5] env, OpenSBI, U-Boot 파티션을 기록합니다..."

    dd if="${FIRMWARE_DIR}/env.bin" of="${EMMC_ENV_PART}" conv=fsync status=none
    dd if="${FIRMWARE_DIR}/fw_dynamic.itb" of="${EMMC_OPENSBI_PART}" conv=fsync status=none
    dd if="${FIRMWARE_DIR}/u-boot.itb" of="${EMMC_UBOOT_PART}" conv=fsync status=none
}

copy_os_image() {
    local loop_boot_part=""
    local loop_root_part=""

    say \
        "[3/5] Copying boot and root partitions from the openSUSE image..." \
        "[3/5] openSUSE 이미지에서 boot와 root 파티션을 복사합니다..."

    LOOP_DEVICE="$(losetup -P -f --show "${OS_IMAGE}")"
    loop_boot_part="$(part_path "${LOOP_DEVICE}" 1)"
    loop_root_part="$(part_path "${LOOP_DEVICE}" 2)"

    wait_for_block_device "${loop_boot_part}"
    wait_for_block_device "${loop_root_part}"

    dd if="${loop_boot_part}" of="${EMMC_BOOT_PART}" bs=4M conv=fsync status=progress
    dd if="${loop_root_part}" of="${EMMC_ROOT_PART}" bs=4M conv=fsync status=progress

    losetup -d "${LOOP_DEVICE}"
    LOOP_DEVICE=""
}

rewrite_partition_reference_file() {
    local file="$1"

    [[ -f "${file}" ]] || return 0

    sed -i \
        -e "s#/dev/mmcblk0p1#/dev/${BOOT_PART_NAME}#g" \
        -e "s#/dev/mmcblk1p1#/dev/${BOOT_PART_NAME}#g" \
        -e "s#/dev/mmcblk0p2#/dev/${ROOT_PART_NAME}#g" \
        -e "s#/dev/mmcblk1p2#/dev/${ROOT_PART_NAME}#g" \
        -e "s#mmcblk0p1#${BOOT_PART_NAME}#g" \
        -e "s#mmcblk1p1#${BOOT_PART_NAME}#g" \
        -e "s#mmcblk0p2#${ROOT_PART_NAME}#g" \
        -e "s#mmcblk1p2#${ROOT_PART_NAME}#g" \
        "${file}"
}

rewrite_storage_references() {
    say \
        "[4/5] Rewriting boot and root references from SD card to eMMC..." \
        "[4/5] boot/root 참조를 SD 카드에서 eMMC로 바꿉니다..."

    mkdir -p "${BOOT_MOUNT}" "${ROOT_MOUNT}"
    mount "${EMMC_BOOT_PART}" "${BOOT_MOUNT}"
    mount "${EMMC_ROOT_PART}" "${ROOT_MOUNT}"

    rewrite_partition_reference_file "${BOOT_MOUNT}/env_k1-x.txt"
    rewrite_partition_reference_file "${BOOT_MOUNT}/armbianEnv.txt"
    rewrite_partition_reference_file "${ROOT_MOUNT}/etc/fstab"

    sync
    umount "${ROOT_MOUNT}"
    umount "${BOOT_MOUNT}"
}

flash_boot0() {
    local force_ro_path=""

    say \
        "[5/5] Writing bootinfo and FSBL into ${BOOT0_DEVICE}..." \
        "[5/5] ${BOOT0_DEVICE} 에 bootinfo 와 FSBL 을 기록합니다..."

    force_ro_path="/sys/block/$(basename "${BOOT0_DEVICE}")/force_ro"
    [[ -w "${force_ro_path}" ]] || die \
        "force_ro is not writable: ${force_ro_path}" \
        "force_ro 를 쓸 수 없습니다: ${force_ro_path}"

    printf '0\n' > "${force_ro_path}"
    dd if="${FIRMWARE_DIR}/bootinfo_emmc.bin" of="${BOOT0_DEVICE}" bs=512 seek=0 conv=fsync status=none
    dd if="${FIRMWARE_DIR}/FSBL.bin" of="${BOOT0_DEVICE}" bs=512 seek=1 conv=fsync status=none
}

show_final_layout() {
    printf '\n'
    say "Final partition layout:" "최종 파티션 레이아웃:"
    lsblk -o NAME,SIZE,TYPE,LABEL "${EMMC_DEVICE}"
    printf '\n'
}

finalize() {
    say \
        "Flashing completed successfully." \
        "플래싱이 성공적으로 완료되었습니다."
    say \
        "After shutdown, remove the SD card and power the board back on to boot from eMMC." \
        "시스템이 종료되면 SD 카드를 제거한 뒤 전원을 다시 넣어 eMMC로 부팅하세요."

    if [[ "${POWER_OFF_WHEN_DONE}" -eq 1 ]]; then
        say \
            "Powering off in 5 seconds..." \
            "5초 후 시스템 전원을 끕니다..."
        sync
        sleep 5
        poweroff
    else
        say \
            "Automatic poweroff was skipped by request." \
            "요청에 따라 자동 전원 종료를 생략했습니다."
    fi
}

main() {
    parse_args "$@"
    select_language
    check_root
    prepare_device_paths
    print_banner
    check_commands
    check_platform
    verify_inputs
    prepare_device_paths
    print_summary

    confirm \
        "Start flashing now? All data on ${EMMC_DEVICE} will be permanently erased." \
        "지금 플래싱을 시작하시겠습니까? ${EMMC_DEVICE} 의 모든 데이터는 영구적으로 삭제됩니다." || die \
        "Operation aborted." \
        "작업을 중단했습니다."

    partition_emmc
    flash_bootloaders
    copy_os_image
    rewrite_storage_references
    flash_boot0
    show_final_layout
    finalize
}

main "$@"
