# syntax=docker/dockerfile:1
FROM satmandu/raspios:lite AS baseimage

# Default environment variables
ENV DEBUG="0" \
    SERVER_ADDRESS="eu1.cloud.thethings.network" \
    SERVER_PORT_UP="1700" \
    SERVER_PORT_DOWN="1700"

# Labels
LABEL \
    org.opencontainers.image.source="https://github.com/pascal0030/lorawan-gateway-sx1302" \
    org.opencontainers.image.description="Loarawan Gateway Docker Image" \
    org.opencontainers.image.authors="Pasal0030"

# Install required packages
# wget and unzip are used by the raspberrypi5 stage below. They happen to be
# present in the current base image, but that tag floats - install them so a
# rebuild does not break when it changes.
RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    gcc \
    jq \
    git \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Raspberry Pi 5 installation
FROM baseimage AS raspberrypi5
LABEL org.opencontainers.image.target.system="raspberrypi5"

# Install sx1302_hal_rpi5 HAL
WORKDIR /app
RUN wget -q https://files.waveshare.com/wiki/SX130X/demo/PI5/sx130x_hal_rpi5.zip && \
    unzip sx130x_hal_rpi5.zip && \
    rm sx130x_hal_rpi5.zip

WORKDIR /app/sx1302_hal_rpi5-master
RUN make clean all
RUN cp tools/reset_lgw.sh util_chip_id/ && cp tools/reset_lgw.sh packet_forwarder/

COPY entrypoint.sh /app/sx1302_hal_rpi5-master/
RUN chmod +x /app/sx1302_hal_rpi5-master/entrypoint.sh

CMD ["/bin/bash", "-c", "./entrypoint.sh"]
