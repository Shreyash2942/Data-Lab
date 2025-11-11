FROM ubuntu:22.04
RUN apt-get update && apt-get install -y openjdk-17-jdk && rm -rf /var/lib/apt/lists/*
ENV SPARK_VERSION=3.5.1 HADOOP_SHORT=3 SPARK_HOME=/opt/spark
ARG SPARK_TGZ_SHA512=3d8e3f082c602027d540771e9eba9987f8ea955e978afc29e1349eb6e3f9fe32543e3d3de52dff048ebbd789730454c96447c86ff5b60a98d72620a0f082b355
ADD https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_SHORT}.tgz /tmp/spark.tgz
RUN echo "${SPARK_TGZ_SHA512}  /tmp/spark.tgz" | sha512sum -c - \
 && tar -xzf /tmp/spark.tgz -C /opt \
 && mv /opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_SHORT} ${SPARK_HOME} \
 && rm /tmp/spark.tgz
COPY dev/spark/conf/ /tmp/spark-conf/
RUN cp /tmp/spark-conf/* ${SPARK_HOME}/conf/ \
 && rm -rf /tmp/spark-conf
ENV PATH="$PATH:${SPARK_HOME}/bin"
CMD ["spark-submit", "--version"]
