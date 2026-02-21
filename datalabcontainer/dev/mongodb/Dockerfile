FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

ENV MONGO_VERSION=7.0.14 \
    MONGO_HOME=/opt/mongodb

ADD https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION}.tgz /tmp/mongodb.tgz
RUN tar -xzf /tmp/mongodb.tgz -C /opt \
    && mv /opt/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION} ${MONGO_HOME} \
    && rm /tmp/mongodb.tgz

ENV PATH="${PATH}:${MONGO_HOME}/bin"

CMD ["mongod", "--version"]
