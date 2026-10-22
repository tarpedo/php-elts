# php-elts

[![build](https://github.com/tarpedo/php-elts/actions/workflows/build.yml/badge.svg)](https://github.com/tarpedo/php-elts/actions/workflows/build.yml)
[![license](https://img.shields.io/github/license/tarpedo/php-elts)](LICENSE)

PHP 7.3 and 7.4 Docker images that still get security fixes. Drop-in
replacements for the official `php` images:

```diff
- FROM php:7.4-fpm
+ FROM ghcr.io/tarpedo/php-elts:7.4-fpm
```

| | cli | fpm | apache |
| --- | --- | --- | --- |
| **7.4** | `ghcr.io/tarpedo/php-elts:7.4` | `ghcr.io/tarpedo/php-elts:7.4-fpm` | `ghcr.io/tarpedo/php-elts:7.4-apache` |
| **7.3** | `ghcr.io/tarpedo/php-elts:7.3` | `ghcr.io/tarpedo/php-elts:7.3-fpm` | `ghcr.io/tarpedo/php-elts:7.3-apache` |

`linux/amd64` and `linux/arm64`. Or [build them yourself](#build-it-yourself)
from this repository: nothing here has to be taken on trust.

## Why

PHP 7.3 reached end of life in December 2021 and PHP 7.4 in November 2022.
The official images stopped there. Every vulnerability found since is open in
them. Their Debian packages (openssl, glibc, libxml2, curl, …) got their last
security update from Debian on 31 August 2026, when bullseye's LTS ended, and
once bullseye moves to archive.debian.org, `apt-get` in those images stops
working altogether.

Debian keeps patching both versions. Its Extended LTS, run by
[Freexian](https://www.freexian.com/lts/extended/), backports security fixes
to `php7.3` and `php7.4`, and publishes them openly. This project builds those
sources into the official images.

## What you get

- **The original PHP plus Debian's fixes, nothing else.** The php.net release
  tarball with the security patches Debian ELTS publishes, applied unchanged:
  50+ CVEs per branch, listed in [7.4/FIXES.md](7.4/FIXES.md) and
  [7.3/FIXES.md](7.3/FIXES.md).
- **The official image underneath.** Same Debian release, entrypoint,
  configuration, paths and configure flags. `docker-php-ext-install` builds
  bundled extensions from the patched sources; `pecl` works as before.
- **Working, updated Debian packages.** The base image's packages (openssl,
  glibc, libxml2, curl, …) are upgraded from the Debian ELTS archive, which
  stays configured, so your own `apt-get install` works and gets updates.

Differences you may notice:

- 7.3 is PHP 7.3.31 plus backports: Debian never imported 7.3.32 and 7.3.33,
  it backported their two security fixes instead. `php -v` says 7.3.31.
- Security fixes added a few ini directives, such as `max_multipart_body_parts`.
  Existing directives keep their defaults.
- `PHP_ELTS_VERSION`, `/etc/php-elts-version` and `/usr/local/share/php-elts/`
  tell which Debian revision an image contains.
- PHP uses its bundled timezone database from the release, as in the official
  images. Run `pecl install timezonedb` if you need current zone rules.

## Verify the sources

The point of this project is that anyone can check that an image contains
the original PHP release and exactly the patches Debian publishes. Without
running any script from this repository, for 7.4:

```sh
# The Debian ELTS archive key; the same file as keys/elts-archive.asc.
curl -fsSLO https://deb.freexian.com/extended-lts/archive-key.gpg
gpg --show-keys archive-key.gpg      # AB597C4F6F3380BD4B2BEBC2A07310D369055D5A

# It signs the archive index, which pins the checksum of the source list.
curl -fsSLO https://deb.freexian.com/extended-lts/dists/bullseye-lts/InRelease
gpgv --keyring ./archive-key.gpg InRelease
curl -fsSLO https://deb.freexian.com/extended-lts/dists/bullseye-lts/main/source/Sources.gz
sha256sum Sources.gz; grep 'main/source/Sources.gz$' InRelease

# The source list pins the checksums of the php7.4 source package...
zcat Sources.gz | awk -v RS= '/(^|\n)Package: php7.4\n/' | sed -n '/^Checksums-Sha256/,/^[A-Z]/p'
# ...which must be the files vendored here and the tarball the build downloads.
sha256sum 7.4/elts/*; grep SHA256 7.4/elts.env

# And Debian's orig tarball is the php.net release.
curl -fsSL 'https://www.php.net/releases/index.php?json&version=7.4.33' \
  | jq -r '.source[] | select(.filename == "php-7.4.33.tar.xz") | .sha256'
```

What is applied: [7.4/series](7.4/series) is Debian's patch series from the
first security fix on ([7.4/series-start](7.4/series-start)); the patches
before it only adapt PHP to Debian's own file layout. Check it against the
vendored package:

```sh
tar -xJf 7.4/elts/*.debian.tar.xz
diff <(sed -n "/^$(grep -v '^#' 7.4/series-start)\$/,\$p" debian/patches/series) 7.4/series
```

[`bin/update.sh --verify 7.4`](bin/update.sh) does all of the above in one go.
Every build, in CI or on your machine, checks the vendored files and the
downloaded tarball against the pinned checksums, the series against Debian's,
and the patched source tree against a pinned hash, and fails on any mismatch.

In an image, `/usr/local/share/php-elts/` holds the `.dsc`, the series and a
SHA-256 of every source file, and `/usr/src/php.tar.xz` is the patched tree.
A published image can be traced to the commit and workflow run that built it:

```sh
gh attestation verify oci://ghcr.io/tarpedo/php-elts:7.4-fpm --repo tarpedo/php-elts
```

## Build it yourself

```sh
git clone https://github.com/tarpedo/php-elts && cd php-elts
bin/build 7.4 fpm        # php-elts:7.4-fpm, about 5 minutes
```

```dockerfile
FROM php-elts:7.4-fpm
```

Branches are `7.3` and `7.4`, variants `cli`, `fpm` and `apache`. Requires
Docker with Buildx. Check out a release tag to build exactly a published image.

## Tags

Tags follow the official images, plus the Debian revision and the build:

| Tag | Points to |
| --- | --- |
| `7.4-fpm`, `7.4.33-fpm`, `7.4-fpm-bullseye` | the latest build |
| `7.4.33-1-deb11u14-fpm` | the latest build of Debian ELTS revision `7.4.33-1+deb11u14` |
| `7.4.33-1-deb11u14-r1-fpm` | one build, never moved |

The same goes for every branch and variant; cli also has the tags without
`-cli` (`7.4`, `7.4.33`, …), as `php:7.4` is the cli image. A Debian revision
is rebuilt as `-r2`, `-r3`, … to pick up Debian package updates.

## How it is tested

1. **CVE regression tests.** Most patches bring the `.phpt` tests PHP added
   with each fix. Every build runs them against the built image, with a
   PostgreSQL server and the extensions they exercise, and fails on any
   failure or on a skip that [tests/cve-tests-skip](tests/cve-tests-skip) does
   not explain (Windows-only or 32-bit-only tests, for example). The report is
   in the build log and in each image, `/usr/local/share/php-elts/cve-tests.log`:
   130 to 137 tests pass per image, none fail.

   Not every fix has a test. Debian's patch for CVE-2026-109618 and
   CVE-2026-109619 ("php2shell") is a minimal mitigation of the upstream fix
   and adds none, so it is verified only by applying cleanly and by the pinned
   hash of the patched tree, not by a test.
2. **Drop-in checks** ([tests/smoke](tests/smoke)) against the official image:
   same extensions, configure flags, ini defaults and image config;
   `docker-php-ext-install` works; FPM and Apache serve a page.
3. **Real application test suites** ([tests/compat](tests/compat),
   `make compat-7.4`): Laravel 8, Carbon 2, PHP-Parser 4, Symfony
   HttpFoundation 5.4, Doctrine DBAL 3.3, Twig 3, CommonMark 1.6 and Monolog 2
   run on the official image and on php-elts with the same dependencies, and
   are compared test by test. Results for the first releases, identical on
   the official image and on php-elts for both branches:

   | Project | Tests | Pass | Skip | Fail on both |
   | --- | ---: | ---: | ---: | ---: |
   | Laravel 8.83 | 6,800 | 6,564 | 231 | 5 |
   | Carbon 2.73 | 5,667 | 5,638 | 29 | 0 |
   | CommonMark 1.6 | 3,866 | 3,866 | 0 | 0 |
   | Doctrine DBAL 3.3 | 3,639 | 3,021 | 617 | 1 |
   | Twig 3.11 | 1,747 | 1,743 | 4 | 0 |
   | PHP-Parser 4.19 | 1,708 | 1,707 | 1 | 0 |
   | Symfony HttpFoundation 5.4 | 1,550 | 1,408 | 137 | 5 |
   | Monolog 2.11 | 1,148 | 1,079 | 69 | 0 |

   The numbers are for 7.4; on 7.3 they differ by at most three tests per
   project. The failures are the same tests on both images, so they come from
   the test environment, not from PHP.

## How it is built

[Dockerfile](Dockerfile), driven by [bin/build](bin/build):

1. Start from the official image, pinned by digest in
   [7.4/base-images](7.4/base-images), and upgrade its packages from ELTS.
2. Unpack the release tarball and apply the patch series.
3. Configure with the flags the official PHP recorded in `php-config`, compile,
   and install over it. The patched tree replaces `/usr/src/php.tar.xz`.
4. Run the CVE regression tests; the image only builds if they pass.

A [daily check](.github/workflows/update-check.yml) opens a pull request when
Debian ELTS publishes a new revision. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

The fixes are written by the [PHP](https://www.php.net/) developers for the
supported 8.x branches. The [Debian LTS and ELTS teams](https://www.freexian.com/lts/extended/)
pick them, port them to 7.3 and 7.4, test and publish them, partly reusing
the public PHP 7.4 backports of Remi Collet. For CVE-2026-109618 and
CVE-2026-109619 ("php2shell") the PHP security team itself published the
7.4 backport, and Debian adapted it to 7.3. This project only packages
their work and is not affiliated with any of them.

These images are a stopgap: a way to close the open vulnerabilities today,
while the application is being moved off PHP 7. If your company has to stay
on PHP 7.3 or 7.4 for longer than that, the permanent solution is a
[Freexian Extended LTS](https://www.freexian.com/lts/extended/) subscription.
It pays for the fixes these images are built from, and it is what keeps
`php7.3` and `php7.4` on the list of packages that get them at all.

## License

The scripts and configuration in this repository are [MIT](LICENSE) licensed.
The images contain PHP under the [PHP License 3.01](https://www.php.net/license/3_01.txt)
and Debian packages under their own licenses.

This product includes PHP software, freely available from
<http://www.php.net/software/>.
