# AWS MSK 고가용성 클러스터

AWS MSK (Managed Streaming for Apache Kafka)를 사용한 엔터프라이즈급 고가용성 메시징 시스템입니다.

---

## 🚀 빠른 시작

처음부터 끝까지 완전한 설치 가이드는 **docs 폴더**에서 순서대로 진행하세요:

👉 **[docs/README.md](./docs/README.md)** - 시작하기

### 📖 문서 구조

1. **[시작하기](./docs/01_GETTING_STARTED.md)** - 사전 준비 및 초기 설정 (15-20분)
2. **[Terraform 배포](./docs/02_TERRAFORM_DEPLOY.md)** - 인프라 배포 (20-30분)
3. **[모니터링 설정](./docs/03_MONITORING.md)** - Prometheus & Grafana (10-15분)
4. **[Kafka-UI 설정](./docs/04_KAFKA_UI.md)** - 웹 기반 관리 도구 (5분)
5. **[토픽 생성 및 테스트](./docs/05_TESTING.md)** - 시스템 검증 (10-15분)

**총 소요 시간:** 60-85분

---

## ✨ 주요 기능

### 고가용성 (HA)
- **3 AZ 배포**: 3개 가용 영역에 브로커 분산
- **Replication Factor 3**: 모든 토픽 3중 복제
- **min.insync.replicas 2**: 최소 2개 복제본 확인
- **무중단 운영**: 롤링 업데이트 지원

### 완전한 모니터링
- **Amazon Managed Prometheus**: 메트릭 수집 및 저장
- **Amazon Managed Grafana**: 시각화 대시보드
- **CloudWatch**: 알람 및 로그 관리
- **Kafka-UI**: 웹 기반 클러스터 관리

### 테스트 및 자동화
- **Terraform IaC**: 전체 인프라 코드화
- **Lambda Functions**: 테스트용 Producer/Consumer 샘플
- **API Gateway**: 테스트용 메시지 발행 API
- **Auto Scaling**: Event Source Mapping

---

## 📋 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└────────────┬────────────────────────────────┬────────────────┘
             │                                │
        API Gateway                      Bastion Server
             │                          (Kafka-UI, Prometheus)
             │                                │
┌────────────┴────────────────────────────────┴────────────────┐
│                      AWS VPC (10.0.0.0/16)                    │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Private Subnet (AZ-a)    AZ-b         AZ-c              │ │
│  │  ┌──────────┐          ┌──────────┐  ┌──────────┐       │ │
│  │  │ MSK      │          │ MSK      │  │ MSK      │       │ │
│  │  │ Broker-1 │◄────────►│ Broker-2 │◄─│ Broker-3 │       │ │
│  │  └────┬─────┘          └────┬─────┘  └────┬─────┘       │ │
│  │       │                     │             │              │ │
│  │       └─────────────────────┴─────────────┘              │ │
│  │                         │                                │ │
│  │  ┌──────────────────────┴────────────────────┐          │ │
│  │  │  Lambda Consumer (Event Source Mapping)   │          │ │
│  │  └───────────────────────────────────────────┘          │ │
│  └──────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                              │
                         CloudWatch
                    (Metrics, Logs, Alarms)
```

--- 
## 🛠️ 기술 스택

**Infrastructure:**
- AWS MSK (Apache Kafka 3.6.0)
- Terraform (Infrastructure as Code)
- Amazon VPC, NAT Gateway

**Compute:**
- AWS Lambda (Python 3.12)
- Amazon EC2 (Bastion)
- Docker (Kafka-UI)

**Monitoring:**
- Amazon Managed Prometheus
- Amazon Managed Grafana
- CloudWatch (Logs, Metrics, Alarms)
- Prometheus JMX Exporter
- Prometheus Node Exporter

**API:**
- Amazon API Gateway (HTTP API)
- AWS Lambda Event Source Mapping

---

## 📦 프로젝트 구조

```
msk-ha-cluster/
├── README.md                    # 프로젝트 소개 (이 파일)
├── .gitignore                   # Git 제외 파일
├── docs/                        # 📂 문서 (단계별 가이드)
│   ├── README.md                # 문서 인덱스
│   ├── 01_GETTING_STARTED.md    # 사전 준비
│   ├── 02_TERRAFORM_DEPLOY.md   # 인프라 배포
│   ├── 03_MONITORING.md         # 모니터링 설정
│   ├── 04_KAFKA_UI.md          # Kafka-UI 설정
│   ├── 05_TESTING.md           # 테스트 및 검증
│   └── MSK_HA_SETUP_GUIDE.md   # MSK HA 이론
├── terraform/                   # Infrastructure as Code
│   ├── main.tf                  # MSK, VPC, 네트워크
│   ├── app.tf                   # Lambda, API Gateway
│   ├── bastion.tf               # Bastion, NAT Gateway
│   ├── monitoring.tf            # Prometheus, Grafana
│   ├── grafana-setup.tf         # Grafana 자동 설정
│   ├── dashboard.tf             # CloudWatch 대시보드
│   ├── variables.tf             # 변수 정의
│   ├── outputs.tf               # 출력 값
│   ├── terraform.tfvars.example # 설정 예제
│   └── dashboards/
│       └── msk-overview.json    # Grafana 대시보드
└── app/                         # Lambda 애플리케이션 (테스트용)
    ├── producer.py              # 테스트용 메시지 발행
    ├── consumer.py              # 테스트용 메시지 소비
    └── build.sh                 # 빌드 스크립트
```

---

## 🎯 사용 사례

### 1. 실시간 데이터 파이프라인
- 로그 수집 및 처리
- 이벤트 스트리밍
- CDC (Change Data Capture)

### 2. 마이크로서비스 간 통신
- Event-Driven Architecture
- CQRS (Command Query Responsibility Segregation)
- Saga Pattern

### 3. 실시간 분석
- 스트림 처리 (Kafka Streams, Flink)
- 실시간 대시보드
- 이상 탐지

---

## 🚦 시작하기 (빠른 요약)

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

자세한 설명은 **[docs/README.md](./docs/README.md)**를 참고하세요.

---

## 📝 라이선스

이 프로젝트는 개인 및 상업적 용도로 자유롭게 사용할 수 있습니다.

---

## 🤝 기여

버그 리포트, 기능 제안, 문서 개선은 언제나 환영합니다!

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

---

## 📚 참고 문서

- [AWS MSK Documentation](https://docs.aws.amazon.com/msk/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [MSK Best Practices](https://docs.aws.amazon.com/msk/latest/developerguide/bestpractices.html)
- [Amazon Managed Grafana](https://docs.aws.amazon.com/grafana/)
- [Amazon Managed Prometheus](https://docs.aws.amazon.com/prometheus/)

---

**처음 시작하기:** 👉 [docs/README.md](./docs/README.md)

**마지막 업데이트:** 2026-01-15
