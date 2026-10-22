# syntax=docker/dockerfile:1

# The official php:<branch>-<variant> image with PHP rebuilt from Debian ELTS
# sources (the php.net release plus every security fix backported since) and
# its Debian packages upgraded from the ELTS archive.
#
# Build arguments come from <branch>/ files; use bin/build rather than calling
# docker build directly.

ARG BASE_IMAGE

FROM ${BASE_IMAGE} AS base
COPY keys/elts-archive.asc /usr/share/keyrings/debian-elts-archive.asc
RUN --mount=type=bind,source=build/apt-upgrade,target=/opt/php-elts/apt-upgrade \
	/opt/php-elts/apt-upgrade

# --------------------------------------------------------------------------
FROM base AS build
ARG BRANCH
ARG MAKE_JOBS

# The -dev packages the official image built with and removed afterwards
# (libonig-dev only matters for 7.4, 7.3 bundles oniguruma).
# hadolint ignore=SC2046
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		libargon2-dev \
		libcurl4-openssl-dev \
		libonig-dev \
		libreadline-dev \
		libsodium-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		zlib1g-dev \
		$(if [ -d /etc/apache2 ]; then echo apache2-dev; fi) \
	&& rm -rf /var/lib/apt/lists/*

COPY build/prepare-source build/check-series build/apply-series build/tree-hash /opt/php-elts/
COPY ${BRANCH}/ /usr/src/php-elts/
RUN /opt/php-elts/prepare-source /usr/src/php-elts
COPY build/compile /opt/php-elts/
RUN MAKE_JOBS=${MAKE_JOBS} /opt/php-elts/compile /usr/src/php-elts

# --------------------------------------------------------------------------
FROM base AS image
ARG BASE_IMAGE
ARG BRANCH
ARG VARIANT
ARG PHP_VERSION
ARG PHP_SHA256
ARG DEBIAN_VERSION
ARG RELEASE=dev

COPY --from=build /out/ /

ENV PHP_VERSION=${PHP_VERSION}
ENV PHP_URL=https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz
ENV PHP_ASC_URL=https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz.asc
ENV PHP_SHA256=${PHP_SHA256}
ENV PHP_ELTS_VERSION=${DEBIAN_VERSION}

RUN --mount=type=bind,source=build/finalize,target=/opt/php-elts/finalize \
	/opt/php-elts/finalize

LABEL org.opencontainers.image.title="php-elts" \
	org.opencontainers.image.description="PHP ${PHP_VERSION} ${VARIANT} with Debian ELTS security fixes, drop-in for php:${BRANCH}-${VARIANT}" \
	org.opencontainers.image.version="${RELEASE}" \
	org.opencontainers.image.source="https://github.com/tarpedo/php-elts" \
	org.opencontainers.image.url="https://github.com/tarpedo/php-elts" \
	org.opencontainers.image.licenses="MIT AND PHP-3.01" \
	org.opencontainers.image.base.name="${BASE_IMAGE}"

# --------------------------------------------------------------------------
FROM image AS test
ARG BRANCH
ARG VARIANT
ARG MAKE_JOBS
COPY build/cve-tests build/cve-tests-report.php /opt/php-elts/
COPY ${BRANCH}/cve-tests tests/cve-tests-skip tests/cve-tests-exclude /usr/src/php-elts/
RUN MAKE_JOBS=${MAKE_JOBS} /opt/php-elts/cve-tests /usr/src/php-elts ${VARIANT}

# --------------------------------------------------------------------------
# The default target: the image itself, which only builds if the tests pass.
FROM image
COPY --from=test /usr/src/php-elts/cve-tests.log /usr/local/share/php-elts/
