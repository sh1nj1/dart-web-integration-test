# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    FLUTTER_VERSION=3.35.5 \
    FLUTTER_WEB_INTEGRATION_HOME=/workspace \
    DISPLAY=:99 \
    CHROME_VERSION=latest \
    PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Install base packages and VNC/noVNC stack
RUN    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      unzip \
      xz-utils \
      zip \
      wget \
      xvfb \
      x11vnc \
      fluxbox \
      novnc \
      websockify \
      python3 \
      nodejs \
      npm \
      libglu1-mesa \
      libnss3 \
      libatk-bridge2.0-0 \
      libxkbcommon0 \
      libgtk-3-0 \
      libasound2t64 \
      openssh-client \
      fonts-noto-color-emoji \
      fonts-noto-cjk && \
    rm -rf /var/lib/apt/lists/*



# Install Flutter SDK from source repository
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter && \
    git config --global --add safe.directory /opt/flutter

WORKDIR /workspace

COPY pubspec.yaml ./
COPY bin ./bin
COPY integration_test ./integration_test
COPY test_driver ./test_driver
COPY lib ./lib
COPY config ./config
COPY test.sh ./test.sh
COPY test_dsl ./test_dsl
COPY test_target/pubspec.yaml test_target/pubspec.yaml
COPY test_target/lib ./test_target/lib
COPY README.md README.md
COPY README_KO.md README_KO.md

RUN flutter pub get

# Install Chrome and Chromedriver using Puppeteer's browser installer
RUN set -eux; \
    mkdir -p /opt/browsers && cd /opt/browsers; \
    npx --yes @puppeteer/browsers install chrome@$CHROME_VERSION; \
    npx --yes @puppeteer/browsers install chromedriver@$CHROME_VERSION
RUN set -eux; \
    cd /opt/browsers; \
    CHROME_EXECUTABLE=$(realpath $(find chrome -type f -name chrome | head -1)); \
    CHROME_DIRNAME=$(dirname "$CHROME_EXECUTABLE"); \
    mv "$CHROME_EXECUTABLE" "$CHROME_DIRNAME/chrome-real"; \
    printf '#!/bin/bash\nexec "%s/chrome-real" --no-sandbox --disable-dev-shm-usage "$@"\n' "$CHROME_DIRNAME" > "$CHROME_DIRNAME/chrome"; \
    chmod +x "$CHROME_DIRNAME/chrome"; \
    ln -sf "$CHROME_DIRNAME/chrome" /usr/local/bin/google-chrome; \
    mkdir -p /opt/drivers; \
    CHROMEDRIVER_PATH=$(realpath $(find chromedriver -type f -name chromedriver | head -1)); \
    ln -sf "$CHROMEDRIVER_PATH" /opt/drivers/chromedriver; \
    chmod +x /opt/drivers/chromedriver; \
    ln -sf /opt/drivers/chromedriver /usr/local/bin/chromedriver

ENV CHROME_EXECUTABLE=/usr/local/bin/google-chrome

RUN mkdir -p build/generated drivers && \
    ln -sf /opt/drivers/chromedriver drivers/chromedriver

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && chmod +x /workspace/test.sh

EXPOSE 5900 6080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
