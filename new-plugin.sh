#!/usr/bin/env bash
# Copies this template into a new directory and fills in the plugin's name,
# id, vendor and so on:  ./new-plugin.sh [target-dir]
#
# Works from a full clone, or as a lone downloaded file, in which case it
# fetches the template from GitHub first.
set -euo pipefail

TEMPLATE_REPO="${TEMPLATE_REPO:-YOUR_USER/zig-clap-template}"
TEMPLATE_BRANCH="${TEMPLATE_BRANCH:-main}"
TEMPLATE_URL="${TEMPLATE_URL:-https://github.com/$TEMPLATE_REPO/archive/refs/heads/$TEMPLATE_BRANCH.tar.gz}"

die() { echo "error: $*" >&2; exit 1; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$SRC/src/plugin.zig" ]]; then
    [[ "$TEMPLATE_URL" == *YOUR_USER* ]] && die "set TEMPLATE_REPO at the top of this script to your GitHub user/repo"
    command -v curl >/dev/null || die "curl is needed to download the template"
    SRC="$(mktemp -d)"
    trap 'rm -rf "$SRC"' EXIT
    echo "Downloading template from $TEMPLATE_URL"
    curl -fsSL "$TEMPLATE_URL" | tar -xz --strip-components=1 -C "$SRC" \
        || die "could not download the template"
fi

ask() { # ask VAR "Prompt" "default"
    local reply
    read -r -p "$2 [$3]: " reply || reply=""
    printf -v "$1" '%s' "${reply:-$3}"
}

# Escape a value for use on the right-hand side of sed s|..|..|.
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

echo "New CLAP plugin from zig-clap-template"
echo

ask NAME "Bundle/file name (letters and digits, e.g. MyReverb)" "MyPlugin"
[[ "$NAME" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die "name must be letters, digits or _, starting with a letter"

ask DISPLAY "Display name shown in the host" "$NAME"
ask VENDOR "Vendor" "Example"
slug="$(printf '%s' "$VENDOR" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9\n' '-' | sed 's/^-*//; s/-*$//')"
pslug="$(printf '%s' "$NAME" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
ask ID "Unique plugin id (reverse-DNS)" "com.${slug:-example}.${pslug}"
[[ "$ID" =~ ^[A-Za-z0-9._-]+$ ]] || die "id may only contain letters, digits, . _ -"
ask DESC "One-line description" "A CLAP plugin written in Zig"
ask URL "Vendor URL (may be empty)" ""
ask VERSION "Version" "0.1.0"
ask DEST "Create in directory" "${1:-$PWD/$pslug}"

[[ -e "$DEST" && -n "$(ls -A "$DEST" 2>/dev/null)" ]] && die "$DEST exists and is not empty"
mkdir -p "$DEST"

# Copy everything tracked by the template, minus git history, build output and
# this script's own bookkeeping.
(cd "$SRC" && tar --exclude=.git --exclude=build --exclude='*.dylib' --exclude='*.so' \
    --exclude=new-plugin.sh --exclude=README.md -cf - .) | (cd "$DEST" && tar -xf -)

sed -i.bak \
    -e "s|^\(    \.id = \).*|\1\"$(esc "$ID")\",|" \
    -e "s|^\(    \.name = \).*|\1\"$(esc "$DISPLAY")\",|" \
    -e "s|^\(    \.vendor = \).*|\1\"$(esc "$VENDOR")\",|" \
    -e "s|^\(    \.url = \).*|\1\"$(esc "$URL")\",|" \
    -e "s|^\(    \.version = \).*|\1\"$(esc "$VERSION")\",|" \
    -e "s|^\(    \.description = \).*|\1\"$(esc "$DESC")\",|" \
    "$DEST/src/clap_entry.zig"

sed -i.bak "s|^NAME     ?= .*|NAME     ?= $NAME|" "$DEST/Makefile"
sed -i.bak \
    -e "s|com\.example\.@NAME@|$(esc "$ID")|" \
    -e "s|<string>0\.1\.0</string>|<string>$(esc "$VERSION")</string>|" \
    "$DEST/Info.plist.in"
find "$DEST" -name '*.bak' -delete

cat > "$DEST/README.md" <<README
# $DISPLAY

$DESC

Built from zig-clap-template. Needs Zig 0.17 and make.

    make            # build/$NAME.clap
    make test       # unit tests for src/plugin.zig
    make install    # copy to your user CLAP folder

DSP lives in \`src/plugin.zig\`. The CLAP glue is in \`src/clap_entry.zig\`.
README

# Fail now, not on the first build, if a substitution missed.
grep -q "\"$(esc "$ID")\"" "$DEST/src/clap_entry.zig" || die "id substitution failed"
grep -q "^NAME     ?= $NAME\$" "$DEST/Makefile" || die "name substitution failed"

if command -v git >/dev/null; then
    (cd "$DEST" && git init -q && git add -A && git commit -q -m "Initial commit from zig-clap-template" 2>/dev/null) || true
fi

echo
echo "Created $DEST"
echo "  cd \"$DEST\" && make test && make"
