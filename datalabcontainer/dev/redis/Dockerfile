FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    redis-server nodejs npm \
    && rm -rf /var/lib/apt/lists/*

ENV DBUI_INSTALL_DIR=/opt/dbui \
    MONGO_EXPRESS_NPM_VERSION=1.0.0 \
    REDIS_COMMANDER_NPM_VERSION=0.9.0

RUN mkdir -p "${DBUI_INSTALL_DIR}" \
    && npm install --prefix "${DBUI_INSTALL_DIR}" --no-save --no-audit --no-fund --loglevel=error \
      "mongo-express@${MONGO_EXPRESS_NPM_VERSION}" \
      "redis-commander@${REDIS_COMMANDER_NPM_VERSION}" \
    && (npm cache clean --force >/dev/null 2>&1 || true) \
    && chmod -R a+rX "${DBUI_INSTALL_DIR}"

CMD ["redis-server", "--version"]
