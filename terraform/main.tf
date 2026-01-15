terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# VPC & Subnets (3 AZ)
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "msk" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.cluster_name}-vpc" }
}

resource "aws_subnet" "msk" {
  count             = 3
  vpc_id            = aws_vpc.msk.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.cluster_name}-subnet-${count.index + 1}" }
}

resource "aws_security_group" "msk" {
  name   = "${var.cluster_name}-sg"
  vpc_id = aws_vpc.msk.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Kafka client ports (internal VPC access)
resource "aws_security_group_rule" "msk_internal" {
  type              = "ingress"
  from_port         = 9092
  to_port           = 9098
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.msk.id
  description       = "Kafka client ports from VPC"
}

# MSK Configuration
resource "aws_msk_configuration" "ha" {
  name              = "${var.cluster_name}-config"
  kafka_versions    = [var.kafka_version]
  server_properties = <<PROPERTIES
auto.create.topics.enable=false
default.replication.factor=3
min.insync.replicas=2
num.partitions=6
num.io.threads=8
num.network.threads=5
num.replica.fetchers=2
replica.lag.time.max.ms=30000
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
socket.send.buffer.bytes=102400
unclean.leader.election.enable=false
log.retention.hours=168
PROPERTIES
}

# MSK Cluster (3 AZ, 3 brokers)
resource "aws_msk_cluster" "main" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = aws_subnet.msk[*].id
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.ebs_volume_size
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.ha.arn
    revision = aws_msk_configuration.ha.latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  open_monitoring {
    prometheus {
      jmx_exporter { enabled_in_broker = true }
      node_exporter { enabled_in_broker = true }
    }
  }

  enhanced_monitoring = "PER_TOPIC_PER_BROKER"

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.cluster_name}"
  retention_in_days = 7
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.cluster_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 60
  alarm_description   = "MSK broker CPU > 60%"

  metric_query {
    id          = "cpu"
    expression  = "user + system"
    label       = "CPU Total"
    return_data = true
  }

  metric_query {
    id = "user"
    metric {
      metric_name = "CpuUser"
      namespace   = "AWS/Kafka"
      period      = 300
      stat        = "Average"
      dimensions  = { "Cluster Name" = var.cluster_name }
    }
  }

  metric_query {
    id = "system"
    metric {
      metric_name = "CpuSystem"
      namespace   = "AWS/Kafka"
      period      = 300
      stat        = "Average"
      dimensions  = { "Cluster Name" = var.cluster_name }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "disk_high" {
  alarm_name          = "${var.cluster_name}-disk-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "KafkaDataLogsDiskUsed"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "MSK disk usage > 85%"
  dimensions          = { "Cluster Name" = var.cluster_name }
}

resource "aws_cloudwatch_metric_alarm" "under_replicated" {
  alarm_name          = "${var.cluster_name}-under-replicated"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnderReplicatedPartitions"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Under-replicated partitions detected"
  dimensions          = { "Cluster Name" = var.cluster_name }
}
