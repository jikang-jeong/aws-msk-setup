#!/bin/bash
set -e

# Update system
yum update -y

# Install dependencies
yum install -y docker jq

# Start Docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Download and install Prometheus
PROM_VERSION="2.48.1"
cd /opt
curl -LO https://github.com/prometheus/prometheus/releases/download/v$${PROM_VERSION}/prometheus-$${PROM_VERSION}.linux-amd64.tar.gz
tar xvfz prometheus-$${PROM_VERSION}.linux-amd64.tar.gz
mv prometheus-$${PROM_VERSION}.linux-amd64 prometheus
rm prometheus-$${PROM_VERSION}.linux-amd64.tar.gz

# Get MSK broker endpoints
REGION="${region}"
BOOTSTRAP_BROKERS="${msk_bootstrap_brokers}"

# Extract broker hostnames from bootstrap brokers string
# Format: b-1.xxx.kafka.region.amazonaws.com:9094,b-2.xxx.kafka.region.amazonaws.com:9094,...
BROKER_TARGETS=$(echo "$BOOTSTRAP_BROKERS" | tr ',' '\n' | sed 's/:9094/:11001/' | sed "s/^/      - '/" | sed "s/$/'/" | tr '\n' ' ')
NODE_TARGETS=$(echo "$BOOTSTRAP_BROKERS" | tr ',' '\n' | sed 's/:9094/:11002/' | sed "s/^/      - '/" | sed "s/$/'/" | tr '\n' ' ')

# Create Prometheus config
cat > /opt/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 30s
  evaluation_interval: 30s
  external_labels:
    cluster: '${cluster_name}'

scrape_configs:
  # MSK JMX Exporter - Kafka broker metrics
  - job_name: 'msk-jmx-exporter'
    static_configs:
      - targets:
$(echo "$BOOTSTRAP_BROKERS" | tr ',' '\n' | sed 's/:9094/:11001/' | sed "s/^/          - '/; s/$/'/")
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: 'b-([0-9]+)\\..*'
        replacement: 'broker-\$\$1'
      - source_labels: [__address__]
        target_label: broker
        regex: '(b-[0-9]+)\\..*'
        replacement: '\$\$1'

  # MSK Node Exporter - System metrics
  - job_name: 'msk-node-exporter'
    static_configs:
      - targets:
$(echo "$BOOTSTRAP_BROKERS" | tr ',' '\n' | sed 's/:9094/:11002/' | sed "s/^/          - '/; s/$/'/")
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: 'b-([0-9]+)\\..*'
        replacement: 'broker-\$\$1'
      - source_labels: [__address__]
        target_label: broker
        regex: '(b-[0-9]+)\\..*'
        replacement: '\$\$1'

remote_write:
  - url: ${prometheus_endpoint}api/v1/remote_write
    queue_config:
      max_samples_per_send: 1000
      max_shards: 200
      capacity: 2500
    sigv4:
      region: ${region}
EOF

# Create systemd service
cat > /etc/systemd/system/prometheus.service <<'SYSTEMD_EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data \
  --storage.tsdb.retention.time=2h \
  --web.listen-address=127.0.0.1:9090
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

# Create data directory
mkdir -p /opt/prometheus/data

# Start Prometheus
systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

# Install Kafka-UI via Docker
mkdir -p /opt/kafka-ui
cat > /opt/kafka-ui/docker-compose.yml <<KAFKA_UI_EOF
version: '3.8'
services:
  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    container_name: kafka-ui
    ports:
      - "8080:8080"
    environment:
      KAFKA_CLUSTERS_0_NAME: ${cluster_name}
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: ${msk_bootstrap_brokers}
      KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL: SSL
    restart: unless-stopped
KAFKA_UI_EOF

# Start Kafka-UI
cd /opt/kafka-ui
docker compose up -d

echo "Bastion setup completed successfully!"
