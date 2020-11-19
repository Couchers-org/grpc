FROM alpine:3 as base

FROM base as build

# build deps
RUN apk add --no-cache cmake git build-base linux-headers

# grpc
WORKDIR /deps
RUN git clone -b v1.31.0 https://github.com/grpc/grpc
WORKDIR /deps/grpc
RUN git submodule update -j 16 --init

# patch the source to enable .fromObject() in js
WORKDIR /deps/grpc/third_party/protobuf/src/google/protobuf/compiler/js/
RUN sed -n 'H;${x;s/^\n//;s/    GenerateClass(options, printer, file->message_type(i))\;*\n/&    GenerateClassFromObject(options, printer, file->message_type(i))\;\n/;p;}' js_generator.cc > temp.cc
RUN rm js_generator.cc
RUN mv temp.cc js_generator.cc

WORKDIR /deps/grpc/build
RUN cmake -DgRPC_INSTALL=ON ..
RUN make -j 16
RUN make install

# grpc-web plugin
WORKDIR /deps
RUN git clone -b 1.2.0 https://github.com/grpc/grpc-web
WORKDIR /deps/grpc-web/javascript/net/grpc/web/

# patch the source to enable .fromObject() d.ts
RUN sed -n 'H;${x;s/^\n//;s/      "static serializeBinaryToWriter(message: $class_name$, writer: "*\n/      "static fromObject(obj: $class_name$.AsObject): "\n      "$class_name$;\\n"\n&/;p;}' grpc_generator.cc > temp.cc
RUN rm grpc_generator.cc
RUN mv temp.cc grpc_generator.cc

RUN make -j 16
RUN make install

FROM base

RUN apk add --no-cache libstdc++

# copy binaries
COPY --from=build /usr/local/bin /usr/local/bin
# copy includes, needed for protobuf imports
COPY --from=build /usr/local/include /usr/local/include
