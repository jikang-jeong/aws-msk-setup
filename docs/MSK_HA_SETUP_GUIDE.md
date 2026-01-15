# Amazon MSK 고가용성 클러스터 설정 가이드

## 개요
이 가이드는 보안 패치 및 롤링 업데이트 중에도 클라이언트 I/O 중단 없이 운영 가능한 MSK 클러스터 구성 방법을 설명합니다.

---

## 0. Express vs Standard 브로커 비교

### 핵심 차이점

| 항목 | Express | Standard |
|------|---------|----------|
| **스토리지** | 무제한, 자동 관리 (pay-as-you-go) | EBS 직접 관리, 프로비저닝 필요 |
| **처리량** | 브로커당 최대 3배 높음 | 기본 처리량 |
| **스케일링 속도** | 최대 20배 빠름 | 일반 속도 |
| **복구 시간** | 90% 단축 | 일반 복구 시간 |
| **AZ 구성** | 3 AZ 고정 | 2 AZ 또는 3 AZ 선택 가능 |
| **인스턴스** | M7g 계열만 | T3, M5, M7g 계열 |
| **Kafka 버전** | 3.6, 3.8, 3.9 | 전체 버전 지원 |
| **기본 설정** | RF=3, minISR=2 자동 적용 | 수동 설정 필요 |
| **유지보수** | 자동 (유지보수 윈도우 불필요) | 유지보수 윈도우 필요 |

### 언제 Express를 선택?
- 스토리지 관리 부담 없이 운영하고 싶을 때
- 빠른 스케일링이 필요할 때
- 높은 처리량이 필요할 때
- 고가용성 기본 설정을 원할 때

### 언제 Standard를 선택?
- 세밀한 설정 제어가 필요할 때
- 2 AZ 구성이 필요할 때
- T3 인스턴스 타입이 필요할 때
- 3.6 미만 Kafka 버전이 필요할 때

### 주의사항
- Express ↔ Standard 간 브로커 타입 변경 불가 (새 클러스터 생성 필요)
- Express는 KStreams API 일부 미지원

---

## 1. 클러스터 설정 (서버 사이드)

### 1.1 3개 가용 영역 구성
- **필수**: 브로커를 3개 AZ에 분산 배치
- AZ 장애 시에도 서비스 지속 가능
- Express 브로커는 기본 3 AZ 분산

### 1.2 핵심 설정값

| 설정 | 권장값 | 설명 | 왜 필요한가? |
|------|--------|------|-------------|
| `default.replication.factor` | 3 | 토픽 기본 복제 계수 | RF=1이면 브로커 재시작 시 파티션 오프라인. RF=2면 데이터 손실 위험 |
| `min.insync.replicas` | 2 | 최소 동기화 복제본 수 (minISR < RF 필수) | RF=3일 때 minISR=3이면 브로커 1개 다운 시 쓰기 실패. minISR=2면 2개만 살아있어도 쓰기 가능 |
| `unclean.leader.election.enable` | false | 데이터 손실 방지 | true면 동기화 안 된 복제본이 리더가 되어 데이터 유실 가능 |
| `auto.create.topics.enable` | false | 의도치 않은 토픽 생성 방지 | 잘못된 토픽명으로 자동 생성 시 RF=1로 생성될 수 있음 |

**패치 중 동작 원리:**
1. MSK가 브로커를 하나씩 순차적으로 재시작 (롤링 업데이트)
2. 재시작되는 브로커의 리더 파티션이 일시적으로 오프라인
3. 다른 브로커의 팔로워 복제본이 새 리더로 승격
4. RF=3, minISR=2면 브로커 1개 다운 시에도 2개 복제본이 살아있어 쓰기/읽기 정상 동작

### 1.3 모니터링 알람 설정

| 메트릭 | 임계값 | 조치 | 왜 필요한가? |
|--------|--------|------|-------------|
| CPU (User + System) | > 60% | 브로커 스케일 업 | 패치 중 리더 재선출로 부하 증가. 여유 없으면 장애 확대 |
| KafkaDataLogsDiskUsed | > 85% | 스토리지 확장 | 디스크 풀 시 브로커 장애 |
| UnderReplicatedPartitions | > 0 | 복제 상태 확인 | 복제 지연 시 패치 중 데이터 손실 위험 |
| UnderMinIsrPartitionCount | > 0 | ISR 상태 확인 | minISR 미달 시 프로듀서 쓰기 실패 |

---

## 2. 클라이언트 설정

### 2.1 연결 문자열
```
# 각 AZ에서 최소 1개 브로커 포함
bootstrap.servers=b-1.cluster.xxx.kafka.ap-northeast-2.amazonaws.com:9094,b-2.cluster.xxx.kafka.ap-northeast-2.amazonaws.com:9094,b-3.cluster.xxx.kafka.ap-northeast-2.amazonaws.com:9094
```
**왜 필요한가?** 단일 브로커만 지정하면 해당 브로커 재시작 시 초기 연결 자체가 실패. 여러 AZ 브로커를 지정하면 failover 가능.

### 2.2 Producer 설정
```properties
# 고가용성 필수 설정
acks=all
retries=2147483647
retry.backoff.ms=100
delivery.timeout.ms=120000
request.timeout.ms=30000

# 성능 최적화
linger.ms=5
batch.size=16384
buffer.memory=33554432
compression.type=lz4
```
**왜 필요한가?**
- `acks=all`: 모든 ISR 복제본이 메시지를 받아야 성공. 리더만 받고 죽으면 데이터 손실
- `retries`: 브로커 재시작 중 일시적 오류 발생 시 자동 재시도
- `retry.backoff.ms`: 재시도 간격. 리더 재선출 시간 확보

### 2.3 Consumer 설정
```properties
# 고가용성 설정
auto.offset.reset=earliest
enable.auto.commit=false
isolation.level=read_committed

# 성능 최적화
fetch.min.bytes=1
fetch.max.wait.ms=500
max.poll.records=500
```
**왜 필요한가?**
- `enable.auto.commit=false`: 수동 커밋으로 메시지 처리 완료 후에만 오프셋 저장. 브로커 장애 시 중복 처리 방지
- `isolation.level=read_committed`: 트랜잭션 완료된 메시지만 읽어 일관성 보장

---

## 3. 토픽 생성 가이드

```bash
# 고가용성 토픽 생성
kafka-topics.sh --create \
  --bootstrap-server $BOOTSTRAP_SERVERS \
  --topic my-topic \
  --partitions 6 \
  --replication-factor 3 \
  --config min.insync.replicas=2
```

**파티션 수 권장사항:**
- 소형 인스턴스 (예: m5.large): 브로커당 최대 1,000개
- 대형 인스턴스 (예: m5.4xlarge): 브로커당 최대 4,000개

---

## 4. 배포 방법

```bash
cd terraform

# 초기화
terraform init

# 계획 확인
terraform plan

# 배포
terraform apply

# 부트스트랩 서버 확인
terraform output bootstrap_brokers_tls
```

---

## 5. 패치 중 체크리스트

- [ ] RF=3, minISR=2 확인
- [ ] 클라이언트 연결 문자열에 3개 AZ 브로커 포함
- [ ] Producer acks=all 설정
- [ ] 재시도 로직 활성화
- [ ] CPU 사용률 60% 미만 유지
- [ ] UnderReplicatedPartitions = 0 확인

---

## 참고 문서
- [MSK Best Practices](https://docs.aws.amazon.com/msk/latest/developerguide/bestpractices.html)
- [Kafka Client Best Practices](https://docs.aws.amazon.com/msk/latest/developerguide/bestpractices-kafka-client.html)
