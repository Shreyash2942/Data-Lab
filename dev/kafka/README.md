# Kafka Stack

Reference Dockerfile that installs Apache Kafka 3.7.1 (Scala 2.13) plus a single-node Zookeeper instance. Configuration files are located in `dev/kafka/conf/` and copied into `/opt/kafka/config` during the image build.

- `server.properties` — broker configuration (PLAINTEXT listener on `localhost:9092`, logs under `/workspace/kafka/logs`)
- `zookeeper.properties` — Zookeeper data directory configuration (`/workspace/kafka/zookeeper-data`)

Use this directory as a blueprint if you want to tweak or debug the Kafka installation separately from the monolithic container.
