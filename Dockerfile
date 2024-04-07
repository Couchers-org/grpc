FROM ubuntu:22.04 as bazel

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update

RUN apt-get install -y locales && locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8

# install clang and other deps
RUN apt-get install -y curl gnupg python3 git clang-15 build-essential cmake libstdc++-10-dev

# install bazel
RUN curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/bazel.gpg
RUN echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/bazel.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list
RUN apt-get update && apt-get install -y bazel

ENV CC=clang-15

ENTRYPOINT ["bazel"]


FROM bazel as build

# protoc
WORKDIR /deps
RUN git clone -b v26.1 https://github.com/protocolbuffers/protobuf
WORKDIR /deps/protobuf
RUN git submodule update -j 16 --init
RUN bazel build //:protoc
RUN mkdir -p wkt/google/protobuf
RUN cp src/google/protobuf/any.proto src/google/protobuf/api.proto src/google/protobuf/descriptor.proto src/google/protobuf/duration.proto src/google/protobuf/empty.proto src/google/protobuf/field_mask.proto src/google/protobuf/source_context.proto src/google/protobuf/struct.proto src/google/protobuf/timestamp.proto src/google/protobuf/type.proto src/google/protobuf/wrappers.proto wkt/google/protobuf/

# grpc
WORKDIR /deps
RUN git clone -b v1.62.1 https://github.com/grpc/grpc
WORKDIR /deps/grpc
RUN git submodule update -j 16 --init
RUN bazel build //src/compiler:grpc_python_plugin

WORKDIR /deps/protoc-gen-grpc-web
RUN curl -Lo protoc-gen-grpc-web "https://github.com/grpc/grpc-web/releases/download/1.5.0/protoc-gen-grpc-web-1.5.0-linux-x86_64"

WORKDIR /deps/protoc-gen-js
RUN curl -Lo protobuf-javascript.tar.gz "https://github.com/protocolbuffers/protobuf-javascript/releases/download/v3.21.2/protobuf-javascript-3.21.2-linux-x86_64.tar.gz"
RUN tar xf protobuf-javascript.tar.gz

FROM ubuntu:22.04 as clean

# copy binaries
COPY --from=build /deps/protobuf/bazel-bin/protoc /usr/local/bin/
COPY --from=build /deps/grpc/bazel-bin/src/compiler/grpc_python_plugin /usr/local/bin/
COPY --from=build /deps/protoc-gen-grpc-web/protoc-gen-grpc-web /usr/local/bin/
COPY --from=build /deps/protoc-gen-js/bin/protoc-gen-js /usr/local/bin/protoc-gen-js
# copy includes, needed for protobuf imports
COPY --from=build /deps/protobuf/wkt /usr/local/include

RUN apt update && apt install -y dos2unix
