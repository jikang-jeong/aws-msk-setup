# MSK Pub/Sub Lambda App

## 개요
API Gateway → Lambda Producer → MSK → Lambda Consumer 파이프라인

---

## 배포 순서

### 1. Lambda 패키징
```bash
cd msk-ha-cluster/app
bash build.sh
```

생성 파일: `producer.zip`, `consumer.zip`

### 2. Terraform 배포
```bash
cd ../terraform
terraform apply
```

---

## 토픽 생성

### 방법 1: Kafka-UI (권장)
1. `http://<bastion_ip>:8080` 접속
2. Topics → Add Topic
3. 설정:
   - Name: `test-topic`
   - Partitions: `6`
   - Replication Factor: `3`
   - `min.insync.replicas`: `2`

### 방법 2: Kafka CLI
Bastion EC2에서:
```bash
# Kafka 다운로드
wget https://archive.apache.org/dist/kafka/3.6.0/kafka_2.13-3.6.0.tgz
tar -xzf kafka_2.13-3.6.0.tgz
cd kafka_2.13-3.6.0/bin

# 토픽 생성
./kafka-topics.sh --create \
  --bootstrap-server <bootstrap_brokers_tls> \
  --topic test-topic \
  --partitions 6 \
  --replication-factor 3 \
  --config min.insync.replicas=2
```

---

## 테스트

### 단일 메시지 발행
```bash
curl -X POST $(terraform output -raw api_endpoint)/publish \
  -H "Content-Type: application/json" \
  -d '{"data": "hello"}'
```

### 대량 메시지 발행 (부하 테스트)
```bash
curl -X POST $(terraform output -raw api_endpoint)/publish \
  -H "Content-Type: application/json" \
  -d '{"count": 1000, "data": "load-test"}'
```

---

## 모니터링

### CloudWatch 대시보드
```bash
# URL 확인
terraform output dashboard_url
```

**확인 가능한 메트릭:**
- 📥 Messages In (초당 메시지 수)
- 📤 Bytes Out (Consumer 읽기량)
- ⏳ Consumer Lag (밀린 메시지)
- 🔥 Lambda 호출 수
- ❌ Lambda 에러
- ⏱️ Iterator Age (처리 지연)
- 💻 브로커 CPU
- 💾 디스크 사용량

### Lambda 로그
```bash
# Producer 로그
aws logs tail /aws/lambda/msk-ha-cluster-producer --follow

# Consumer 로그
aws logs tail /aws/lambda/msk-ha-cluster-consumer --follow
```

Consumer 로그에 `Received: {"index": 0, "data": "load-test"}` 출력되면 성공.

### Kafka-UI
`http://<bastion_ip>:8080`에서:
- 토픽별 메시지 조회
- Consumer Group Lag 실시간 확인
- 파티션별 오프셋 확인

---

## 코드 수정 후 재배포

```bash
# 1. 코드 수정
vi producer.py  # 또는 consumer.py

# 2. 재빌드
bash build.sh

# 3. Lambda 업데이트
aws lambda update-function-code \
  --function-name msk-ha-cluster-producer \
  --zip-file fileb://producer.zip \
  --region ap-northeast-2

aws lambda update-function-code \
  --function-name msk-ha-cluster-consumer \
  --zip-file fileb://consumer.zip \
  --region ap-northeast-2
```

---

## 파일 구조
```
app/
├── producer.py       # Kafka Producer Lambda
├── consumer.py       # Kafka Consumer Lambda (100ms 지연)
├── requirements.txt  # kafka-python
├── build.sh          # Lambda zip 패키징
├── producer.zip      # 빌드 결과물
└── consumer.zip      # 빌드 결과물
```

---

## 주요 설정

### Producer
- 메시지 발행 API
- `count` 파라미터로 대량 발행 가능
- SSL 연결

### Consumer
- MSK Event Source Mapping으로 자동 트리거
- Batch Size: 100개
- 메시지당 100ms 지연 (Lag 시뮬레이션)
- Starting Position: LATEST
