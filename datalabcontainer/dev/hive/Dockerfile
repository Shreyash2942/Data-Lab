FROM ubuntu:22.04
RUN apt-get update && apt-get install -y openjdk-11-jdk && rm -rf /var/lib/apt/lists/*
ENV HIVE_VERSION=2.3.9 HIVE_HOME=/opt/hive
ARG HIVE_TGZ_SHA256=1996327c96672e7ea8eaa8fc63972c75bc095287a32612e545e0e51c1622cb5c
ADD https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz /tmp/hive.tgz
RUN echo "${HIVE_TGZ_SHA256}  /tmp/hive.tgz" | sha256sum -c - \
 && tar -xzf /tmp/hive.tgz -C /opt \
 && mv /opt/apache-hive-${HIVE_VERSION}-bin ${HIVE_HOME} \
 && rm /tmp/hive.tgz
COPY datalabcontainer/dev/lakehouses/hive/conf/ /tmp/hive-conf/
RUN cp /tmp/hive-conf/* ${HIVE_HOME}/conf/ \
 && rm -rf /tmp/hive-conf
ENV PATH="$PATH:${HIVE_HOME}/bin"
CMD ["hive", "--version"]
