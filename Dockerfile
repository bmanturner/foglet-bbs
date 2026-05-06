# Find eligible builder and runner images on Docker Hub. We use Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260112-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: docker.io/hexpm/elixir:1.19.5-erlang-28.1.1-debian-trixie-20260112-slim
#
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.1.1
ARG DEBIAN_VERSION=trixie-20260112-slim
ARG USURPER_REBORN_VERSION=0.60.8
ARG USURPER_REBORN_LINUX_X64_SHA256=3e7db43967540dc8a14866feae83dfd209e9cd3a138495bc3993957f8d069594

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
COPY vendor vendor
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates openssh-client python3 curl unzip \
  && rm -rf /var/lib/apt/lists/*

ARG USURPER_REBORN_VERSION
ARG USURPER_REBORN_LINUX_X64_SHA256

# The release runs as Debian's non-root nobody account. Add foglet-door as
# a named UID/GID 65534 alias so restricted_user_process_group manifests can
# resolve their sandbox identity without making the BEAM VM run as root.
RUN set -eux; \
  echo 'foglet-door:x:65534:' >> /etc/group; \
  echo 'foglet-door:x:65534:65534:Foglet door sandbox:/nonexistent:/usr/sbin/nologin' >> /etc/passwd; \
  usurper_zip="UsurperReborn-v${USURPER_REBORN_VERSION}-Linux-x64.zip"; \
  curl -fsSL -o "/tmp/${usurper_zip}" "https://github.com/binary-knight/usurper-reborn/releases/download/v${USURPER_REBORN_VERSION}/${usurper_zip}"; \
  echo "${USURPER_REBORN_LINUX_X64_SHA256}  /tmp/${usurper_zip}" | sha256sum -c -; \
  mkdir -p /opt/foglet/doors/usurper /var/lib/foglet/usurper; \
  unzip -q "/tmp/${usurper_zip}" -d /opt/foglet/doors/usurper; \
  rm "/tmp/${usurper_zip}"; \
  chmod 0755 /opt/foglet /opt/foglet/doors /opt/foglet/doors/usurper; \
  chmod 0755 /opt/foglet/doors/usurper/UsurperReborn; \
  chown -R root:root /opt/foglet; \
  mkdir -p /opt/foglet/doors/usurper/logs; \
  chown foglet-door:foglet-door /opt/foglet/doors/usurper/logs; \
  chmod 0750 /opt/foglet/doors/usurper/logs; \
  chown -R foglet-door:foglet-door /var/lib/foglet; \
  chmod 0750 /var/lib/foglet /var/lib/foglet/usurper

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN mkdir -p /data/ssh \
  && chown -R nobody /app /data

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/foglet_bbs ./
RUN chmod +x /app/bin/server /app/bin/migrate \
  /app/lib/foglet_bbs-*/priv/doors/demo/external_echo.sh \
  /app/lib/foglet_bbs-*/priv/doors/demo/fullscreen_probe.py \
  /app/lib/foglet_bbs-*/priv/doors/pty/foglet_pty_adapter.py

USER nobody

EXPOSE 2222 4000
VOLUME ["/data", "/var/lib/foglet/usurper"]

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
