#!/bin/bash
set -euo pipefail

# ============================================================
# Build a portable Ryujinx (bundled prodkeys + firmware)
# Usage: ./build.sh [version]   # defaults to DEFAULT_VERSION
# ============================================================

# Default version: prodkeys / firmware version bundled into the final archive
DEFAULT_VERSION='22.1.0'
TARGET_VERSION="${1:-$DEFAULT_VERSION}"

# All firmware / prodkeys versions: every one is downloaded and kept in dist/
VERSIONS=('19.0.1' '20.5.0' '21.0.0' '22.0.0' '22.1.0')

log() { echo "[build] $*"; }

# Map a firmware version to its prodkeys / firmware download URLs.
# Sets globals: prodkeys_url, firmware_url, prodkeys_zip, firmware_zip
resolve_urls() {
    local version="$1"
    case "$version" in
        19.0.1)
            prodkeys_url="https://files.prodkeys.net/ProdKeys.net-v19.0.1.zip"
            firmware_url="https://github.com/THZoria/NX_Firmware/releases/download/19.0.1/Firmware.19.0.1.zip"
            ;;
        20.5.0)
            prodkeys_url="https://files.prodkeys.net/ProdKeys.NET-v20.5.0.zip"
            firmware_url="https://github.com/THZoria/NX_Firmware/releases/download/20.5.0/Firmware.20.5.0.zip"
            ;;
        21.0.0)
            prodkeys_url="https://files.prodkeys.net/Prodkeys.NET_v21-0-0.zip"
            firmware_url="https://github.com/THZoria/NX_Firmware/releases/download/21.0.0/Firmware.21.0.0.zip"
            ;;
        22.0.0)
            prodkeys_url="https://files.prodkeys.net/ProdKeys.NET-v22.0.0.zip"
            firmware_url="https://github.com/THZoria/NX_Firmware/releases/download/22.0.0/Firmware.22.0.0.zip"
            ;;
        22.1.0)
            prodkeys_url="https://files.prodkeys.net/ProdKeys.NET-v22.1.0.zip"
            firmware_url="https://github.com/THZoria/NX_Firmware/releases/download/22.1.0/Firmware.22.1.0.zip"
            ;;
        *)
            echo "ERROR: unsupported version '$version' (supported: ${VERSIONS[*]})" >&2
            exit 1
            ;;
    esac
    prodkeys_zip="${prodkeys_url##*/}"
    firmware_zip="${firmware_url##*/}"
}

# ---------- 1. Resolve the latest Ryujinx version ----------
releases_url="https://git.ryujinx.app/api/v1/repos/projects/Ryubing/releases/latest"

# The endpoint returns a SINGLE object (not an array), so read .tag_name
# directly. The win_x64 asset URL comes straight from the API response so
# the filename always matches what the server actually hosts.
json=$(curl -sf -H "User-Agent: Bash" "$releases_url")
latest_tag=$(jq -r '.tag_name' <<< "$json")
filename=$(jq -r '.assets[] | select(.name | contains("win_x64")) | .name' <<< "$json")
download_url=$(jq -r '.assets[] | select(.name | contains("win_x64")) | .browser_download_url' <<< "$json")

if [[ -z "$latest_tag" || "$latest_tag" == "null" \
    || -z "$filename" || "$filename" == "null" \
    || -z "$download_url" || "$download_url" == "null" ]]; then
    echo "ERROR: could not resolve the latest release" >&2
    exit 1
fi
log "latest Ryujinx tag: $latest_tag"

# ---------- 2. Download all firmwares / prodkeys ----------
# Every zip stays in dist/: the CI release step publishes all dist/*.zip
# as release assets, so they are kept intentionally.
resolve_urls "$TARGET_VERSION"   # fail fast on an unsupported version
log "target prodkeys / firmware version: $TARGET_VERSION"
mkdir -p dist
for version in "${VERSIONS[@]}"; do
    resolve_urls "$version"
    log "downloading prodkeys ($version): $prodkeys_zip"
    curl -fL --retry 3 -o "dist/$prodkeys_zip" "$prodkeys_url"
    log "downloading firmware ($version): $firmware_zip"
    curl -fL --retry 3 -o "dist/$firmware_zip" "$firmware_url"
done

# ---------- 3. Re-zip prodkeys with a flat layout ----------
# Upstream prodkeys zips may nest the keys in subfolders (e.g. Keys-22.1.0/),
# which breaks flat globs later in the build. Re-zip each one so every key
# file sits at the archive root; the flattened zip replaces the original
# under the same name in dist/.
for version in "${VERSIONS[@]}"; do
    resolve_urls "$version"
    log "re-zipping $prodkeys_zip (flat layout)"
    rm -rf rezip_tmp
    mkdir -p rezip_tmp
    unzip -q "dist/$prodkeys_zip" -d rezip_tmp
    (cd rezip_tmp \
        && find . -type f -exec mv -f {} . \; \
        && find . -type d -empty -delete)
    (cd rezip_tmp && zip -r -q -X "../dist/$prodkeys_zip.tmp" .)
    mv -f "dist/$prodkeys_zip.tmp" "dist/$prodkeys_zip"
    rm -rf rezip_tmp
done

# ---------- 4. Download Ryujinx ----------
log "downloading Ryujinx: $filename"
curl -fL --retry 3 -o "dist/$filename" "$download_url"

# ---------- 5. Extract ----------
resolve_urls "$TARGET_VERSION"
rm -rf ryujinx ryujinx-win ProdKeys Firmware
unzip -q "dist/$prodkeys_zip" -d ProdKeys
unzip -q "dist/$firmware_zip" -d Firmware
unzip -q "dist/$filename" -d ryujinx-win

mv ./ryujinx-win/publish ./ryujinx
mkdir -p ./ryujinx/portable

# ---------- 6. First run to generate the portable config ----------
cd ryujinx
# On Linux, wine is required (wine ./Ryujinx.exe &)
if command -v wine >/dev/null 2>&1; then
    wine ./Ryujinx.exe &
else
    ./Ryujinx.exe &
fi
pid=$!
sleep 10
kill "$pid" 2>/dev/null || true

# ---------- 7. Install prodkeys / firmware ----------
system_dir="./portable/system"
registered_dir="./portable/bis/system/Contents/registered"
mkdir -p "$system_dir" "$registered_dir"

# Prodkeys zips may nest the keys in subfolders (e.g. Keys-22.1.0/),
# so find *.keys recursively instead of assuming a flat layout.
find ../ProdKeys -name '*.keys' -type f -exec cp -f {} "$system_dir/" \;

# Same for firmware: copy every .nca regardless of any nesting.
find ../Firmware -name '*.nca' -type f -exec cp -f {} "$registered_dir/" \;

# Reorganize firmware NCAs into the <id>.nca/00 layout Ryujinx expects
# for installed firmware titles.
#
# Why move each file away FIRST? Firmware ships BOTH <id>.nca and
# <id>.cnmt.nca for the same title. If we created <id>.nca/ while the
# plain <id>.nca file still exists, mkdir would fail with "File exists"
# (a file and a folder cannot share the same name). Relocating the file
# to a hidden temp name first sidesteps that entirely.
# .nca_tmp is safe to reuse every iteration: real NCA names always end
# in ".nca", so the temp name can never collide with an actual file.
cd "$registered_dir"
for file in *; do
    nca=$(basename "$file")

    # Derive the title ID from the NCA filename:
    #   <id>.cnmt.nca  ->  <id>   (control metadata; strip ".cnmt")
    #   <id>.nca       ->  <id>   (regular content; strip ".nca")
    # Anything else (subfolders, non-NCA files) is skipped.
    if [[ $nca == *.cnmt.nca ]]; then
        xxx=${nca%.cnmt.nca}
    elif [[ $nca == *.nca ]]; then
        xxx=${nca%.nca}
    else
        continue
    fi

    # 1. Move the file out of the way (prevents the mkdir collision above)
    mv "$file" ".nca_tmp"
    # 2. Create the per-title folder
    mkdir -p "$xxx.nca"
    # 3. Move the file into place as "00" (the content index inside a title)
    mv ".nca_tmp" "$xxx.nca/00"
done
cd - >/dev/null

# ---------- 8. Tweak the config ----------
config="./portable/Config.json"
sed -i 's/"game_dirs": \[\]/"game_dirs": ["portable\/games"]/g' "$config"
sed -i 's/"graphics_backend": "[^"]*"/"graphics_backend": "Vulkan"/g' "$config"

# ---------- 9. Repack ----------
cd ..
rm -f "dist/$filename"
(cd ryujinx && zip -r -q "../dist/$filename" .)
ls -lh dist

# ---------- 10. Output GitHub Actions variables ----------
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "tag=$latest_tag" >> "$GITHUB_OUTPUT"
fi

log "done: dist/$filename"
