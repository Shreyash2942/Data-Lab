FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

ARG AIRFLOW_VERSION=2.9.3
ARG AIRFLOW_PYTHON_MAJOR_MINOR=3.10

# Base tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    openjdk-17-jdk \
    curl wget git ca-certificates \
    scala \
    nano vim less \
    net-tools iputils-ping \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/bin/python3 /usr/bin/python || true

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$PATH:$JAVA_HOME/bin"

# Spark
ENV SPARK_VERSION=3.5.1 \
    HADOOP_SHORT=3 \
    SPARK_HOME=/opt/spark

ARG SPARK_TGZ_SHA512=3d8e3f082c602027d540771e9eba9987f8ea955e978afc29e1349eb6e3f9fe32543e3d3de52dff048ebbd789730454c96447c86ff5b60a98d72620a0f082b355
ADD https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_SHORT}.tgz /tmp/spark.tgz
RUN echo "${SPARK_TGZ_SHA512}  /tmp/spark.tgz" | sha512sum -c - \
    && tar -xzf /tmp/spark.tgz -C /opt \
    && mv /opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_SHORT} ${SPARK_HOME} \
    && rm /tmp/spark.tgz

COPY dev/spark/conf/ /tmp/spark-conf/
RUN cp /tmp/spark-conf/* ${SPARK_HOME}/conf/ \
    && rm -rf /tmp/spark-conf

# Hadoop
ENV HADOOP_VERSION_FULL=3.3.6 \
    HADOOP_HOME=/opt/hadoop

ARG HADOOP_TGZ_SHA512=de3eaca2e0517e4b569a88b63c89fae19cb8ac6c01ff990f1ff8f0cc0f3128c8e8a23db01577ca562a0e0bb1b4a3889f8c74384e609cd55e537aada3dcaa9f8a
ADD https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION_FULL}/hadoop-${HADOOP_VERSION_FULL}.tar.gz /tmp/hadoop.tgz
RUN echo "${HADOOP_TGZ_SHA512}  /tmp/hadoop.tgz" | sha512sum -c - \
    && tar -xzf /tmp/hadoop.tgz -C /opt \
    && mv /opt/hadoop-${HADOOP_VERSION_FULL} ${HADOOP_HOME} \
    && rm /tmp/hadoop.tgz

# Hive
ENV HIVE_VERSION=3.1.3 \
    HIVE_HOME=/opt/hive

ARG HIVE_TGZ_SHA256=0c9b6a6359a7341b6029cc9347435ee7b379f93846f779d710b13f795b54bb16
ADD https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz /tmp/hive.tgz
RUN echo "${HIVE_TGZ_SHA256}  /tmp/hive.tgz" | sha256sum -c - \
    && tar -xzf /tmp/hive.tgz -C /opt \
    && mv /opt/apache-hive-${HIVE_VERSION}-bin ${HIVE_HOME} \
    && rm /tmp/hive.tgz

COPY dev/hive/conf/ /tmp/hive-conf/
RUN cp /tmp/hive-conf/* ${HIVE_HOME}/conf/ \
    && rm -rf /tmp/hive-conf

ENV KAFKA_VERSION=3.7.1 \
    KAFKA_SCALA_VERSION=2.13 \
    KAFKA_HOME=/opt/kafka

ARG KAFKA_TGZ_SHA512=78e985235d245ba9e2951a82e723a62b8aba8b74a2c8376f7271906af715a36de9142c446096f13fd4bff3a4c10f1d080eb924e91e2256ec2db779906fd6737d
ADD https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz /tmp/kafka.tgz
RUN echo "${KAFKA_TGZ_SHA512}  /tmp/kafka.tgz" | sha512sum -c - \
    && tar -xzf /tmp/kafka.tgz -C /opt \
    && mv /opt/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION} ${KAFKA_HOME} \
    && rm /tmp/kafka.tgz

COPY dev/kafka/conf/ /tmp/kafka-conf/
RUN cp /tmp/kafka-conf/* ${KAFKA_HOME}/config/ \
    && rm -rf /tmp/kafka-conf

COPY dev/hadoop/conf/ /tmp/hadoop-conf/
RUN cp /tmp/hadoop-conf/* ${HADOOP_HOME}/etc/hadoop/ \
    && chown -R ${LAB_APP_USER}:${LAB_APP_USER} ${HADOOP_HOME}/etc/hadoop \
    && rm -rf /tmp/hadoop-conf

# Python tooling
RUN pip install --no-cache-dir \
    "apache-airflow==${AIRFLOW_VERSION}" \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${AIRFLOW_PYTHON_MAJOR_MINOR}.txt"

RUN pip install --no-cache-dir \
    "pyspark==3.5.1" \
    "dbt-core==1.8.7" "dbt-postgres==1.8.2" "dbt-duckdb==1.8.2" \
    "confluent-kafka==2.5.0" \
    "pytest"

# Terraform (optional)
ARG TERRAFORM_ZIP_SHA256=3ff056b5e8259003f67fd0f0ed7229499cfb0b41f3ff55cc184088589994f7a5
ADD https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip /tmp/terraform.zip
RUN echo "${TERRAFORM_ZIP_SHA256}  /tmp/terraform.zip" | sha256sum -c - \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip || true

# Dual user model
ENV LAB_ROOT_USER=datalab_root \
    LAB_APP_USER=datalab_user

RUN useradd -m -s /bin/bash "${LAB_ROOT_USER}" \
    && useradd -m -s /bin/bash "${LAB_APP_USER}" \
    && mkdir -p /workspace \
    && chown -R ${LAB_APP_USER}:${LAB_APP_USER} /workspace

# Default runtime user
USER ${LAB_APP_USER}
WORKDIR /workspace

# Final PATHs
ENV SPARK_HOME=/opt/spark \
    HADOOP_HOME=/opt/hadoop \
    HIVE_HOME=/opt/hive \
    KAFKA_HOME=/opt/kafka \
    PATH="$PATH:${SPARK_HOME}/bin:${HADOOP_HOME}/bin:${HIVE_HOME}/bin:${KAFKA_HOME}/bin"

CMD ["bash"]
