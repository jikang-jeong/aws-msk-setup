# 시작하기

MSK HA Cluster 구축을 위한 사전 준비 및 초기 설정 가이드입니다.

---

## 📋 사전 요구사항

### 필수 도구
```bash
# Terraform 설치 (macOS)
brew install terraform

# 또는 Linux
curl "https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip" -o terraform.zip
unzip terraform.zip
sudo mv terraform /usr/local/bin/

# 버전 확인
terraform version  # v1.0 이상
```

```bash
# AWS CLI 설치 및 설정
brew install awscli  # macOS
aws configure

# 입력 항목:
# AWS Access Key ID: <입력>
# AWS Secret Access Key: <입력>
# Default region: ap-northeast-2
# Default output format: json

# 확인
aws sts get-caller-identity
```

```bash
# Python 3.9+ (Lambda 빌드용)
python3 --version

# Docker (Kafka-UI용)
docker --version
```

### AWS 권한
다음 AWS 서비스에 대한 권한이 필요합니다:
- **MSK** (Managed Streaming for Apache Kafka)
- **EC2** (VPC, Subnet, Security Group, NAT Gateway, Bastion)
- **Lambda, API Gateway**
- **IAM** (Role, Policy)
- **CloudWatch** (Logs, Metrics, Alarms)
- **Amazon Managed Prometheus**
- **Amazon Managed Grafana**
- **IAM Identity Center (AWS SSO)** - Grafana 인증용

---

## 🔐 AWS 계정 설정

### 1. 현재 IP 확인
Bastion SSH 접근을 위해 현재 퍼블릭 IP를 확인합니다.

```bash
# 현재 IP 확인
curl https://checkip.amazonaws.com

# 또는
curl https://ifconfig.me

# 출력 예: 203.0.113.42
# → 이 IP를 terraform.tfvars의 allowed_cidr_blocks에 입력
```

### 2. EC2 키페어 생성
```bash
# SSH 키페어 생성
aws ec2 create-key-pair \
  --key-name msk-key \
  --region ap-northeast-2 \
  --query 'KeyMaterial' \
  --output text > msk-key.pem

# 권한 설정 (필수)
chmod 400 msk-key.pem

# 키페어 확인
aws ec2 describe-key-pairs \
  --key-names msk-key \
  --region ap-northeast-2

# 출력 예:
# {
#     "KeyPairs": [
#         {
#             "KeyName": "msk-key",
#             "KeyFingerprint": "...",
#             "KeyPairId": "key-..."
#         }
#     ]
# }
```

### 3. AWS SSO 설정 (Grafana 인증용)

**Option 1: Grafana Admin 자동 권한 (권장)**

AWS SSO User ID를 알면 terraform이 자동으로 Grafana Admin 권한을 부여합니다.

```bash
# IAM Identity Center 콘솔에서 확인
# https://console.aws.amazon.com/singlesignon
#
# 또는 AWS CLI로 확인:
aws identitystore list-users \
  --identity-store-id <YOUR_IDENTITY_STORE_ID> \
  --region ap-northeast-2

# User ID 예시: c4f8b488-4081-703e-da8f-5cfc374d0e05
# → terraform.tfvars의 grafana_admin_user_id에 입력
```

**Option 2: 수동 권한 설정**

User ID를 모르면 terraform.tfvars에서 `grafana_admin_user_id = ""`로 비워두고, 배포 후 수동으로 권한을 부여합니다.

---

## 📂 로컬 환경 준비

### 1. 디렉토리 구조 확인
```
msk-ha-cluster/
├── README.md              # 프로젝트 소개
├── .gitignore             # Git 제외 파일
├── docs/                  # 문서 (여기)
│   ├── 01_GETTING_STARTED.md
│   ├── 02_TERRAFORM_DEPLOY.md
│   ├── 03_MONITORING.md
│   ├── 04_KAFKA_UI.md
│   ├── 05_TESTING.md
│   └── MSK_HA_SETUP_GUIDE.md
├── app/                   # Lambda 애플리케이션 (테스트용 Pub/Sub)
│   ├── producer.py        # 테스트용 메시지 발행
│   ├── consumer.py        # 테스트용 메시지 소비
│   └── build.sh
└── terraform/             # Infrastructure as Code
    ├── main.tf
    ├── app.tf
    ├── bastion.tf
    ├── monitoring.tf
    ├── grafana-setup.tf
    ├── dashboard.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    └── dashboards/
        └── msk-overview.json
```

---

## 🔨 Lambda 함수 빌드

> **참고**: 이 Lambda 함수들은 MSK 클러스터의 **테스트 및 검증용 Pub/Sub 샘플**입니다.
> - Producer: API Gateway를 통해 메시지를 발행하는 테스트 함수
> - Consumer: MSK 토픽에서 메시지를 소비하고 CloudWatch Logs에 출력하는 테스트 함수

Lambda 함수 코드를 zip 파일로 패키징합니다.

```bash
cd app
bash build.sh  # app/build.sh 실행
```

**빌드 과정:**
1. Producer 함수 패키징 (테스트용 메시지 발행)
2. Consumer 함수 패키징 (테스트용 메시지 소비)
3. kafka-python 라이브러리 포함

**생성되는 파일:**
- `producer.zip` - 메시지 발행 Lambda (~5MB)
- `consumer.zip` - 메시지 소비 Lambda (~5MB)

**확인:**
```bash
ls -lh *.zip

# 출력 예:
# -rw-r--r--  1 user  staff   5.2M  producer.zip
# -rw-r--r--  1 user  staff   5.1M  consumer.zip
```

**빌드 실패 시:**
```bash
# Python 3.12 환경 확인
python3 --version

# 수동 빌드
cd app
pip3 install kafka-python -t .
zip -r producer.zip producer.py kafka/
zip -r consumer.zip consumer.py kafka/
```

---

## ⚙️ Terraform 변수 설정

### 1. terraform/variables.tf 파일 편집

```bash
cd ../terraform

# 에디터로 variables.tf 열기
vi variables.tf  # 또는 nano, code 등
```

### 2. 필수 변수 수정

**terraform/variables.tf** 파일에서 다음 값들을 수정하세요:

```hcl
variable "key_pair_name" {
  description = "EC2 SSH 키페어 이름 (예: msk-key)"
  type        = string
  default     = "msk-key"  # ← 본인이 생성한 키페어 이름으로 변경
}

variable "allowed_cidr_blocks" {
  description = "Bastion SSH/Grafana 접근 허용 IP"
  type        = list(string)
  default     = ["1.2.3.4/32"]  # ⚠️ 본인의 공인 IP로 변경 필수!
}

variable "grafana_admin_user_id" {
  description = "AWS SSO User ID for Grafana admin access (optional)"
  type        = string
  default     = ""  # 선택: AWS SSO User ID 입력 (예: "c4f8b488-4081-703e-da8f-5cfc374d0e05")
}
```

### 3. 선택 변수 (필요시 수정)

기본값이 적절하면 수정하지 않아도 됩니다:

```hcl
variable "region" {
  default = "ap-northeast-2"  # AWS 리전
}

variable "cluster_name" {
  default = "msk-ha-cluster"  # 클러스터 이름
}

variable "broker_instance_type" {
  default = "kafka.m5.large"  # 또는 "kafka.m5.xlarge"
}

variable "ebs_volume_size" {
  default = 100  # GB
}
```

### 4. 보안 주의사항

> ⚠️ **중요**: terraform/variables.tf 파일을 Git에 커밋할 때
> - `allowed_cidr_blocks`에 본인의 실제 IP가 들어가므로 **public repository에 올리지 마세요**
> - 또는 Git 커밋 전에 다시 예시 IP(`["1.2.3.4/32"]`)로 변경하세요
> - Public repository용으로는 예시 값만 유지하세요

### 5. 변수 확인

```bash
# Terraform 초기화 및 검증
terraform init
terraform validate
```

---

## ✅ 준비 완료 체크리스트

배포 전 다음 사항을 확인하세요:

- [ ] Terraform 설치 완료 (`terraform version`)
- [ ] AWS CLI 설정 완료 (`aws sts get-caller-identity`)
- [ ] Python 3.9+ 설치 완료
- [ ] Docker 설치 완료
- [ ] EC2 키페어 생성 완료 (`msk-key.pem`)
- [ ] 현재 IP 확인 완료
- [ ] Lambda 함수 빌드 완료 (`app/producer.zip`, `app/consumer.zip`)
- [ ] terraform/variables.tf 설정 완료 (key_pair_name, allowed_cidr_blocks)
- [ ] AWS SSO User ID 확인 (Optional)

---

## 🚀 다음 단계

준비가 완료되었습니다. 이제 Terraform으로 인프라를 배포합니다.

👉 **[02_TERRAFORM_DEPLOY.md](./02_TERRAFORM_DEPLOY.md)**

---

## 🔍 추가 정보

### 예상 소요 시간
- 사전 준비: 10-15분
- Lambda 빌드: 2-3분
- Terraform 설정: 5분

### 예상 비용 (서울 리전)
| 리소스 | 월간 비용 |
|--------|----------|
| MSK (kafka.m5.large × 3) | ~$460 |
| EBS (100GB × 3) | ~$30 |
| NAT Gateway | ~$43 |
| Bastion (t3.micro) | ~$9 |
| Managed Prometheus | ~$20 |
| Managed Grafana | ~$9 |
| Lambda & API Gateway | 무료 티어 |
| **합계** | **~$571/월** |

### AWS SSO Identity Store ID 찾기
```bash
# Identity Store ID 확인
aws sso-admin list-instances --region ap-northeast-2

# 출력에서 "IdentityStoreId" 값 확인
```

### 문제 해결

**AWS CLI 권한 부족:**
```bash
# IAM 사용자에게 필요한 권한 정책 연결
# - MSKFullAccess
# - EC2FullAccess
# - IAMFullAccess
# - CloudWatchFullAccess
# - AmazonPrometheusFullAccess
# - AmazonGrafanaFullAccess
```

**Lambda 빌드 실패:**
```bash
# kafka-python 수동 설치
pip3 install kafka-python -t ./app/
```

**키페어 이름 충돌:**
```bash
# 기존 키페어 삭제 후 재생성
aws ec2 delete-key-pair --key-name msk-key --region ap-northeast-2
```
