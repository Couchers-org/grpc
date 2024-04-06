FROM aapeliv/bazel:latest as base

FROM base as build

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

# grpc-web plugin
WORKDIR /deps
RUN git clone -b 1.5.0 https://github.com/grpc/grpc-web
WORKDIR /deps/grpc-web
RUN bazel build //...

FROM ubuntu:20.04 as clean

# copy binaries
COPY --from=build /deps/protobuf/bazel-bin/protoc /usr/local/bin/
COPY --from=build /deps/grpc/bazel-bin/src/compiler/grpc_python_plugin /usr/local/bin/
COPY --from=build /deps/grpc-web/bazel-bin/javascript/net/grpc/web/generator/protoc-gen-grpc-web /usr/local/bin/
# copy includes, needed for protobuf imports
COPY --from=build /deps/protobuf/wkt /usr/local/include

RUN apt update && apt install -y dos2unix
