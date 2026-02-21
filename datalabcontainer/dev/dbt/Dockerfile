FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3 python3-pip && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir dbt-core==1.8.7 dbt-postgres==1.8.2
CMD ["dbt", "--version"]
