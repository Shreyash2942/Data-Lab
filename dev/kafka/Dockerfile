FROM ubuntu:22.04

RUN apt-get update && apt-get install -y openjdk-17-jdk curl && rm -rf /var/lib/apt/lists/*

ENV KAFKA_VERSION=3.7.1 \
    KAFKA_SCALA_VERSION=2.13 \
    KAFKA_HOME=/opt/kafka

ARG KAFKA_TGZ_SHA512=78e985235d245ba9e2951a82e723a62b8aba8b74a2c8376f7271906af715a36de9142c446096f13fd4bff3a4c10f1d080eb924e91e2256ec2db779906fd6737d

ADD https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz /tmp/kafka.tgz
RUN echo "${KAFKA_TGZ_SHA512}  /tmp/kafka.tgz" | sha512sum -c - \
 && tar -xzf /tmp/kafka.tgz -C /opt \
 && mv /opt/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION} ${KAFKA_HOME} \
 && rm /tmp/kafka.tgz

COPY conf/ /tmp/kafka-conf/
RUN cp /tmp/kafka-conf/* ${KAFKA_HOME}/config/ \
 && rm -rf /tmp/kafka-conf

ENV PATH="$PATH:${KAFKA_HOME}/bin"

CMD ["bash","-lc","${KAFKA_HOME}/bin/kafka-server-start.sh ${KAFKA_HOME}/config/server.properties"]
