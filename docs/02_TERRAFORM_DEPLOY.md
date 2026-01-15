# Terraform 배포 가이드

Terraform을 사용하여 MSK HA Cluster 인프라를 배포하는 가이드입니다.

👈 이전: [01_GETTING_STARTED.md](./01_GETTING_STARTED.md)
👉 다음: [03_MONITORING.md](./03_MONITORING.md)

---

## 📋 사전 확인

시작하기 전 다음 사항이 완료되어야 합니다:
- [ ] Terraform 설치 완료
- [ ] AWS CLI 설정 완료
- [ ] EC2 키페어 생성 (`msk-key.pem`)
- [ ] Lambda 함수 빌드 (`app/producer.zip`, `app/consumer.zip`)
- [ ] terraform/variables.tf 설정 완료 (key_pair_name, allowed_cidr_blocks)

👉 미완료 시: [01_GETTING_STARTED.md](./01_GETTING_STARTED.md)로 돌아가세요

---

## 🚀 Terraform 배포

### 1. 초기화
```bash
cd terraform  # terraform/ 디렉토리로 이동
terraform init
```

**예상 출력:**
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

**오류 발생 시:**
```bash
# 캐시 삭제 후 재시도
rm -rf .terraform .terraform.lock.hcl
terraform init
```

### 2. 배포 계획 확인
```bash
terraform plan
```

**생성될 주요 리소스 (총 ~55개):**
- ✅ VPC, Subnets (3 private + 1 public)
- ✅ Internet Gateway, NAT Gateway
- ✅ Security Groups (MSK, Lambda, Bastion)
- ✅ MSK Cluster (3 brokers across 3 AZs)
- ✅ Lambda Functions (테스트용 Producer, Consumer)
- ✅ API Gateway HTTP API
- ✅ Bastion EC2 (t3.micro)
- ✅ Amazon Managed Prometheus
- ✅ Amazon Managed Grafana
- ✅ CloudWatch Alarms
- ✅ IAM Roles & Policies

**예상 비용 (서울 리전):**
```
Plan: 55 to add, 0 to change, 0 to destroy.

월간 예상 비용: ~$571
```

### 3. 배포 실행
```bash
terraform apply
```

**확인 프롬프트:**
```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes  # ← 입력
```

**배포 진행 상황:**
```
aws_vpc.msk: Creating...
aws_vpc.msk: Creation complete after 2s
aws_subnet.msk[0]: Creating...
...
aws_msk_cluster.main: Still creating... [10m0s elapsed]
aws_msk_cluster.main: Still creating... [20m0s elapsed]
aws_msk_cluster.main: Creation complete after 23m15s
...
Apply complete! Resources: 55 added, 0 changed, 0 destroyed.
```

**예상 소요 시간:**
- MSK 클러스터: 15-25분 (가장 오래 걸림)
- Grafana 워크스페이스: 5-10분
- 나머지 리소스: 5분
- **총 소요 시간: 20-30분**

### 4. 배포 완료 확인
```bash
# 모든 출력 확인
terraform output

# 주요 출력:
# bastion_public_ip = "3.35.58.22"
# bootstrap_brokers_tls = "b-1.xxx:9094,b-2.xxx:9094,b-3.xxx:9094"
# api_endpoint = "https://xxxxx.execute-api.ap-northeast-2.amazonaws.com"
# grafana_url = "https://g-xxxxx.grafana-workspace.ap-northeast-2.amazonaws.com"
# prometheus_endpoint = "https://aps-workspaces...amazonaws.com/workspaces/ws-xxxxx/"
```

**개별 출력 확인:**
```bash
terraform output bastion_public_ip
terraform output bootstrap_brokers_tls
terraform output api_endpoint
terraform output grafana_url
```

---

## 📊 배포된 리소스 상세

### 네트워크
| 리소스 | CIDR/설명 | 용도 |
|--------|-----------|------|
| VPC | 10.0.0.0/16 | MSK 전용 VPC |
| Private Subnet 1 | 10.0.0.0/24 (AZ-a) | MSK Broker-1, Lambda |
| Private Subnet 2 | 10.0.1.0/24 (AZ-b) | MSK Broker-2, Lambda |
| Private Subnet 3 | 10.0.2.0/24 (AZ-c) | MSK Broker-3, Lambda |
| Public Subnet | 10.0.3.0/24 (AZ-a) | Bastion, NAT Gateway |
| NAT Gateway | Elastic IP | Lambda → 인터넷 통신 |

### MSK 클러스터
| 속성 | 값 |
|------|-----|
| Kafka Version | 3.6.0 |
| Broker Type | kafka.m5.large × 3 |
| EBS Volume | 100GB × 3 |
| Replication Factor | 3 |
| min.insync.replicas | 2 |
| Encryption | TLS (in-transit & at-rest) |
| Enhanced Monitoring | PER_TOPIC_PER_BROKER |

### Lambda Functions (테스트용 Pub/Sub)
| Function | Runtime | Timeout | VPC | 용도 |
|----------|---------|---------|-----|------|
| Producer | Python 3.12 | 30s | Private Subnets | 테스트용 메시지 발행 |
| Consumer | Python 3.12 | 30s | Private Subnets | 테스트용 메시지 소비 |

### 모니터링
| 리소스 | 설명 |
|--------|------|
| Amazon Managed Prometheus | 메트릭 저장소 (remote write) |
| Amazon Managed Grafana | 시각화 대시보드 (AWS SSO 인증) |
| CloudWatch Logs | Lambda, MSK 로그 |
| CloudWatch Alarms | CPU, Disk, UnderReplicatedPartitions |

---

## ✅ 배포 검증

### 1. MSK 클러스터 상태 확인
```bash
# 클러스터 상태 조회
aws kafka describe-cluster \
  --cluster-arn $(terraform output -raw msk_cluster_arn) \
  --region ap-northeast-2 \
  --query 'ClusterInfo.State'

# 출력: "ACTIVE"
```

### 2. Lambda 함수 확인
```bash
# Producer 함수
aws lambda get-function \
  --function-name msk-ha-cluster-producer \
  --region ap-northeast-2 \
  --query 'Configuration.State'

# Consumer 함수
aws lambda get-function \
  --function-name msk-ha-cluster-consumer \
  --region ap-northeast-2 \
  --query 'Configuration.State'

# 모두 "Active" 출력되어야 함
```

### 3. Event Source Mapping 확인
```bash
aws lambda list-event-source-mappings \
  --function-name msk-ha-cluster-consumer \
  --region ap-northeast-2 \
  --query 'EventSourceMappings[0].{State:State,Topics:Topics}'

# 출력:
# {
#     "State": "Enabled",
#     "Topics": ["test-topic"]
# }
```

### 4. Bastion 서버 접속 확인
```bash
# SSH 접속 테스트
ssh -i msk-key.pem ec2-user@$(terraform output -raw bastion_public_ip) "echo 'Connection successful'"

# 출력: Connection successful
```

---

## 🔧 리소스 업데이트

### Lambda 코드 업데이트
```bash
# 코드 수정 후 재빌드
cd app
bash build.sh

# Terraform으로 재배포
cd ../terraform
terraform apply

# 또는 AWS CLI로 직접 업데이트 (더 빠름)
aws lambda update-function-code \
  --function-name msk-ha-cluster-producer \
  --zip-file fileb://../app/producer.zip \
  --region ap-northeast-2
```

### MSK 설정 변경
```bash
# terraform/variables.tf 수정 후
terraform apply

# 예: terraform/variables.tf에서 브로커 타입 변경
# variable "broker_instance_type" {
#   default = "kafka.m5.xlarge"
# }
```

### Security Group 규칙 추가
```bash
# bastion.tf 또는 main.tf 수정 후
terraform apply
```

---

## 🗑️ 리소스 정리

### 전체 삭제
```bash
cd terraform
terraform destroy

# 확인 프롬프트에서 'yes' 입력
```

**삭제 순서:**
1. Lambda Event Source Mapping
2. Lambda Functions
3. API Gateway
4. MSK Cluster (시간 소요)
5. NAT Gateway, Elastic IP
6. Subnets, Route Tables
7. VPC
8. Grafana, Prometheus
9. IAM Roles, Policies

**소요 시간: 15-20분**

### 부분 삭제
```bash
# 특정 리소스만 삭제
terraform destroy -target=aws_lambda_function.producer
terraform destroy -target=aws_msk_cluster.main
```

### 삭제 후 정리
```bash
# 로컬 state 파일 삭제
rm -f terraform.tfstate terraform.tfstate.backup

# Lambda zip 파일 삭제
rm -f ../app/*.zip

# EC2 키페어 삭제 (필요시)
aws ec2 delete-key-pair --key-name msk-key --region ap-northeast-2
rm -f msk-key.pem
```

---

## 🐛 트러블슈팅

### 문제 1: Terraform init 실패
**증상:**
```
Error: Failed to query available provider packages
```

**해결:**
```bash
# 프록시 설정 제거
unset HTTP_PROXY HTTPS_PROXY

# DNS 확인
nslookup registry.terraform.io

# 재시도
rm -rf .terraform
terraform init
```

### 문제 2: MSK 클러스터 생성 실패
**증상:**
```
Error: error creating MSK Cluster: InvalidParameterException
```

**해결:**
```bash
# 서브넷이 3개 AZ에 분산되어 있는지 확인
terraform state show aws_subnet.msk[0]
terraform state show aws_subnet.msk[1]
terraform state show aws_subnet.msk[2]

# 각 서브넷의 availability_zone이 다른지 확인
```

### 문제 3: Lambda VPC 연결 실패
**증상:**
```
Error: error creating Lambda Function: InvalidParameterValueException:
The provided execution role does not have permissions to call CreateNetworkInterface
```

**해결:**
```bash
# IAM 역할에 VPC 권한 확인
terraform state show aws_iam_role_policy_attachment.lambda_vpc

# 재배포
terraform apply
```

### 문제 4: Event Source Mapping 생성 실패
**증상:**
```
Error: error creating Lambda Event Source Mapping: ResourceNotFoundException
```

**원인:** MSK 클러스터가 아직 ACTIVE 상태가 아님

**해결:**
```bash
# MSK 상태 확인
aws kafka describe-cluster \
  --cluster-arn $(terraform output -raw msk_cluster_arn) \
  --query 'ClusterInfo.State'

# ACTIVE가 될 때까지 대기 후 재시도
terraform apply
```

### 문제 5: 변수 설정 오류
**증상:**
```
Error: Invalid value for variable
```

**해결:**
```bash
# terraform/variables.tf 확인
cat terraform/variables.tf | grep -A 3 "allowed_cidr_blocks"

# 필수 변수 수정
vi terraform/variables.tf

# key_pair_name과 allowed_cidr_blocks를 본인 환경에 맞게 변경
```

### 문제 6: 비용 초과 방지
**실수로 리소스가 삭제되지 않았을 때:**
```bash
# 모든 MSK 클러스터 확인
aws kafka list-clusters --region ap-northeast-2

# 수동 삭제
aws kafka delete-cluster \
  --cluster-arn <ARN> \
  --region ap-northeast-2

# NAT Gateway 확인 및 삭제
aws ec2 describe-nat-gateways --region ap-northeast-2
aws ec2 delete-nat-gateway --nat-gateway-id <ID> --region ap-northeast-2

# Elastic IP 릴리스
aws ec2 describe-addresses --region ap-northeast-2
aws ec2 release-address --allocation-id <ID> --region ap-northeast-2
```

---

## 📚 다음 단계

인프라 배포가 완료되었습니다. 이제 모니터링을 설정합니다.

👉 **[03_MONITORING.md](./03_MONITORING.md)** - Prometheus & Grafana 설정

---

## 🔗 참고 링크

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS MSK Terraform Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/msk_cluster)
- [Terraform Backend Configuration](https://www.terraform.io/docs/language/settings/backends/index.html)
