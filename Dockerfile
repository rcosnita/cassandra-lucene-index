# Taken from https://github.com/datastax/management-api-for-apache-cassandra/blob/master/Dockerfile-build
# Requirements described in https://community.datastax.com/questions/5080/what-are-the-image-requirements-when-setting-a-cus.html
FROM maven:3.6.3-jdk-8-slim as management-api-for-apache-cassandra-builder

WORKDIR /build

COPY third-party/management-api-for-apache-cassandra/pom.xml ./
COPY third-party/management-api-for-apache-cassandra/management-api-agent/pom.xml ./management-api-agent/pom.xml
COPY third-party/management-api-for-apache-cassandra/management-api-common/pom.xml ./management-api-common/pom.xml
COPY third-party/management-api-for-apache-cassandra/management-api-server/pom.xml ./management-api-server/pom.xml
COPY third-party/management-api-for-apache-cassandra/management-api-shim-3.x/pom.xml ./management-api-shim-3.x/pom.xml
COPY third-party/management-api-for-apache-cassandra/management-api-shim-4.x/pom.xml ./management-api-shim-4.x/pom.xml
# this duplicates work done in the next steps, but this should provide
# a solid cache layer that only gets reset on pom.xml changes
RUN mvn -q -ff -T 1C install && rm -rf target

COPY third-party/management-api-for-apache-cassandra/management-api-agent ./management-api-agent
COPY third-party/management-api-for-apache-cassandra/management-api-common ./management-api-common
COPY third-party/management-api-for-apache-cassandra/management-api-server ./management-api-server
COPY third-party/management-api-for-apache-cassandra/management-api-shim-3.x ./management-api-shim-3.x
COPY third-party/management-api-for-apache-cassandra/management-api-shim-4.x ./management-api-shim-4.x
RUN mvn -q -ff package -DskipTests


FROM cassandra:3.11.6 as lucene_index

RUN apt-get update -y || true && \
    apt-get install -y apt-transport-https ca-certificates && \
    apt-get update -y

RUN apt-get install -y --fix-missing && \
   apt-get install -y git maven openjdk-8-jdk

RUN mkdir -p /home/lucene_index && \
   cd /home/lucene_index && \
   git clone https://github.com/rcosnita/cassandra-lucene-index-1.git cassandra-lucene-index && \
   cd cassandra-lucene-index && \
   git checkout branch-3.11.6.0 && \
   export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64 && \
   export PATH=${JAVA_HOME}/bin:${PATH} && \
   mvn clean package -Dmaven.test.skip.exec

FROM cassandra:3.11.6 as medusa

RUN apt-get update -y && \
   apt-get install -y python3 python3-venv gcc g++ python3-dev

RUN mkdir /opt/medusa && \
   cd /opt/medusa && \
   python3 -m venv .venv && \
   . .venv/bin/activate && \
   pip install --upgrade pip && \
   pip install cassandra-medusa==0.7.0


FROM cassandra:3.11.6

RUN apt-get update -y && \
   apt-get install -y python3

COPY --from=lucene_index /home/lucene_index/cassandra-lucene-index/plugin/target/cassandra-lucene-index-plugin-3.11.6.1-RC1-SNAPSHOT.jar /opt/cassandra/lib//cassandra-lucene-index-plugin-3.11.6.1-RC1-SNAPSHOT.jar
COPY --from=medusa /opt/medusa /opt/medusa

COPY --from=management-api-for-apache-cassandra-builder /build/management-api-common/target/datastax-mgmtapi-common-0.1.0-SNAPSHOT.jar /etc/cassandra/
COPY --from=management-api-for-apache-cassandra-builder /build/management-api-agent/target/datastax-mgmtapi-agent-0.1.0-SNAPSHOT.jar /etc/cassandra/
COPY --from=management-api-for-apache-cassandra-builder /build/management-api-server/target/datastax-mgmtapi-server-0.1.0-SNAPSHOT.jar /opt/mgmtapi/
COPY --from=management-api-for-apache-cassandra-builder /build/management-api-shim-3.x/target/datastax-mgmtapi-shim-3.x-0.1.0-SNAPSHOT.jar /opt/mgmtapi/
COPY --from=management-api-for-apache-cassandra-builder /build/management-api-shim-4.x/target/datastax-mgmtapi-shim-4.x-0.1.0-SNAPSHOT.jar /opt/mgmtapi/

ENV TINI_VERSION v0.18.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

RUN set -eux; \
  rm -fr /etc/apt/sources.list.d/*; \
  rm -rf /var/lib/apt/lists/*; \
  apt-get update; \
  apt-get install -y --no-install-recommends wget iproute2; \
  rm -rf /var/lib/apt/lists/*

ENV MCAC_VERSION 0.1.7
ADD https://github.com/datastax/metric-collector-for-apache-cassandra/releases/download/v${MCAC_VERSION}/datastax-mcac-agent-${MCAC_VERSION}.tar.gz /opt/mcac-agent.tar.gz
RUN mkdir /opt/mcac-agent && tar zxvf /opt/mcac-agent.tar.gz -C /opt/mcac-agent --strip-components 1 && rm /opt/mcac-agent.tar.gz

# backwards compat with upstream ENTRYPOINT
COPY third-party/management-api-for-apache-cassandra/scripts/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh && \
  ln -sf /usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh

EXPOSE 9103
EXPOSE 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["mgmtapi"]