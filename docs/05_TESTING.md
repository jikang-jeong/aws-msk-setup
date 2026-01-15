# 토픽 생성 및 테스트

Kafka 토픽을 생성하고 메시지를 발행/소비하여 시스템을 테스트합니다.

> **전제 조건**:
> - [02_TERRAFORM_DEPLOY.md](./02_TERRAFORM_DEPLOY.md)에서 `terraform apply` 완료
> - [03_MONITORING.md](./03_MONITORING.md) 모니터링 설정 완료 (선택)
> - [04_KAFKA_UI.md](./04_KAFKA_UI.md) Kafka-UI 설정 완료 (선택)

👈 이전: [04_KAFKA_UI.md](./04_KAFKA_UI.md)

---

## 📝 Kafka 토픽 생성

### Kafka-UI로 생성 (권장)
1. 브라우저에서 `http://<bastion_ip>:8080` 접속
2. Topics → "Add Topic" 클릭
3. 설정:
   - **Topic name**: `test-topic`
   - **Number of partitions**: `6`
   - **Replication factor**: `3`
   - **Configurations**:
     - `min.insync.replicas`: `2`
     - `retention.ms`: `604800000` (7일)
4. "Create topic" 클릭

### CLI로 생성
```bash
# Bastion 접속
ssh -i msk-key.pem ec2-user@$(terraform output -raw bastion_public_ip)

# Kafka CLI 설치
sudo yum install -y java-11
wget https://archive.apache.org/dist/kafka/3.6.0/kafka_2.13-3.6.0.tgz
tar -xzf kafka_2.13-3.6.0.tgz
cd kafka_2.13-3.6.0

# 토픽 생성
bin/kafka-topics.sh --bootstrap-server $(terraform output -raw bootstrap_brokers_tls) \
  --command-config client.properties \
  --create \
  --topic test-topic \
  --partitions 6 \
  --replication-factor 3 \
  --config min.insync.replicas=2
```

---

## 🚀 메시지 발행 테스트

### API Gateway로 발행
```bash
# 단일 메시지 발행
curl -X POST $(terraform output -raw api_endpoint)/publish \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello MSK"}'

# 대량 메시지 발행
curl -X POST $(terraform output -raw api_endpoint)/publish \
  -H "Content-Type: application/json" \
  -d '{"count": 1000, "data": "test message"}'

# 예상 응답:
# {"statusCode": 200, "body": "{\"message\": \"Published 1000 messages\"}"}
```

### 부하 테스트
```bash
# 10개 병렬 요청, 각 1000개 메시지
for i in {1..10}; do
  curl -X POST $(terraform output -raw api_endpoint)/publish \
    -H "Content-Type: application/json" \
    -d '{"count": 1000, "data": "load test"}' &
done
wait

echo "총 10,000개 메시지 발행 완료"
```

---

## 📥 메시지 소비 확인

### Lambda Consumer 로그
```bash
# 실시간 로그 확인
aws logs tail /aws/lambda/msk-ha-cluster-consumer \
  --follow \
  --region ap-northeast-2

# 최근 10분 로그
aws logs tail /aws/lambda/msk-ha-cluster-consumer \
  --since 10m \
  --region ap-northeast-2
```

### Kafka-UI에서 확인
1. Topics → test-topic
2. Messages 탭 → "Live Mode" 활성화
3. 발행된 메시지 실시간 확인

---

## ✅ 시스템 검증

### 1. 전체 시스템 상태
```bash
# MSK 클러스터
aws kafka describe-cluster \
  --cluster-arn $(terraform output -raw msk_cluster_arn) \
  --query 'ClusterInfo.State' \
  --region ap-northeast-2
# 출력: "ACTIVE"

# Lambda 함수
aws lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `msk-ha-cluster`)].{Name:FunctionName,State:State}' \
  --region ap-northeast-2
# 모두 "Active"

# Event Source Mapping
aws lambda list-event-source-mappings \
  --function-name msk-ha-cluster-consumer \
  --query 'EventSourceMappings[0].State' \
  --region ap-northeast-2
# 출력: "Enabled"
```

### 2. Prometheus 타겟 확인
```bash
# Bastion 접속 후
ssh -i msk-key.pem ec2-user@$(terraform output -raw bastion_public_ip)

# Prometheus 타겟 상태
curl -s http://127.0.0.1:9090/api/v1/targets | \
  jq '.data.activeTargets[] | {instance: .labels.instance, job: .labels.job, health: .health}'

# 모든 타겟이 "health": "up" 이어야 함
```

### 3. Grafana 대시보드
1. Grafana 접속: `terraform output grafana_url`
2. MSK Cluster Overview 대시보드 확인
3. 메트릭 표시 확인:
   - Messages Per Topic: 발행된 메시지 수
   - CPU Usage: 0-10%
   - Consumer Lag: 0 또는 낮은 값
   - Under Replicated Partitions: 0

---

## 📊 성능 벤치마크

### Producer 성능 테스트
```bash
# kafka-producer-perf-test (Bastion에서)
bin/kafka-producer-perf-test.sh \
  --topic test-topic \
  --num-records 100000 \
  --record-size 1000 \
  --throughput -1 \
  --producer-props \
    bootstrap.servers=$(terraform output -raw bootstrap_brokers_tls) \
    security.protocol=SSL

# 예상 결과:
# 100000 records sent, 20000 records/sec, 20 MB/sec
```

### Consumer 성능 테스트
```bash
# kafka-consumer-perf-test
bin/kafka-consumer-perf-test.sh \
  --topic test-topic \
  --messages 100000 \
  --bootstrap-server $(terraform output -raw bootstrap_brokers_tls) \
  --consumer.config client.properties
```

---

## 🐛 트러블슈팅

### Consumer가 메시지를 처리하지 않음
```bash
# Event Source Mapping 상태 확인
aws lambda list-event-source-mappings \
  --function-name msk-ha-cluster-consumer

# Disabled 상태면 재활성화
aws lambda update-event-source-mapping \
  --uuid <UUID> \
  --enabled

# Lambda 로그 확인
aws logs tail /aws/lambda/msk-ha-cluster-consumer --since 30m
```

### API Gateway 403 Forbidden
- authorization_type이 "NONE"인지 확인: `terraform/app.tf` 127줄

### 메시지가 Kafka-UI에 표시되지 않음
- 토픽 이름 확인: `test-topic`
- Bootstrap servers 확인

---

## 📚 다음 단계

시스템이 정상 작동합니다. 이제 MSK 고가용성 원리를 학습하세요.

👉 **[MSK_HA_SETUP_GUIDE.md](./MSK_HA_SETUP_GUIDE.md)** - MSK HA 원리

---

**마지막 업데이트:** 2026-01-15
