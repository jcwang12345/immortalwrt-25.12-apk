# ImmortalWrt 25.12 V19 IFB APK Repository

Signed apk-tools v3 repository for `kmod-ifb`, `kmod-sched-core`, and `tc-full`.

## Usage

### Automatic configuration (recommended)

The installer reads the actual apk architecture and installed kernel ABI,
selects exactly one matching kmods index, verifies the dedicated repository
public key, writes its own repository file, and runs `apk update`:

```sh
wget -O /tmp/install-feed.sh https://jcwang12345.github.io/immortalwrt-25.12-apk/install-feed.sh
sh /tmp/install-feed.sh --dry-run
sh /tmp/install-feed.sh
```

Add `--install-ifb` to the final command only when the packages also need to be
installed. Unknown ABIs are rejected without changing the router. The script
does not use `--allow-untrusted` or any force-install option.

### Manual configuration

1. Check the installed kernel package/ABI:

   ```sh
   apk info kernel
   ```

2. Add **one matching kmods URL** from `compatibility.json`, plus the base URL for your architecture, to:

   ```text
   /etc/apk/repositories.d/customfeeds.list
   ```

3. Update and install:

   ```sh
   apk update
   apk add kmod-ifb kmod-sched-core tc-full
   ```

Before adding this repository for the first time, install its dedicated public key and verify the fingerprint:

```sh
wget -O /tmp/ifb-repository.pem https://jcwang12345.github.io/immortalwrt-25.12-apk/keys/ifb-repository.pem
echo "771f11260b4e68d799dee7220b41cdda5eea04daa591b6b97f53740f4c54e249  /tmp/ifb-repository.pem" | sha256sum -c -
cp /tmp/ifb-repository.pem /etc/apk/keys/ifb-repository.pem
chmod 0644 /etc/apk/keys/ifb-repository.pem
```

The private repository key remains only on the compiler. Future firmware can preinstall this public key.

## Repository URLs

### aarch64_cortex-a53 base

```text
https://jcwang12345.github.io/immortalwrt-25.12-apk/packages/aarch64_cortex-a53/base/packages.adb
```

### x86_64 base

```text
https://jcwang12345.github.io/immortalwrt-25.12-apk/packages/x86_64/base/packages.adb
```

Exact kmod repository URLs and ABI values are listed in [`compatibility.json`](compatibility.json).

## Important

- Architecture alone is not sufficient for kernel modules; the full kernel ABI must match.
- The automatic installer selects by the installed kernel ABI, not by the OpenClash or PassWall service name.
- The older V19 ABI is intentionally not claimed compatible.
- No default traffic-shaping policy is installed by these packages.
- Q30 Pro firmware images are separate from legacy Q30; this repository contains packages only.
