FROM aapeliv/bazel:latest as base

FROM base as build

# build deps
RUN apt-get update && apt-get install -y git build-base linux-headers

bazel build //:protoc

# protoc
WORKDIR /deps
RUN git clone -b v3.19.3 https://github.com/protocolbuffers/protobuf
WORKDIR /deps/protobuf
RUN git submodule update -j 16 --init
RUN bazel build //:protoc

# grpc
WORKDIR /deps
RUN git clone -b v1.43.0 https://github.com/grpc/grpc
WORKDIR /deps/grpc
RUN git submodule update -j 16 --init
RUN bazel build //src/compiler:grpc_python_plugin

# grpc-web plugin
WORKDIR /deps
RUN git clone -b 1.3.0 https://github.com/grpc/grpc-web
WORKDIR /deps/grpc-web
RUN bazel build //...

FROM base

# copy binaries
COPY --from build /deps/protoc/bazel-bin/protoc /usr/local/bin/
COPY --from build /deps/grpc/bazel-bin/src/compiler/grpc_python_plugin /usr/local/bin/
COPY --from build /deps/grpc-web/bazel-bin/javascript/net/grpc/web/generator/protoc-gen-grpc-web /usr/local/bin/
# copy includes, needed for protobuf imports
COPY --from=build /deps/protoc/bazel-bin/include /usr/local/include
