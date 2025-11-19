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
      clang-15  \
      build-essential

# Install Bazelisk (wrapper that downloads the right Bazel version)
RUN curl -fsSL "https://github.com/bazelbuild/bazelisk/releases/download/v1.27.0/bazelisk-linux-${TARGETARCH}" \
    -o /usr/local/bin/bazel && \
    chmod +x /usr/local/bin/bazel
ENV CC=clang-15
ENV USE_BAZEL_VERSION=7.1.0

ENTRYPOINT ["bazelisk"]


FROM bazel AS build

# protoc
WORKDIR /deps
RUN git clone --depth=1 --shallow-submodules -b v26.1 https://github.com/protocolbuffers/protobuf
WORKDIR /deps/protobuf
RUN git submodule update -j 16 --init
RUN bazel build //:protoc
RUN mkdir -p wkt/google/protobuf
RUN cp src/google/protobuf/any.proto \
       src/google/protobuf/api.proto  \
       src/google/protobuf/descriptor.proto  \
       src/google/protobuf/duration.proto  \
       src/google/protobuf/empty.proto  \
       src/google/protobuf/field_mask.proto  \
       src/google/protobuf/source_context.proto  \
       src/google/protobuf/struct.proto  \
       src/google/protobuf/timestamp.proto  \
       src/google/protobuf/type.proto  \
       src/google/protobuf/wrappers.proto  \
       wkt/google/protobuf/

# grpc
WORKDIR /deps
RUN git clone --depth=1 --shallow-submodules -b v1.62.1 https://github.com/grpc/grpc
WORKDIR /deps/grpc
RUN git submodule update -j 16 --init
RUN bazel build //src/compiler:grpc_python_plugin

WORKDIR /deps/protoc-gen-grpc-web

ARG TARGETARCH

RUN if [ "$TARGETARCH" = "amd64" ]; then \
        ARCH_SUFFIX="x86_64"; \
    else \
        ARCH_SUFFIX="aarch64"; \
    fi && \
    curl -Lo protoc-gen-grpc-web "https://github.com/grpc/grpc-web/releases/download/1.5.0/protoc-gen-grpc-web-1.5.0-linux-${ARCH_SUFFIX}"

RUN chmod +x protoc-gen-grpc-web

# protoc-gen-js
WORKDIR /deps/protoc-gen-js
RUN curl -fsSL -o protobuf-javascript.tar.gz "https://github.com/protocolbuffers/protobuf-javascript/archive/refs/tags/v3.21.2.tar.gz" && \
    tar xf protobuf-javascript.tar.gz && \
    cd protobuf-javascript-3.21.2 && \
    bazel build //generator:protoc-gen-js && \
    mkdir -p ../bin && \
    cp bazel-bin/generator/protoc-gen-js ../bin/

FROM ubuntu:24.04 AS clean

RUN <<EOT
apt-get update -qy
# python is needed in the final image for the mypy-protobuf plugin
apt-get install -qyy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    dos2unix python3-dev python3-pip

pip3 install --break-system-package mypy-protobuf
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

# copy binaries
COPY --from=build /deps/protobuf/bazel-bin/protoc /usr/local/bin/
COPY --from=build /deps/grpc/bazel-bin/src/compiler/grpc_python_plugin /usr/local/bin/
COPY --from=build /deps/protoc-gen-grpc-web/protoc-gen-grpc-web /usr/local/bin/
COPY --from=build /deps/protoc-gen-js/bin/protoc-gen-js /usr/local/bin/protoc-gen-js
# copy includes, needed for protobuf imports
COPY --from=build /deps/protobuf/wkt /usr/local/include
