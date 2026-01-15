variable "region" {
  default = "ap-northeast-2"
}

variable "cluster_name" {
  default = "msk-ha-cluster"
}

variable "kafka_version" {
  default = "3.6.0"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "broker_instance_type" {
  description = "Standard: kafka.m5.*, kafka.m7g.* / Express: express.m7g.*"
  default     = "kafka.m5.large"
}

variable "ebs_volume_size" {
  default = 100
}

variable "tags" {
  type    = map(string)
  default = { Environment = "production" }
}

variable "kafka_topic" {
  default = "test-topic"
}

variable "key_pair_name" {
  description = "EC2 SSH 키페어 이름 (예: msk-key)"
  type        = string
  default     = "msk-key"  # 본인이 생성한 키페어 이름으로 변경
}

variable "allowed_cidr_blocks" {
  description = "Bastion SSH/Grafana 접근 허용 IP - 반드시 본인 IP로 변경하세요! (현재 IP 확인: curl https://checkip.amazonaws.com)"
  type        = list(string)
  default     = ["1.2.3.4/32"]  # ⚠️ 본인의 공인 IP로 변경 필수!

  validation {
    condition     = !contains(var.allowed_cidr_blocks, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not allowed. Specify specific IP ranges."
  }
}

variable "grafana_admin_user_id" {
  description = "AWS SSO User ID for Grafana admin access (optional, will auto-detect if not provided)"
  type        = string
  default     = ""
}
