FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl nodejs npm \
    && rm -rf /var/lib/apt/lists/*

ENV MONGO_VERSION=7.0.14 \
    MONGO_HOME=/opt/mongodb

ADD https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION}.tgz /tmp/mongodb.tgz
RUN tar -xzf /tmp/mongodb.tgz -C /opt \
    && mv /opt/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION} ${MONGO_HOME} \
    && rm /tmp/mongodb.tgz

ENV DBUI_INSTALL_DIR=/opt/dbui \
    MONGO_EXPRESS_NPM_VERSION=1.0.0 \
    REDIS_COMMANDER_NPM_VERSION=0.9.0

RUN mkdir -p "${DBUI_INSTALL_DIR}" \
    && npm install --prefix "${DBUI_INSTALL_DIR}" --no-save --no-audit --no-fund --loglevel=error \
      "mongo-express@${MONGO_EXPRESS_NPM_VERSION}" \
      "redis-commander@${REDIS_COMMANDER_NPM_VERSION}" \
    && (npm cache clean --force >/dev/null 2>&1 || true) \
    && chmod -R a+rX "${DBUI_INSTALL_DIR}"

ENV PATH="${PATH}:${MONGO_HOME}/bin"

CMD ["mongod", "--version"]
