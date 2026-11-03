#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/install-feed.sh"
KEY="$ROOT/keys/ifb-repository.pem"
EXPECTED_KEY_SHA="771f11260b4e68d799dee7220b41cdda5eea04daa591b6b97f53740f4c54e249"
TEST_ROOT="$(mktemp -d /tmp/test-ifb-feed.XXXXXX)"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

make_apk_stub() {
    directory="$1"
    architecture="$2"
    kernel_package="$3"
    update_status="$4"
    mkdir -p "$directory"
    cat > "$directory/apk" <<EOF
#!/bin/sh
case "\$1" in
    --print-arch)
        echo '$architecture'
        ;;
    info)
        echo '$kernel_package'
        ;;
    list)
        echo '$kernel_package $architecture {feeds/base/kernel/linux} (GPL-2.0-only) [installed]'
        ;;
    update)
        exit '$update_status'
        ;;
    add)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$directory/apk"
}

assert_contains() {
    value="$1"
    expected="$2"
    echo "$value" | grep -F "$expected" >/dev/null || {
        echo "Missing expected text: $expected" >&2
        exit 1
    }
}

run_dry_case() {
    name="$1"
    architecture="$2"
    kernel_package="$3"
    expected="$4"
    bin="$TEST_ROOT/$name/bin"
    make_apk_stub "$bin" "$architecture" "$kernel_package" 0
    output="$(PATH="$bin:$PATH" sh "$SCRIPT" --dry-run)"
    assert_contains "$output" "$expected"
    assert_contains "$output" "no files were changed"
}

run_dry_case arm-openclash aarch64_cortex-a53 \
    kernel-6.12.103~ea0eb633dd9ac6371d586d3dcebb0c62-r1 \
    mediatek-filogic-openclash
run_dry_case arm-passwall aarch64_cortex-a53 \
    kernel-6.12.103~f401babd18fa21dc0692b98851aed338-r1 \
    mediatek-filogic-passwall-archive
run_dry_case x86 x86_64 \
    kernel-6.12.103~5100077a5b88e89ca777287688c85889-r1 \
    x86-64-dual

unknown_bin="$TEST_ROOT/unknown/bin"
make_apk_stub "$unknown_bin" aarch64_cortex-a53 kernel-6.12.103~unknown-r1 0
if PATH="$unknown_bin:$PATH" sh "$SCRIPT" --dry-run >"$TEST_ROOT/unknown.out" 2>"$TEST_ROOT/unknown.err"; then
    echo "Unknown ABI was accepted" >&2
    exit 1
fi
grep -F "Unsupported kernel ABI" "$TEST_ROOT/unknown.err" >/dev/null

apply_root="$TEST_ROOT/apply"
apply_bin="$apply_root/bin"
make_apk_stub "$apply_bin" aarch64_cortex-a53 \
    kernel-6.12.103~ea0eb633dd9ac6371d586d3dcebb0c62-r1 0
mkdir -p "$apply_root/keys" "$apply_root/repositories.d"
PATH="$apply_bin:$PATH" \
IFB_PUBLIC_KEY_URL="file://$KEY" \
IFB_PUBLIC_KEY_SHA256="$EXPECTED_KEY_SHA" \
IFB_KEYS_DIR="$apply_root/keys" \
IFB_REPOSITORY_FILE="$apply_root/repositories.d/ifb-community.list" \
    sh "$SCRIPT" >"$apply_root/output"
cmp "$KEY" "$apply_root/keys/ifb-repository.pem"
grep -F '/targets/mediatek/filogic/kmods/6.12.103-1-ea0eb633dd9ac6371d586d3dcebb0c62/packages.adb' \
    "$apply_root/repositories.d/ifb-community.list" >/dev/null

rollback_root="$TEST_ROOT/rollback"
rollback_bin="$rollback_root/bin"
make_apk_stub "$rollback_bin" aarch64_cortex-a53 \
    kernel-6.12.103~ea0eb633dd9ac6371d586d3dcebb0c62-r1 1
mkdir -p "$rollback_root/keys" "$rollback_root/repositories.d"
echo old-key > "$rollback_root/keys/ifb-repository.pem"
echo old-repository > "$rollback_root/repositories.d/ifb-community.list"
if PATH="$rollback_bin:$PATH" \
    IFB_PUBLIC_KEY_URL="file://$KEY" \
    IFB_PUBLIC_KEY_SHA256="$EXPECTED_KEY_SHA" \
    IFB_KEYS_DIR="$rollback_root/keys" \
    IFB_REPOSITORY_FILE="$rollback_root/repositories.d/ifb-community.list" \
        sh "$SCRIPT" >"$rollback_root/output" 2>"$rollback_root/error"; then
    echo "Failed apk update was accepted" >&2
    exit 1
fi
grep -Fx old-key "$rollback_root/keys/ifb-repository.pem" >/dev/null
grep -Fx old-repository "$rollback_root/repositories.d/ifb-community.list" >/dev/null

echo "install-feed tests passed"
