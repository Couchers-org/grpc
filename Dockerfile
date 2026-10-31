FROM ubuntu:24.04 AS bazel

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH

RUN apt-get update -qy && apt-get install -qyy locales && locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8

# install clang and other deps
RUN apt-get  \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    install -qyy  \
      ca-certificates \
      curl  \
      git  \
      unzip  \
      clang-18  \
      build-essential

# Install Bazelisk (wrapper that downloads the right Bazel version)
RUN curl -fsSL "https://github.com/bazelbuild/bazelisk/releases/download/v1.30.0/bazelisk-linux-${TARGETARCH}" \
    -o /usr/local/bin/bazel && \
    chmod +x /usr/local/bin/bazel
ENV CC=clang-18

ENTRYPOINT ["bazelisk"]


FROM bazel AS build

# protoc
WORKDIR /deps/protoc
# The release zip also contains the well-known type protos under include/, needed for protobuf imports.
# Checksums are the GitHub release asset digests; update them when bumping the version.
ARG PROTOC_VERSION=36.2
RUN case "$TARGETARCH" in \
      amd64) ARCH=x86_64;   SHA256=121f6c7afe1d4d0e3ea6aab9432038599250134cbf4474cb1167d2c7decd4278 ;; \
      arm64) ARCH=aarch_64; SHA256=8b8f18bd2b30346efbc698dd5a73dd7c805f3ef8380f6dfc95c768f3f1852f6a ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o protoc.zip \
      "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-${ARCH}.zip" && \
    echo "${SHA256}  protoc.zip" | sha256sum -c - && \
    unzip -q protoc.zip bin/protoc 'include/*'

# grpc
WORKDIR /deps
RUN git clone --depth=1 --shallow-submodules -b v1.85.1 https://github.com/grpc/grpc
WORKDIR /deps/grpc
RUN git submodule update -j 16 --init
# bazelisk picks the Bazel version from grpc's .bazelversion
RUN bazel build //src/compiler:grpc_python_plugin

# protoc-gen-grpc-web
WORKDIR /deps/protoc-gen-grpc-web
ARG PROTOC_GEN_GRPC_WEB_VERSION=2.1.1
RUN case "$TARGETARCH" in \
      amd64) ARCH=x86_64;  SHA256=d7f0000b84ecebceeb317204f60dc2716708f9276d11ae8b4b5d3a10af49d65f ;; \
      arm64) ARCH=aarch64; SHA256=e95f306f16c17cac80280e0964c0095073433232f94b025fe41652a0eeacbaea ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o protoc-gen-grpc-web \
      "https://github.com/grpc/grpc-web/releases/download/${PROTOC_GEN_GRPC_WEB_VERSION}/protoc-gen-grpc-web-${PROTOC_GEN_GRPC_WEB_VERSION}-linux-${ARCH}" && \
    echo "${SHA256}  protoc-gen-grpc-web" | sha256sum -c - && \
    chmod +x protoc-gen-grpc-web

# protoc-gen-js
WORKDIR /deps/protoc-gen-js
# Use the prebuilt release binary (published since v4) instead of building with Bazel.
# The project publishes no checksums, so these are pinned from the release; update them when bumping the version.
ARG PROTOC_GEN_JS_VERSION=4.0.3
RUN case "$TARGETARCH" in \
      amd64) ARCH=x86_64;   SHA256=30abc1d57c3cc7105950e56e1b37b41033f6ed989b79efc59b90186c0a835c30 ;; \
      # note: aarch_64 with an underscore, unlike grpc-web's aarch64
      arm64) ARCH=aarch_64; SHA256=856585ad455e1f1ce82eebb95ca70415d3d8c017559e35b585d7907239bafa04 ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o protobuf-javascript.tar.gz \
      "https://github.com/protocolbuffers/protobuf-javascript/releases/download/v${PROTOC_GEN_JS_VERSION}/protobuf-javascript-${PROTOC_GEN_JS_VERSION}-linux-${ARCH}.tar.gz" && \
    echo "${SHA256}  protobuf-javascript.tar.gz" | sha256sum -c - && \
    tar xzf protobuf-javascript.tar.gz bin/protoc-gen-js

FROM ubuntu:24.04 AS clean

RUN <<EOT
apt-get update -qy
# python is needed in the final image for the mypy-protobuf plugin
apt-get install -qyy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    dos2unix python3-dev python3-pip rsync make

pip3 install --break-system-packages --no-cache-dir --compile mypy-protobuf==5.1.0
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

# copy binaries
COPY --from=build /deps/protoc/bin/protoc /usr/local/bin/
COPY --from=build /deps/grpc/bazel-bin/src/compiler/grpc_python_plugin /usr/local/bin/
COPY --from=build /deps/protoc-gen-grpc-web/protoc-gen-grpc-web /usr/local/bin/
COPY --from=build /deps/protoc-gen-js/bin/protoc-gen-js /usr/local/bin/protoc-gen-js
# copy includes, needed for protobuf imports
COPY --from=build /deps/protoc/include /usr/local/include
