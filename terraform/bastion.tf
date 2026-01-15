# Bastion/Kafka-UI EC2

# Elastic IP (고정 IP)
resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id

  lifecycle {
    create_before_destroy = true
  }
}

# 퍼블릭 서브넷
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.msk.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 10)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.cluster_name}-public" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.msk.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.msk.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway (Lambda → MSK 연결용)
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.msk.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.msk[count.index].id
  route_table_id = aws_route_table.private.id
}

# 보안그룹
resource "aws_security_group" "bastion" {
  name   = "${var.cluster_name}-bastion-sg"
  vpc_id = aws_vpc.msk.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "SSH access from allowed IPs"
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Kafka-UI access from allowed IPs"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    precondition {
      condition     = !contains(var.allowed_cidr_blocks, "0.0.0.0/0")
      error_message = "Security Group cannot allow 0.0.0.0/0"
    }
  }
}

# MSK 보안그룹에 Bastion 허용 추가
resource "aws_security_group_rule" "msk_from_bastion" {
  type                     = "ingress"
  from_port                = 9092
  to_port                  = 9098
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.msk.id
  description              = "Kafka client access from Bastion"
}

# MSK Prometheus JMX Exporter 포트 (Bastion만 허용)
resource "aws_security_group_rule" "msk_jmx_from_bastion" {
  type                     = "ingress"
  from_port                = 11001
  to_port                  = 11001
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.msk.id
  description              = "JMX Exporter metrics from Bastion only"
}

# MSK Prometheus Node Exporter 포트 (Bastion만 허용)
resource "aws_security_group_rule" "msk_node_from_bastion" {
  type                     = "ingress"
  from_port                = 11002
  to_port                  = 11002
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.msk.id
  description              = "Node Exporter metrics from Bastion only"
}

# IAM Role for Bastion (Prometheus Agent)
resource "aws_iam_role" "bastion" {
  name = "${var.cluster_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "bastion_amp" {
  name = "${var.cluster_name}-bastion-amp"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = aws_prometheus_workspace.msk.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.cluster_name}-bastion-profile"
  role = aws_iam_role.bastion.name
}

# EC2 인스턴스
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  user_data = templatefile("${path.module}/templates/bastion-init.sh", {
    cluster_name            = var.cluster_name
    prometheus_workspace_id = aws_prometheus_workspace.msk.id
    prometheus_endpoint     = aws_prometheus_workspace.msk.prometheus_endpoint
    region                  = var.region
    msk_bootstrap_brokers   = aws_msk_cluster.main.bootstrap_brokers_tls
  })

  user_data_replace_on_change = true

  # 무중단 배포: 새 인스턴스 먼저 생성 후 기존 인스턴스 삭제
  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.cluster_name}-bastion" }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
