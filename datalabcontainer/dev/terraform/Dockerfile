FROM ubuntu:22.04
RUN apt-get update && apt-get install -y unzip && rm -rf /var/lib/apt/lists/*
ARG TERRAFORM_ZIP_SHA256=3ff056b5e8259003f67fd0f0ed7229499cfb0b41f3ff55cc184088589994f7a5
ADD https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip /tmp/terraform.zip
RUN echo "${TERRAFORM_ZIP_SHA256}  /tmp/terraform.zip" | sha256sum -c - \
 && unzip /tmp/terraform.zip -d /usr/local/bin \
 && rm /tmp/terraform.zip
CMD ["terraform", "--version"]
