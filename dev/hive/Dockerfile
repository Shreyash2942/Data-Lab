FROM ubuntu:22.04
RUN apt-get update && apt-get install -y openjdk-11-jdk && rm -rf /var/lib/apt/lists/*
ENV HIVE_VERSION=4.0.1 HIVE_HOME=/opt/hive
ARG HIVE_TGZ_SHA256=2bf988a1ed17437b1103e367939c25a13f64d36cf6d1c3bef8c3f319f0067619
ADD https://downloads.apache.org/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz /tmp/hive.tgz
RUN echo "${HIVE_TGZ_SHA256}  /tmp/hive.tgz" | sha256sum -c - \
 && tar -xzf /tmp/hive.tgz -C /opt \
 && mv /opt/apache-hive-${HIVE_VERSION}-bin ${HIVE_HOME} \
 && rm /tmp/hive.tgz
COPY dev/hive/conf/ /tmp/hive-conf/
RUN cp /tmp/hive-conf/* ${HIVE_HOME}/conf/ \
 && rm -rf /tmp/hive-conf
ENV PATH="$PATH:${HIVE_HOME}/bin"
CMD ["hive", "--version"]
