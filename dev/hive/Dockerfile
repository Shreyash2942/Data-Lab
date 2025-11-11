FROM ubuntu:22.04
RUN apt-get update && apt-get install -y openjdk-17-jdk && rm -rf /var/lib/apt/lists/*
ENV HIVE_VERSION=3.1.3 HIVE_HOME=/opt/hive
ARG HIVE_TGZ_SHA256=0c9b6a6359a7341b6029cc9347435ee7b379f93846f779d710b13f795b54bb16
ADD https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz /tmp/hive.tgz
RUN echo "${HIVE_TGZ_SHA256}  /tmp/hive.tgz" | sha256sum -c - \
 && tar -xzf /tmp/hive.tgz -C /opt \
 && mv /opt/apache-hive-${HIVE_VERSION}-bin ${HIVE_HOME} \
 && rm /tmp/hive.tgz
COPY dev/hive/conf/ /tmp/hive-conf/
RUN cp /tmp/hive-conf/* ${HIVE_HOME}/conf/ \
 && rm -rf /tmp/hive-conf
ENV PATH="$PATH:${HIVE_HOME}/bin"
CMD ["hive", "--version"]
