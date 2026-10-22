#!/usr/bin/env bash
# Vendor the current Debian ELTS source package of a PHP branch.
#
#   bin/update.sh <branch>            fetch, verify and write <branch>/
#   bin/update.sh --verify <branch>   re-verify and compare with <branch>/
#   bin/update.sh --latest <branch>   print the version ELTS currently ships
#
# Chain of trust, every link checked here:
#   keys/elts-archive.asc, fingerprint pinned below
#     signs dists/<suite>/InRelease,
#     which pins the SHA-256 of main/source/Sources.gz,
#     which pins the SHA-256 of the .dsc, .debian.tar.xz and .orig.tar.xz;
#   and the .orig.tar.xz must be the release tarball php.net publishes.
set -euo pipefail

ELTS_MIRROR=${ELTS_MIRROR:-https://deb.freexian.com/extended-lts}
ELTS_KEY_FINGERPRINT=AB597C4F6F3380BD4B2BEBC2A07310D369055D5A

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

die() {
	echo "update: $*" >&2
	exit 1
}

fetch() {
	curl -fsSL --retry 3 -o "$2" "$1" || die "cannot fetch $1"
}

mode=update
case ${1:-} in
--verify | --latest)
	mode=${1#--}
	shift
	;;
esac
[ $# -eq 1 ] || die "usage: $0 [--verify|--latest] <branch>"
branch=$1

case $branch in
7.0) suite=stretch-lts ;;
7.3) suite=buster-lts ;;
7.4) suite=bullseye-lts ;;
*) die "unknown branch: $branch" ;;
esac
package=php$branch

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME=$work/gnupg
mkdir -m 700 "$GNUPGHOME"

# --- archive key -> InRelease -> Sources -----------------------------------

fingerprint=$(gpg --batch --show-keys --with-colons "$root/keys/elts-archive.asc" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
[ "$fingerprint" = "$ELTS_KEY_FINGERPRINT" ] ||
	die "keys/elts-archive.asc has fingerprint $fingerprint, expected $ELTS_KEY_FINGERPRINT"
gpg --batch --dearmor <"$root/keys/elts-archive.asc" >"$work/keyring.gpg" 2>/dev/null

fetch "$ELTS_MIRROR/dists/$suite/InRelease" "$work/InRelease"
gpgv --keyring "$work/keyring.gpg" --output "$work/Release" "$work/InRelease" 2>"$work/gpgv.log" ||
	die "InRelease of $suite: bad signature: $(cat "$work/gpgv.log")"

sources_sha=$(awk '/^SHA256:/ { on = 1; next } /^[^ ]/ { on = 0 } on && $3 == "main/source/Sources.gz" { print $1 }' "$work/Release")
[ -n "$sources_sha" ] || die "InRelease of $suite does not list main/source/Sources.gz"
fetch "$ELTS_MIRROR/dists/$suite/main/source/Sources.gz" "$work/Sources.gz"
echo "$sources_sha  $work/Sources.gz" | sha256sum -c --quiet - || die "Sources.gz of $suite: checksum mismatch"

zcat "$work/Sources.gz" | awk -v RS= -v pkg="$package" '$0 ~ "(^|\n)Package: " pkg "\n" { print; n++ } END { exit n != 1 }' >"$work/stanza" ||
	die "expected exactly one $package entry in $suite"

field() { awk -v f="$1" 'index($0, f ": ") == 1 { print substr($0, length(f) + 3); exit }' "$work/stanza"; }
sha256_of() { awk -v name="$1" '/^Checksums-Sha256:/ { on = 1; next } /^[^ ]/ { on = 0 } on && $3 == name { print $1 }' "$work/stanza"; }
file_like() { awk -v re="$1" '/^Checksums-Sha256:/ { on = 1; next } /^[^ ]/ { on = 0 } on && $3 ~ re { print $3 }' "$work/stanza"; }

version=$(field Version)
if [ "$mode" = latest ]; then
	echo "$version"
	exit 0
fi

upstream=${version%%-*}
directory=$(field Directory)
dsc=$(file_like '[.]dsc$')
debian_tar=$(file_like '[.]debian[.]tar[.]xz$')
orig=$(file_like '[.]orig[.]tar[.]xz$')
if [ -z "$dsc" ] || [ -z "$debian_tar" ] || [ -z "$orig" ]; then
	die "$package $version: unexpected source format"
fi

# --- Sources -> source package files ---------------------------------------

for name in "$dsc" "$debian_tar" "$orig"; do
	fetch "$ELTS_MIRROR/$directory/${name//+/%2B}" "$work/$name"
	echo "$(sha256_of "$name")  $work/$name" | sha256sum -c --quiet - || die "$name: checksum mismatch"
done

release_sha=$(curl -fsSL --retry 3 "https://www.php.net/releases/index.php?json&version=$upstream" |
	jq -r --arg f "php-$upstream.tar.xz" '.source[] | select(.filename == $f) | .sha256')
[ "$release_sha" = "$(sha256_of "$orig")" ] ||
	die "$orig is not the php.net release tarball php-$upstream.tar.xz"

# --- patch series ------------------------------------------------------------

tar -xJf "$work/$debian_tar" -C "$work"
start=$(grep -v '^#' "$root/$branch/series-start" | head -n1)
awk -v first="$start" '/^#/ || !NF { next } $1 == first { on = 1 } on { print $1 }' \
	"$work/debian/patches/series" >"$work/series"
[ -s "$work/series" ] || die "series-start $start is not in the $version series"

mkdir "$work/src"
tar -xJf "$work/$orig" -C "$work/src" --strip-components=1
"$root/build/apply-series" "$work/src" "$work/debian/patches" "$work/series"
tree_sha=$("$root/build/tree-hash" "$work/src")

# --- write <branch>/ ---------------------------------------------------------

if [ "$mode" = verify ]; then
	dest=$work/out
else
	dest=$root/$branch
fi
mkdir -p "$dest"
rm -rf "$dest/elts"
mkdir "$dest/elts"
cp "$work/$dsc" "$work/$debian_tar" "$dest/elts/"
cp "$work/series" "$dest/series"

# Regression tests the series adds or changes; build/cve-tests runs them.
while read -r patch; do
	cat "$work/debian/patches/$patch"
done <"$work/series" |
	awk '/^\+\+\+ / { sub(/^[^\/]*\//, "", $2); print $2 }' |
	{ grep '[.]phpt$' || :; } | LC_ALL=C sort -u |
	while read -r test; do
		if [ -f "$work/src/$test" ]; then echo "$test"; fi
	done >"$dest/cve-tests"

cat >"$dest/elts.env" <<EOF
# Generated by bin/update.sh from $suite. Do not edit.
PACKAGE='$package'
SUITE='$suite'
DEBIAN_VERSION='$version'
PHP_VERSION='$upstream'
DSC='$dsc'
DSC_SHA256='$(sha256_of "$dsc")'
DEBIAN_TAR='$debian_tar'
DEBIAN_TAR_SHA256='$(sha256_of "$debian_tar")'
ORIG='$orig'
ORIG_SHA256='$(sha256_of "$orig")'
ORIG_URL='$ELTS_MIRROR/$directory/${orig//+/%2B}'
TREE_SHA256='$tree_sha'
EOF

# Security fixes per Debian revision of this upstream version, from the changelog.
{
	cat <<EOF
# PHP $branch security fixes

Fixes that Debian ELTS backported to PHP $upstream, newest first. Every
image tagged \`$upstream-*\` contains all of them up to its Debian revision.

Generated by \`bin/update.sh\` from \`debian/changelog\` of \`$package $version\`.

| Debian revision | Date | Fixes |
| --- | --- | --- |
EOF
	awk -v up="$upstream" '
		/^[^ ].* \(.*\) / {
			ver = $2; gsub(/[()]/, "", ver)
			mine = index(ver, up "-") == 1
			ids = ""; delete seen
			next
		}
		!mine { next }
		/^ -- / {
			date = $0; sub(/.*>  /, "", date)
			printf "%s\t%s\t%s\n", ver, date, ids
			next
		}
		{
			line = $0
			while (match(line, /(CVE-[0-9]+-[0-9]+|GHSA-[a-z0-9]+-[a-z0-9]+-[a-z0-9]+)/)) {
				id = substr(line, RSTART, RLENGTH)
				if (!(id in seen)) { seen[id] = 1; ids = ids (ids == "" ? "" : " ") id }
				line = substr(line, RSTART + RLENGTH)
			}
		}
	' "$work/debian/changelog" |
		while IFS=$'\t' read -r ver date ids; do
			links=
			for id in $ids; do
				case $id in
				CVE-*) url=https://security-tracker.debian.org/tracker/$id ;;
				GHSA-*) url=https://github.com/php/php-src/security/advisories/$id ;;
				esac
				links+="${links:+, }[$id]($url)"
			done
			echo "| $ver | $(date -ud "$date" +%F) | ${links:-bug fixes} |"
		done
} >"$dest/FIXES.md"

if [ "$mode" = verify ]; then
	for f in elts series cve-tests elts.env FIXES.md; do
		diff -r "$root/$branch/$f" "$dest/$f" >/dev/null || die "$branch/$f differs from $package $version in $suite"
	done
	echo "$branch: $package $version verified against $suite"
else
	echo "$branch: $package $version, $(wc -l <"$dest/series") patches, $(wc -l <"$dest/cve-tests") tests"
fi
