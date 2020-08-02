FROM datastax/cassandra-mgmtapi-3_11_6:v0.1.11 as lucene_index

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

FROM datastax/cassandra-mgmtapi-3_11_6:v0.1.11 as medusa

RUN apt-get update -y && \
   apt-get install -y python3 python3-venv gcc g++ python3-dev

RUN mkdir /opt/medusa && \
   cd /opt/medusa && \
   python3 -m venv .venv && \
   . .venv/bin/activate && \
   pip install --upgrade pip && \
   pip install cassandra-medusa==0.7.0


FROM datastax/cassandra-mgmtapi-3_11_6:v0.1.11

RUN apt-get update -y && \
   apt-get install -y python3 apt-transport-https ca-certificates

COPY --from=lucene_index /home/lucene_index/cassandra-lucene-index/plugin/target/cassandra-lucene-index-plugin-3.11.6.1-RC1-SNAPSHOT.jar /opt/cassandra/lib//cassandra-lucene-index-plugin-3.11.6.1-RC1-SNAPSHOT.jar
COPY --from=medusa /opt/medusa /opt/medusa


EXPOSE 9103
EXPOSE 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["mgmtapi"]