# Define ARGs at the top level - available to all stages
ARG BUSYBOX_VERSION
ARG OPENBLAS_VERSION
ARG WHISPER_VERSION

# Build stage
FROM debian:bookworm AS builder

# Redeclare ARGs to make them available in this stage
ARG BUSYBOX_VERSION
ARG OPENBLAS_VERSION
ARG WHISPER_VERSION

RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    libncurses5-dev \
    bison \
    flex \
    cmake \
    libsdl2-dev \
    clang

# Download and compile OpenBLAS
RUN wget https://github.com/OpenMathLib/OpenBLAS/releases/download/v${OPENBLAS_VERSION}/OpenBLAS-${OPENBLAS_VERSION}.tar.gz && \
    tar -xvf OpenBLAS-${OPENBLAS_VERSION}.tar.gz && \
    cd OpenBLAS-${OPENBLAS_VERSION} && \
    make -j$(nproc) TARGET=CORTEXA76 && \
    make install

# Download and compile whisper.cpp
RUN wget https://github.com/ggerganov/whisper.cpp/archive/refs/tags/v${WHISPER_VERSION}.tar.gz && \
    tar -xvf v${WHISPER_VERSION}.tar.gz && \
    cd whisper.cpp-${WHISPER_VERSION} && \
    sh ./models/download-ggml-model.sh tiny.en && \
    cmake -B build -DGMML_BLAS=1 -DWHISPER_SDL2=ON -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ && \
    cmake --build build --config Release

# Create a directory for libraries and copy OpenBLAS libraries there (only if they exist)
RUN mkdir -p /output/lib && \
    if [ -d /usr/local/lib ]; then \
      find /usr/local/lib -name "libopenblas*" -type f -exec cp {} /output/lib/ \; || true; \
    fi

# Runtime stage - using a minimal base image
FROM debian:bookworm-slim

# Redeclare ARGs to make them available in this stage
ARG WHISPER_VERSION

# Install only the runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libsdl2-2.0-0 \
    libasound2-dev \
    alsa-tools \
    alsa-utils && \
    rm -rf /var/lib/apt/lists/* 

# Copy binary, model and required libraries
COPY --from=builder /whisper.cpp-${WHISPER_VERSION}/build/bin/whisper-stream /bin/whisper-stream
COPY --from=builder /whisper.cpp-${WHISPER_VERSION}/models/ggml-tiny.en.bin /models/ggml-tiny.en.bin

# Copy all the required libraries directly to standard lib location
COPY --from=builder /whisper.cpp-${WHISPER_VERSION}/build/src/libwhisper.so* /usr/lib/
COPY --from=builder /whisper.cpp-${WHISPER_VERSION}/build/ggml/src/libggml.so* /usr/lib/
COPY --from=builder /whisper.cpp-${WHISPER_VERSION}/build/ggml/src/libggml-cpu.so* /usr/lib/
COPY --from=builder /whisper.cpp-${WHISPER_VERSION}/build/ggml/src/libggml-base.so* /usr/lib/
COPY --from=builder /output/lib/* /usr/lib/

# Update the dynamic linker configuration
RUN ldconfig

CMD /bin/whisper-stream -m /models/ggml-tiny.en.bin -t 8 --step 500 --length 5000