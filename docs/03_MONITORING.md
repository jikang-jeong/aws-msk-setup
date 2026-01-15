# AWS Managed Grafana 설정 가이드

## 개요

이 프로젝트는 AWS Managed Grafana + Amazon Managed Prometheus를 사용하여 MSK 클러스터의 상세한 모니터링을 제공합니다.

### 모니터링 아키텍처

```
MSK Cluster (3 Brokers)
  ↓ JMX Exporter (11001) + Node Exporter (11002)
Bastion EC2 (Prometheus Agent)
  ↓ Remote Write (IAM Auth)
Amazon Managed Prometheus
  ↓ Query
AWS Managed Grafana
```

### 보안 설계

- **네트워크 격리**: Prometheus 메트릭 포트(11001, 11002)는 Bastion 보안그룹에서만 접근 가능
- **Public 접근 차단**: SSH(22), Kafka-UI(8080), Prometheus(9090) 모두 `allowed_cidr_blocks`로 제한
- **IAM 권한 최소화**: Bastion EC2는 Prometheus remote write 권한만 보유
- **암호화**: MSK 클러스터 내부 및 클라이언트 통신 TLS 암호화

## 배포 후 설정

> **전제 조건**: [02_TERRAFORM_DEPLOY.md](./02_TERRAFORM_DEPLOY.md)에서 `terraform apply` 완료 후 진행

Terraform으로 Prometheus와 Grafana workspace는 자동 생성되지만, **데이터 소스 연결과 대시보드 import는 수동 설정**이 필요합니다.

### 1. AWS SSO 설정

AWS Managed Grafana는 AWS SSO 인증이 필요합니다.

1. AWS Console → AWS IAM Identity Center (SSO) 활성화
2. SSO 사용자 생성 또는 기존 사용자 선택
3. Grafana Workspace → Authentication → AWS SSO 사용자 할당

### 2. Grafana 데이터 소스 연결

Terraform은 데이터 소스 **기능**만 활성화합니다. 실제 연결은 수동 설정 필요:

#### 2.1 Prometheus 데이터 소스 추가

1. Grafana Console 접속 (outputs에서 `grafana_url` 확인)
2. **Configuration** → **Data Sources** → **Add data source**
3. **Prometheus** 선택
4. 설정:
   - **Name**: `Prometheus-MSK`
   - **URL**: `<prometheus_endpoint>` (terraform outputs에서 확인)
   - **Auth**: `SigV4 auth` 체크
   - **Region**: `ap-northeast-2` (또는 배포 리전)
5. **Save & Test**

#### 2.2 CloudWatch 데이터 소스 추가

1. **Add data source** → **CloudWatch**
2. 설정:
   - **Name**: `CloudWatch-MSK`
   - **Auth Provider**: `AWS SDK Default`
   - **Default Region**: `ap-northeast-2`
3. **Save & Test**

### 3. Grafana Dashboard Import

#### 3.1 Prometheus Dashboard (Topic/Consumer 상세 메트릭)

1. **Dashboards** → **Import**
2. **Upload JSON file**: `terraform/templates/grafana-msk-dashboard.json`
3. **Prometheus 데이터 소스 선택**: `Prometheus-MSK`
4. **Import**

#### 3.2 CloudWatch Dashboard

CloudWatch Dashboard는 AWS Console에서 자동 생성됩니다:
- URL: `<dashboard_url>` (terraform outputs 확인)
- 또는 CloudWatch Console → Dashboards → `msk-ha-cluster-dashboard`

## 모니터링 메트릭

### Prometheus (Grafana)

**Topic별 상세 메트릭:**
- Messages In/sec per topic
- Bytes In/sec per topic
- Consumer Lag by topic & consumer group
- Consumer Lag by partition

**Broker 메트릭:**
- CPU, Memory, JVM Heap 사용률
- Under Replicated Partitions
- Request latency (Produce/Fetch)

### CloudWatch (AWS Console)

**클러스터 전체 메트릭:**
- Messages/Bytes In/Out (Total)
- Consumer Lag (Total & Time)
- Broker Health (CPU, Disk, Memory)
- Partition Health (Under Replicated, Offline)
- Lambda Functions (Producer/Consumer)

## 접근 방법

### AWS Managed Grafana

```bash
# Terraform outputs에서 URL 확인
terraform output grafana_url

# 브라우저에서 접속 (AWS SSO 로그인 필요)
```

### CloudWatch Dashboard

```bash
# Terraform outputs에서 URL 확인
terraform output dashboard_url

# 또는 AWS Console
# CloudWatch → Dashboards → msk-ha-cluster-dashboard
```

### Bastion/Kafka-UI 접속

```bash
# Bastion IP 확인
terraform output bastion_public_ip

# SSH 접속
ssh -i <your-key.pem> ec2-user@<bastion-ip>

# Kafka-UI 접속 (브라우저)
http://<bastion-ip>:8080

# Prometheus Agent 상태 확인
sudo systemctl status prometheus
sudo journalctl -u prometheus -f
```

## 트러블슈팅

### Grafana에서 메트릭이 안보일 때

1. **Prometheus 데이터 소스 확인**:
   ```bash
   # Bastion SSH 접속
   ssh -i <key> ec2-user@<bastion-ip>

   # Prometheus 로그 확인
   sudo journalctl -u prometheus -n 100

   # MSK 브로커 접속 확인
   curl http://b-1.msk-ha-cluster.<region>.amazonaws.com:11001/metrics
   ```

2. **Prometheus Remote Write 확인**:
   ```bash
   # Prometheus 설정 확인
   cat /opt/prometheus/prometheus.yml

   # IAM 권한 확인 (CloudWatch Logs)
   # EC2가 Prometheus에 쓰기 권한이 있는지 확인
   ```

3. **보안그룹 확인**:
   ```bash
   # Bastion이 MSK 11001, 11002 포트에 접근 가능한지 확인
   telnet b-1.msk-ha-cluster.<region>.amazonaws.com 11001
   ```

### CloudWatch 메트릭이 안보일 때

1. **Enhanced Monitoring 활성화 확인** (main.tf:111):
   ```hcl
   enhanced_monitoring = "PER_TOPIC_PER_BROKER"
   ```

2. **MSK 클러스터가 실행중인지 확인**:
   ```bash
   aws kafka describe-cluster --cluster-arn <cluster-arn>
   ```

3. **메트릭 생성 대기** (최대 5-10분 소요):
   - Producer Lambda 호출로 메트릭 생성:
     ```bash
     curl -X POST <api-endpoint>/publish \
       -H "Content-Type: application/json" \
       -d '{"message": "test"}'
     ```

### Consumer Lag 메트릭이 없을 때

Consumer Lag는 실제 Consumer Group이 있어야 수집됩니다:

```bash
# Consumer Lambda 확인
aws lambda invoke --function-name msk-ha-cluster-consumer /tmp/output.json

# Event Source Mapping 확인
aws lambda list-event-source-mappings \
  --function-name msk-ha-cluster-consumer
```

## 비용 최적화

### 현재 구성 예상 비용 (ap-northeast-2 기준)

- **AWS Managed Grafana**: $9/월 (Workspace)
- **Amazon Managed Prometheus**: ~$5-10/월 (수집/저장량에 따라)
- **Bastion EC2 (t3.small)**: ~$15/월
- **MSK (3 x kafka.m5.large)**: ~$600/월

### 절감 방안

1. **Prometheus 수집 간격 조정** (bastion-init.sh):
   ```yaml
   scrape_interval: 60s  # 30s → 60s
   ```

2. **Prometheus 보관 기간 단축** (bastion-init.sh):
   ```yaml
   storage.tsdb.retention.time: 2h  # 로컬만 유지
   ```

3. **개발 환경에서는 CloudWatch만 사용**:
   - Prometheus/Grafana 비활성화
   - CloudWatch Dashboard만 사용

## 보안 체크리스트

- [x] SSH 포트 (22) - `allowed_cidr_blocks`로 제한
- [x] Kafka-UI (8080) - `allowed_cidr_blocks`로 제한
- [x] Prometheus 메트릭 (11001, 11002) - Bastion 보안그룹만 허용
- [x] Prometheus UI (9090) - localhost만 허용 (127.0.0.1:9090)
- [x] MSK Kafka (9092-9098) - VPC 내부만 허용
- [x] Lambda IAM 권한 - 특정 MSK 클러스터만 접근
- [x] Grafana IAM 권한 - CloudWatch/Prometheus 읽기만 허용
- [x] Bastion IAM 권한 - Prometheus 쓰기만 허용

## 추가 개선 사항

### 알림 설정

Grafana Alert Manager 설정 예시:

```yaml
# Grafana Alerting 설정
- alert: HighConsumerLag
  expr: kafka_consumergroup_lag > 10000
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Consumer lag is high"
```

### 커스텀 메트릭 추가

JMX Exporter 설정 확장 (MSK Configuration):
```properties
# MSK의 JMX Exporter는 기본 제공되므로 추가 설정 불필요
# 커스텀 메트릭이 필요한 경우 별도 JMX Exporter 배포 필요
```

## 참고 자료

- [AWS Managed Grafana 공식 문서](https://docs.aws.amazon.com/grafana/)
- [Amazon Managed Prometheus 공식 문서](https://docs.aws.amazon.com/prometheus/)
- [MSK Monitoring](https://docs.aws.amazon.com/msk/latest/developerguide/monitoring.html)
- [Kafka JMX Metrics](https://kafka.apache.org/documentation/#monitoring)
