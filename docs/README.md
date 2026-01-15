# MSK 고가용성 클러스터 - 문서

처음부터 끝까지 AWS MSK HA Cluster를 구축하는 단계별 가이드입니다.

---

## 📚 문서 순서

MSK 클러스터를 처음 구축한다면 **다음 순서대로** 진행하세요:

### ⚠️ 중요: terraform apply는 단 한 번만!

- **1단계**: 사전 준비 (AWS CLI, 키페어, Lambda 빌드, tfvars 설정)
- **2단계**: `terraform apply` 실행 → **모든 AWS 리소스 자동 생성**
- **3-5단계**: 배포 후 수동 설정 및 검증

---

### 1️⃣ [시작하기](./01_GETTING_STARTED.md)
사전 준비 및 초기 설정
- AWS CLI, Terraform 설치
- EC2 키페어 생성
- Lambda 함수 빌드
- terraform.tfvars 설정

**소요 시간:** 15-20분

---

### 2️⃣ [Terraform 배포](./02_TERRAFORM_DEPLOY.md)
인프라 배포 (`terraform apply` 실행)
- Terraform init & apply
- MSK, Lambda, API Gateway, Prometheus, Grafana 자동 생성
- 배포 검증

**소요 시간:** 20-30분 (MSK 생성 포함)

---

### 3️⃣ [모니터링 설정](./03_MONITORING.md)
Prometheus & Grafana 수동 설정
- Bastion에서 Prometheus 확인
- Grafana Admin 권한 설정 (필요시)
- 데이터 소스 연결 (UI에서)
- 대시보드 Import (JSON 파일)

**소요 시간:** 10-15분
**참고**: Terraform으로 Grafana workspace는 생성되지만, 데이터 소스와 대시보드는 수동 설정 필요

---

### 4️⃣ [Kafka-UI 설정](./04_KAFKA_UI.md)
웹 기반 Kafka 관리 도구
- Bastion SSH 접속
- Docker로 Kafka-UI 실행
- 브라우저에서 접속 확인

**소요 시간:** 5분
**참고**: Terraform은 EC2 내부 명령어를 실행할 수 없어 수동 설정 필요

---

### 5️⃣ [토픽 생성 및 테스트](./05_TESTING.md)
시스템 테스트 및 검증
- Kafka 토픽 생성
- 메시지 발행/소비 테스트
- 성능 벤치마크
- 전체 시스템 검증

**소요 시간:** 10-15분

---

### 📖 [MSK 고가용성 원리](./MSK_HA_SETUP_GUIDE.md)
이론 및 운영 가이드 (선택 사항)
- Express vs Standard 브로커
- Replication Factor와 minISR
- 롤링 업데이트 전략
- 장애 시나리오

---

## 🏗️ 프로젝트 구조

```
msk-ha-cluster/
├── README.md                # 프로젝트 소개
├── docs/                    # 📂 문서 (여기)
│   ├── 01_GETTING_STARTED.md
│   ├── 02_TERRAFORM_DEPLOY.md
│   ├── 03_MONITORING.md
│   ├── 04_KAFKA_UI.md
│   ├── 05_TESTING.md
│   └── MSK_HA_SETUP_GUIDE.md
├── terraform/               # IaC
│   ├── *.tf
│   ├── terraform.tfvars.example
│   └── dashboards/
│       └── msk-overview.json
└── app/                     # Lambda 코드 (테스트용 Pub/Sub)
    ├── producer.py          # 테스트용 메시지 발행
    ├── consumer.py          # 테스트용 메시지 소비
    └── build.sh
```

---

## ⏱️ 전체 소요 시간

| 단계 | 소요 시간 |
|------|----------|
| 사전 준비 | 15-20분 |
| Terraform 배포 | 20-30분 |
| 모니터링 설정 | 10-15분 |
| Kafka-UI 설정 | 5분 |
| 테스트 및 검증 | 10-15분 |
| **총 소요 시간** | **60-85분** |

---

## 💰 예상 비용 (서울 리전)

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

---

## 🚀 빠른 시작 (요약)

이미 환경이 준비되었다면:

```bash
# 1. Lambda 빌드
cd app && bash build.sh

# 2. Terraform 설정
cd ../terraform
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars  # 본인 IP, 키 이름 입력

# 3. 배포
terraform init
terraform apply

# 4. Bastion 접속
ssh -i msk-key.pem ec2-user@$(terraform output -raw bastion_public_ip)

# 5. Kafka-UI 실행 (Bastion에서)
docker run -d --name kafka-ui -p 8080:8080 \
  -e KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS="$(terraform output -raw bootstrap_brokers_tls)" \
  provectuslabs/kafka-ui

# 6. Grafana 접속
terraform output grafana_url
```

---

## 📖 외부 참고 자료

- [AWS MSK Documentation](https://docs.aws.amazon.com/msk/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Amazon Managed Grafana](https://docs.aws.amazon.com/grafana/)
- [MSK Best Practices](https://docs.aws.amazon.com/msk/latest/developerguide/bestpractices.html)

---

**처음 시작하기:** 👉 [01_GETTING_STARTED.md](./01_GETTING_STARTED.md)

**마지막 업데이트:** 2026-01-15
