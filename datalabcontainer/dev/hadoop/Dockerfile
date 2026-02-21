FROM ubuntu:22.04
RUN apt-get update && apt-get install -y openjdk-17-jdk && rm -rf /var/lib/apt/lists/*
ENV HADOOP_VERSION_FULL=3.3.6 HADOOP_HOME=/opt/hadoop
ARG HADOOP_TGZ_SHA512=de3eaca2e0517e4b569a88b63c89fae19cb8ac6c01ff990f1ff8f0cc0f3128c8e8a23db01577ca562a0e0bb1b4a3889f8c74384e609cd55e537aada3dcaa9f8a
ADD https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION_FULL}/hadoop-${HADOOP_VERSION_FULL}.tar.gz /tmp/hadoop.tgz
RUN echo "${HADOOP_TGZ_SHA512}  /tmp/hadoop.tgz" | sha512sum -c - \
 && tar -xzf /tmp/hadoop.tgz -C /opt \
 && mv /opt/hadoop-${HADOOP_VERSION_FULL} ${HADOOP_HOME} \
 && rm /tmp/hadoop.tgz
COPY datalabcontainer/dev/hadoop/conf/ /tmp/hadoop-conf/
RUN cp /tmp/hadoop-conf/* ${HADOOP_HOME}/etc/hadoop/ \
 && rm -rf /tmp/hadoop-conf
ENV PATH="$PATH:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin"
CMD ["hadoop", "version"]
