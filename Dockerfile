FROM cassandra:3.11.3 as lucene_index

RUN apt-get update -y || true && \
    apt-get install -y apt-transport-https ca-certificates && \
    apt-get update -y

RUN apt-get install -y --fix-missing && \
   apt-get install -y git maven openjdk-8-jdk

RUN mkdir -p /home/lucene_index && \
   cd /home/lucene_index && \
   git clone http://github.com/Stratio/cassandra-lucene-index && \
   cd cassandra-lucene-index && \
   git checkout 3.11.3.0 && \
   mvn clean package -Dmaven.test.skip.exec

FROM cassandra:3.11.3
COPY --from=lucene_index /home/lucene_index/cassandra-lucene-index/plugin/target/cassandra-lucene-index-plugin-3.11.3.0.jar /usr/share/cassandra/lib/cassandra-lucene-index-plugin-3.11.3.0.jar