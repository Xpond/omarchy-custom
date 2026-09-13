# Package-owned shell files, sourced by install.sh and revert.sh (which set REPO and STATE).
# Pacman's checksums say what stock is; this checkout's patch history says what is ours.
PACKAGE_LOCAL=/var/lib/pacman/local
PACKAGE_CACHE=/var/cache/pacman/pkg
PACKAGE_DB=$(ls -d "$PACKAGE_LOCAL"/omarchy-[0-9]* 2>/dev/null | tail -n 1) || true

stock_sum() {
  [[ -n $PACKAGE_DB ]] || return 1
  zcat "$PACKAGE_DB/mtree" | awk -v path="./usr/share/omarchy/shell/$1" \
    '$1 == path { for (i = 2; i <= NF; i++) if ($i ~ /^sha256digest=/) print substr($i, 14) }'
}

is_stock() {
  local want
  want=$(stock_sum "$1") && [[ -n $want && -f $2 && $(sha256sum < "$2") == "$want  -" ]]
}

# An interrupted or recorded install, the current patch, or any committed version of it.
is_ours() {
  [[ -f $STATE/installed/$1.pending ]] || cmp -s "$2" "$STATE/installed/$1" ||
    cmp -s "$2" "$REPO/patches/shell/$1" ||
    [[ -n $(git -C "$REPO" log --all -1 --format=%h --find-object="$(git hash-object "$2" 2>/dev/null)" \
            -- "patches/shell/$1" 2>/dev/null) ]]
}

# Write verified stock bytes to $2: the checkout's merge base, else the cached package.
stock_copy() {
  local archive
  if is_stock "$1" "$REPO/patches/orig/$1"; then cp "$REPO/patches/orig/$1" "$2"; return; fi
  archive=$(ls "$PACKAGE_CACHE/${PACKAGE_DB##*/}"-*.pkg.tar.zst 2>/dev/null | head -n 1)
  [[ -n $archive ]] && bsdtar -xOf "$archive" "usr/share/omarchy/shell/$1" > "$2" 2>/dev/null &&
    is_stock "$1" "$2"
}
