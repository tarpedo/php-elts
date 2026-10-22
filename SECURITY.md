# Security

## What these images cover

- **PHP** gets every security fix that Debian ELTS backports to `php7.3`
  (buster) and `php7.4` (bullseye). The fixes per release are listed in
  [7.3/FIXES.md](7.3/FIXES.md) and [7.4/FIXES.md](7.4/FIXES.md).
- **Debian packages** of the base image (openssl, glibc, libxml2, curl, …) are
  upgraded from the Debian ELTS archive for bullseye when an image is built,
  and a revision is rebuilt (`-r2`, `-r3`, …) to pick up later updates.
- **Extensions you add** with `docker-php-ext-install` are built from the
  patched PHP sources. PECL extensions are not covered.

A vulnerability fixed in PHP 8 is only fixed here once Debian ELTS backports
it. The images build what ELTS publishes and add no fixes of their own.

## Reporting

- A vulnerability in PHP itself: report it to the PHP project
  (<https://github.com/php/php-src/security>). Once fixed upstream, Debian ELTS
  decides on a backport.
- A problem in these images (a missing or wrong backport, a broken chain of
  trust, a leak in the build): open a private advisory at
  <https://github.com/tarpedo/php-elts/security/advisories/new>.
