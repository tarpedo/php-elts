# A typical application image: the image under test plus the extensions real
# projects expect, built with docker-php-ext-install from the image's own
# PHP source tarball. Built identically on top of both images being compared.
#
# Build context: the repository root.
ARG IMAGE
FROM ${IMAGE}
ARG JOBS
# The official images can no longer install packages on their own: Debian has
# moved bullseye-security off its mirrors. Both images get them from ELTS.
COPY keys/elts-archive.asc /usr/share/keyrings/debian-elts-archive.asc
RUN codename=$(. /etc/os-release && echo "$VERSION_CODENAME") \
	&& echo "deb [signed-by=/usr/share/keyrings/debian-elts-archive.asc] https://deb.freexian.com/extended-lts $codename-lts main" \
		>/etc/apt/sources.list.d/debian-elts.list \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends git libgmp-dev libicu-dev libpng-dev libzip-dev unzip \
	&& docker-php-ext-install -j"${JOBS:-$(nproc)}" bcmath gd gmp intl pcntl pdo_mysql zip \
	&& rm -rf /var/lib/apt/lists/*
