#!/bin/bash
    exec >> /var/log/case-management.log 2>&1
    sudo mkdir /home/ubuntu/password
    cd /home/ubuntu/password
    echo "${data.terraform_remote_state.keycloak.outputs.keycloakpwd}" > password.txt
    export KEYCLOAK_ADMIN_PASSWORD="${data.terraform_remote_state.keycloak.outputs.keycloakpwd}"
    echo "KEYCLOAK_ADMIN_PASSWORD: $KEYCLOAK_ADMIN_PASSWORD"
    echo "KEYCLOAK_ADMIN_PASSWORD=\"${data.terraform_remote_state.keycloak.outputs.keycloakpwd}\"" | tee -a /etc/environment > /dev/null
    echo "ORGANIZATION_NAME=\"${var.organization_name}\"" | tee -a /etc/environment > /dev/null
    source /etc/environment
    echo "KEYCLOAK_ADMIN_PASSWORD from /etc/environment: $KEYCLOAK_ADMIN_PASSWORD"
    echo "ORGANIZATION_NAME from /etc/environment: $ORGANIZATION_NAME"
    echo "export KEYCLOAK_ADMIN_PASSWORD=\"${data.terraform_remote_state.keycloak.outputs.keycloakpwd}\"" >> ~/.bashrc
    echo "export ORGANIZATION_NAME=\"${var.organization_name}\"" >> ~/.bashrc
    source ~/.bashrc
    echo "KEYCLOAK_ADMIN_PASSWORD from ~/.bashrc: $KEYCLOAK_ADMIN_PASSWORD"
    echo "ORGANIZATION_NAME from ~/.bashrc: $ORGANIZATION_NAME"
    sudo apt update
    sudo apt upgrade -y
    echo "=========================================="
    echo "Installing Java 1.8.x"
    echo "=========================================="

    apt-get install -y openjdk-8-jre-headless unzip
    echo JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64" >> /etc/environment
    export JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"

    echo "=========================================="
    echo "Installing Cassandra 3.11.x"
    echo "=========================================="

    wget -qO -  https://downloads.apache.org/cassandra/KEYS | sudo gpg --dearmor  -o /usr/share/keyrings/cassandra-archive.gpg

    echo "deb [signed-by=/usr/share/keyrings/cassandra-archive.gpg] https://debian.cassandra.apache.org 40x main" |  sudo tee -a /etc/apt/sources.list.d/cassandra.sources.list

    sudo apt update -y
    sudo apt install cassandra -y
    # curl -fsSL https://www.apache.org/dist/cassandra/KEYS | sudo apt-key add -
    # echo "deb http://www.apache.org/dist/cassandra/debian 311x main" | sudo tee -a /etc/apt/sources.list.d/cassandra.sources.list

    # sudo apt update -y
    # sudo apt install cassandra -y

    cp /etc/cassandra/cassandra.yaml /etc/cassandra/cassandra.yaml.backup
    cp /etc/cassandra/cassandra.yaml ./cassandra.yaml.template
    #sed -i "s/Test Cluster/thp/g" cassandra.yaml.template
    sed -i "s/hints_directory:.*/hints_directory: \/data\/hints/g" cassandra.yaml.template
    sed -i "s/commitlog_directory:.*/commitlog_directory: \/var\/lib\/cassandra\/logs\/commitlog/g" cassandra.yaml.template
    sed -i "s/commitlog_directory:.*/commitlog_directory: \/var\/lib\/cassandra\/logs\/commitlog/g" cassandra.yaml.backup
    sed -i "s/saved_caches_directory:.*/saved_caches_directory: \/var\/lib\/cassandra\/data\/saved_caches/g" cassandra.yaml.template
    \cp -fR ./cassandra.yaml.template /etc/cassandra/cassandra.yaml

    #chkconfig --del cassandra
    systemctl daemon-reload
    systemctl enable cassandra
    systemctl start cassandra
    sleep 60

    cqlsh localhost 9042 --execute="UPDATE system.local SET cluster_name = 'thp' where key='local';"
    nodetool flush

    sed -i "s/Test Cluster/thp/g" /etc/cassandra/cassandra.yaml

    systemctl restart cassanndra


    echo "========================================="
    echo "Installing Thehive 4.1.x"
    echo "========================================="

    curl https://raw.githubusercontent.com/TheHive-Project/TheHive/master/PGP-PUBLIC-KEY | sudo apt-key add -

    echo 'deb https://deb.thehive-project.org release main' | sudo tee -a /etc/apt/sources.list.d/thehive-project.list
    sudo apt-get update -y
    sudo apt-get install thehive4 -y

    mkdir /opt/thp/thehive/index
    chown thehive:thehive -R /opt/thp/thehive/index

    mkdir -p /opt/thp/thehive/files
    chown -R thehive:thehive /opt/thp/thehive/files

    mv  /etc/thehive/application.conf /etc/thehive/application.conf.bkp
    wget https://hive-repo-bucket.s3.ap-south-1.amazonaws.com/application.conf

    mv /application.conf /etc/thehive/application.conf

    chown root:thehive /etc/thehive/application.conf

    systemctl daemon-reload
    systemctl enable thehive
    systemctl start thehive

    echo "=================================="
    echo "Installing Elasticsearch"
    echo "=================================="

    # PGP key installation
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key D88E42B4

    # Alternative PGP key installation
    # wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -

    echo  "Debian repository configuration"
    echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list

    echo "Install https support for apt"
    sudo apt install apt-transport-https

    echo "Elasticsearch installation"
    sudo apt update && sudo apt install elasticsearch -y 

    echo "Make changes in config of Elasticsearch"

    mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bkp
    touch /etc/elasticsearch/elasticsearch.yml
    echo "path.data: /var/lib/elasticsearch" >> /etc/elasticsearch/elasticsearch.yml
    echo "path.logs: /var/log/elasticsearch" >> /etc/elasticsearch/elasticsearch.yml
    echo "http.host: 127.0.0.1" >> /etc/elasticsearch/elasticsearch.yml
    echo "discovery.type: single-node" >> /etc/elasticsearch/elasticsearch.yml
    echo "cluster.name: hive" >> /etc/elasticsearch/elasticsearch.yml
    echo "thread_pool.search.queue_size: 100000" >> /etc/elasticsearch/elasticsearch.yml
    sed -i s/"## -Xms4g"/"-Xms2g"/g /etc/elasticsearch/jvm.options
    sed -i s/"## -Xmx4g"/"-Xmx2g"/g /etc/elasticsearch/jvm.options

    systemctl daemon-reload
    systemctl enable elasticsearch
    systemctl start elasticsearch
    sleep 30

    echo "==================================="
    echo "Installing Cortex 3.1.x"
    echo "==================================="

    apt install cortex unzip -y

    sudo mkdir /etc/cortex
    (cat << _EOF_
    # Secret key
    # ~~~~~
    # The secret key is used to secure cryptographics functions.
    # If you deploy your application to several instances be sure to use the same key!
    play.http.secret.key="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)"
    _EOF_
    ) | sudo tee -a /etc/cortex/application.conf

    systemctl start cortex
    systemctl enable cortex

    echo "====================================================="
    echo "Making configuration file changes in Elasticsearch"
    echo "====================================================="

    mkdir -p  /opt/backup
    chmod 777 /opt/backup
    echo "path.repo: ["/opt/backup"]" >> /etc/elasticsearch/elasticsearch.yml
    chown -R elasticsearch: /opt/backup/


    sudo systemctl restart elasticsearch
    sleep 20

    #curl -XPUT -H 'Content-Type: application/json' 'http://localhost:9200/_snapshot/cortex_backup' -d '{"type": "fs","settings": {"location": "/opt/backup","compress": true}'
    curl -X PUT "127.0.0.1:9200/_snapshot/cortex_backup" -H 'Content-Type: application/json' -d'{  "type": "fs",  "settings": {    "location": "/opt/backup" ,   "compress": "true"  }}'
    curl -XPUT -H 'Content-Type: application/json' 'http://localhost:9200/_snapshot/cortex_backup/snapshot_2'

    sudo yes | rm -rf /opt/backup/*

    sudo ls -l /opt/backup

    wget https://hive-repo-bucket.s3.ap-south-1.amazonaws.com/backup.zip
    unzip backup.zip -d /opt/
    chown -R elasticsearch /opt/backup

    sudo systemctl restart elasticsearch
    sleep 30

    curl -X POST "127.0.0.1:9200/_snapshot/cortex_backup/snapshot_2/_restore?pretty"

    sudo systemctl daemon-reload
    sudo systemctl restart cortex

    echo "========================================================="
    echo "Cortex-Hive integration"
    echo "========================================================="

    wget https://hive-repo-bucket.s3.ap-south-1.amazonaws.com/cortex-hive-integration.conf

    mv /etc/thehive/application.conf /etc/thehive/application.conf.latest
    cp -r /cortex-hive-integration.conf /etc/thehive/application.conf

    sudo systemctl daemon-reload
    sudo systemctl restart thehive
    sudo systemctl restart cassandra
    sudo systemctl restart elasticsearch
    sudo systemctl restart cortex

    echo "Installation Finished "
    echo "==================================="
    echo "Credentials of Hive"
    echo "==================================="
    echo "Login Username: admin@thehive.local"
    echo "Login Password: secret"

    echo "==================================="
    echo "Credentials of Cortex"
    echo "==================================="
    echo "Login Username: admin"
    echo "Login Password: redhat"

    echo "Kindly Change all default credentials"