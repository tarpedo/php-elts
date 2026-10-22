# Contributing

## Layout

| Path | What it is |
| --- | --- |
| `7.3/`, `7.4/` | One directory per PHP branch. `series-start` and `base-images` are written by hand, everything else by `bin/update.sh` |
| `bin/update.sh` | Fetches the current ELTS source package, verifies it and vendors it |
| `bin/build` | Builds one image; CI, releases and `make` all go through it |
| `build/` | Scripts that run inside the Docker build |
| `tests/` | Drop-in checks, CVE test skip/exclude lists, real-world test suites |
| `keys/` | The Debian ELTS archive key; its fingerprint is pinned in `bin/update.sh` |

## Working on it

```sh
make help               # all targets
make 7.4-fpm            # build an image (CVE regression tests included)
make smoke-7.4-fpm      # compare it with the official image
make compat-7.4         # real-world test suites on php-elts:7.4-cli
```

CI builds and smoke-tests all six images for every pull request; run
`make compat-<branch>` when a change could affect how PHP behaves. Shell
scripts must pass `shellcheck`, the Dockerfiles `hadolint`, the workflows
`actionlint`.

## A new ELTS revision

`update-check` notices it within a day and opens a pull request with the
vendored sources. Check the new patches in the diff of `<branch>/series` and
the CVE test report of the build. When a new patch adds a test that cannot run
in these images, list it in `tests/cve-tests-skip` or `tests/cve-tests-exclude`
with the reason.

## Releases

A release is a git tag `<Debian version>-r<N>`: the Debian ELTS revision in
`<branch>/elts.env`, in Docker tag spelling, and which build of it this is.

```sh
git tag 7.4.33-1-deb11u14-r1 && git push origin 7.4.33-1-deb11u14-r1
```

The release workflow builds the three variants for amd64 and arm64, runs the
CVE tests, and pushes the images with their tags. Tag `-r2`, `-r3`, … of the
same revision to rebuild it, e.g. for Debian package updates or a fix to the
build; the immutable tags of earlier builds stay as they are.
