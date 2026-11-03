#!/bin/sh

set -eu

BASE_URL="${IFB_BASE_URL:-https://jcwang12345.github.io/immortalwrt-25.12-apk}"
PUBLIC_KEY_URL="${IFB_PUBLIC_KEY_URL:-${BASE_URL}/keys/ifb-repository.pem}"
PUBLIC_KEY_SHA256="${IFB_PUBLIC_KEY_SHA256:-771f11260b4e68d799dee7220b41cdda5eea04daa591b6b97f53740f4c54e249}"
KEYS_DIR="${IFB_KEYS_DIR:-/etc/apk/keys}"
REPOSITORY_FILE="${IFB_REPOSITORY_FILE:-/etc/apk/repositories.d/ifb-community.list}"
KEY_NAME="ifb-repository.pem"

DRY_RUN=0
INSTALL_IFB=0

usage() {
    cat <<'EOF'
Usage: sh install-feed.sh [--dry-run] [--install-ifb]

  --dry-run      Detect architecture and kernel ABI, then print the selected
                 repositories without changing the system.
  --install-ifb  After configuring and validating the repository, install
                 kmod-ifb, kmod-sched-core, and tc-full.

The script refuses unknown kernel ABIs and never enables untrusted packages.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --install-ifb)
            INSTALL_IFB=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unsupported argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

command -v apk >/dev/null 2>&1 || {
    echo "apk was not found; this repository is for ImmortalWrt 25.12 apk-based firmware." >&2
    exit 1
}

ARCH="$(apk --print-arch 2>/dev/null | sed -n '1p')"
KERNEL_PACKAGE="$(apk list --installed kernel 2>/dev/null | sed -n '1p' || true)"
if [ -z "$KERNEL_PACKAGE" ]; then
    KERNEL_PACKAGE="$(apk info -a kernel 2>/dev/null | sed -n '1s/ description:$//p' || true)"
fi

if [ -z "$ARCH" ] || [ -z "$KERNEL_PACKAGE" ]; then
    echo "Unable to determine apk architecture or the installed kernel package." >&2
    exit 1
fi

PROFILE=""
KMOD_URL=""
BASE_REPOSITORY_URL=""

case "${ARCH}:${KERNEL_PACKAGE}" in
    aarch64_cortex-a53:*6.12.103~ea0eb633dd9ac6371d586d3dcebb0c62-r1*)
        PROFILE="mediatek-filogic-openclash"
        KMOD_URL="${BASE_URL}/targets/mediatek/filogic/kmods/6.12.103-1-ea0eb633dd9ac6371d586d3dcebb0c62/packages.adb"
        BASE_REPOSITORY_URL="${BASE_URL}/packages/aarch64_cortex-a53/base/packages.adb"
        ;;
    aarch64_cortex-a53:*6.12.103~f401babd18fa21dc0692b98851aed338-r1*)
        PROFILE="mediatek-filogic-passwall-archive"
        KMOD_URL="${BASE_URL}/targets/mediatek/filogic/kmods/6.12.103-1-f401babd18fa21dc0692b98851aed338/packages.adb"
        BASE_REPOSITORY_URL="${BASE_URL}/packages/aarch64_cortex-a53/base/packages.adb"
        ;;
    x86_64:*6.12.103~5100077a5b88e89ca777287688c85889-r1*)
        PROFILE="x86-64-dual"
        KMOD_URL="${BASE_URL}/targets/x86/64/kmods/6.12.103-1-5100077a5b88e89ca777287688c85889/packages.adb"
        BASE_REPOSITORY_URL="${BASE_URL}/packages/x86_64/base/packages.adb"
        ;;
    *)
        echo "Unsupported kernel ABI; no files were changed." >&2
        echo "Architecture: ${ARCH}" >&2
        echo "Kernel package: ${KERNEL_PACKAGE}" >&2
        echo "Do not force-install a kmod built for another ABI." >&2
        exit 1
        ;;
esac

echo "Detected architecture: ${ARCH}"
echo "Detected kernel: ${KERNEL_PACKAGE}"
echo "Selected profile: ${PROFILE}"
echo "Selected kmods index: ${KMOD_URL}"
echo "Selected base index: ${BASE_REPOSITORY_URL}"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run complete; no files were changed."
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    case "${KEYS_DIR}:${REPOSITORY_FILE}" in
        /etc/*|*:/etc/*)
            echo "Run this script as root to configure apk repositories." >&2
            exit 1
            ;;
    esac
fi

TMP_DIR="$(mktemp -d /tmp/ifb-feed.XXXXXX)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

download_key() {
    destination="$1"
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$destination" "$PUBLIC_KEY_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$destination" "$PUBLIC_KEY_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$destination" "$PUBLIC_KEY_URL"
    else
        echo "No HTTPS downloader was found (uclient-fetch, wget, or curl)." >&2
        return 1
    fi
}

command -v sha256sum >/dev/null 2>&1 || {
    echo "sha256sum is required to verify the repository key." >&2
    exit 1
}

download_key "$TMP_DIR/$KEY_NAME"
ACTUAL_KEY_SHA256="$(sha256sum "$TMP_DIR/$KEY_NAME" | awk '{print $1}')"
if [ "$ACTUAL_KEY_SHA256" != "$PUBLIC_KEY_SHA256" ]; then
    echo "Repository public-key checksum mismatch; no files were changed." >&2
    exit 1
fi

mkdir -p "$KEYS_DIR" "$(dirname "$REPOSITORY_FILE")"

KEY_TARGET="$KEYS_DIR/$KEY_NAME"
HAD_KEY=0
HAD_REPOSITORY=0
[ ! -e "$KEY_TARGET" ] || {
    HAD_KEY=1
    cp "$KEY_TARGET" "$TMP_DIR/original-key"
}
[ ! -e "$REPOSITORY_FILE" ] || {
    HAD_REPOSITORY=1
    cp "$REPOSITORY_FILE" "$TMP_DIR/original-repository"
}

cp "$TMP_DIR/$KEY_NAME" "$KEY_TARGET"
chmod 0644 "$KEY_TARGET"
{
    echo "$KMOD_URL"
    echo "$BASE_REPOSITORY_URL"
} > "$TMP_DIR/repositories"
cp "$TMP_DIR/repositories" "${REPOSITORY_FILE}.new.$$"
chmod 0644 "${REPOSITORY_FILE}.new.$$"
mv "${REPOSITORY_FILE}.new.$$" "$REPOSITORY_FILE"

if ! apk update; then
    echo "apk update failed; restoring the previous repository configuration." >&2
    if [ "$HAD_REPOSITORY" -eq 1 ]; then
        cp "$TMP_DIR/original-repository" "$REPOSITORY_FILE"
    else
        rm -f "$REPOSITORY_FILE"
    fi
    if [ "$HAD_KEY" -eq 1 ]; then
        cp "$TMP_DIR/original-key" "$KEY_TARGET"
    else
        rm -f "$KEY_TARGET"
    fi
    exit 1
fi

echo "Repository configured and signature index validation completed."

if [ "$INSTALL_IFB" -eq 1 ]; then
    apk add kmod-ifb kmod-sched-core tc-full
    echo "IFB packages installed."
else
    echo "Packages were not installed. Use --install-ifb when installation is required."
fi
