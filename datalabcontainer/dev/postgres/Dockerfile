FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql postgresql-client \
    && rm -rf /var/lib/apt/lists/*

CMD ["psql", "--version"]
