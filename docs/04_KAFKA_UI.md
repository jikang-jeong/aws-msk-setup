# Kafka-UI 설정 가이드

## 개요
Bastion EC2에서 kafka-ui를 Docker로 실행하여 MSK 클러스터를 관리합니다.

> **전제 조건**: [02_TERRAFORM_DEPLOY.md](./02_TERRAFORM_DEPLOY.md)에서 `terraform apply` 완료 후 진행

---

## 1. Bastion 접속

**프로젝트 루트에서:**
```bash
# 프로젝트 루트에 msk-key.pem이 있는 경우
ssh -i msk-key.pem ec2-user@$(cd terraform && terraform output -raw bastion_public_ip)
```

**terraform 폴더에서:**
```bash
cd terraform
ssh -i ../msk-key.pem ec2-user@$(terraform output -raw bastion_public_ip)
```

---

## 2. Kafka-UI 실행

```bash
# 부트스트랩 서버 확인 (로컬에서)
cd terraform && terraform output bootstrap_brokers_tls

# EC2에서 실행 (위 출력값을 복사해서 붙여넣기)
docker run -d -p 8080:8080 \
  --name kafka-ui \
  --restart unless-stopped \
  -e KAFKA_CLUSTERS_0_NAME=msk \
  -e KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS="b-1.xxx:9094,b-2.xxx:9094,b-3.xxx:9094" \
  -e KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL=SSL \
  provectuslabs/kafka-ui
```

> ⚠️ `BOOTSTRAPSERVERS` 값은 `terraform output bootstrap_brokers_tls` 결과로 교체하세요.

---

## 3. 접속

브라우저에서:
```
http://<bastion_public_ip>:8080
```

---

## 4. Kafka-UI 기능

### 토픽 관리
- 토픽 생성/삭제/조회
- 파티션 수, RF, minISR 설정
- 토픽 설정 변경

### 메시지 관리
- 메시지 조회 (파티션별, 오프셋별)
- 메시지 발행 (테스트용)
- 메시지 검색

### 모니터링
- Consumer Group Lag 실시간 확인
- 브로커 상태 확인
- 파티션별 오프셋 확인
- 토픽별 메시지 수

---

## 5. 토픽 생성 (UI에서)

1. **Topics** → **Add Topic**
2. 설정:
   - **Name**: `test-topic`
   - **Partitions**: `6`
   - **Replication Factor**: `3`
   - **Custom Parameters** → Add:
     - Key: `min.insync.replicas`
     - Value: `2`
3. **Create**

---

## 6. 관리 명령어

```bash
# 로그 확인
docker logs kafka-ui

# 재시작
docker restart kafka-ui

# 중지
docker stop kafka-ui

# 삭제
docker rm kafka-ui

# 재실행 (중지 후)
docker start kafka-ui
```

---

## 7. 보안 참고

### 현재 보안 설정 (terraform/bastion.tf)

✅ **8080 포트는 이미 제한되어 있습니다:**
```hcl
ingress {
  from_port   = 8080
  to_port     = 8080
  protocol    = "tcp"
  cidr_blocks = var.allowed_cidr_blocks  # terraform/variables.tf에서 설정한 IP만 허용
  description = "Kafka-UI access from allowed IPs"
}
```

### 접근 가능한 IP 확인

```bash
cd terraform
terraform state show aws_security_group.bastion | grep -A 5 "8080"
```

### 추가 보안 강화 (선택)

**1. Kafka-UI 인증 활성화:**
```bash
docker run -d -p 8080:8080 \
  --name kafka-ui \
  --restart unless-stopped \
  -e AUTH_TYPE=LOGIN_FORM \
  -e SPRING_SECURITY_USER_NAME=admin \
  -e SPRING_SECURITY_USER_PASSWORD=<strong-password> \
  -e KAFKA_CLUSTERS_0_NAME=msk \
  -e KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS="..." \
  -e KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL=SSL \
  provectuslabs/kafka-ui
```

**2. SSH 터널링 사용 (가장 안전):**
```bash
# 로컬에서 SSH 터널 생성
ssh -i msk-key.pem -L 8080:localhost:8080 ec2-user@<bastion-ip>

# 브라우저에서 접속
http://localhost:8080  # 로컬에서만 접근 가능
```

이 경우 8080 포트를 보안그룹에서 제거 가능

---

## 8. 트러블슈팅

### kafka-ui가 MSK에 연결 안 됨
```bash
# 로그 확인
docker logs kafka-ui

# 부트스트랩 서버 주소 확인
# 콤마로 구분된 3개 브로커 주소가 정확한지 확인
```

### Docker 명령어 권한 에러
```bash
# ec2-user를 docker 그룹에 추가 (이미 user_data에서 처리됨)
sudo usermod -aG docker ec2-user

# 재로그인
exit
ssh -i ../msk-key.pem ec2-user@<bastion-ip>  # terraform 폴더에서
# 또는
ssh -i msk-key.pem ec2-user@<bastion-ip>     # 프로젝트 루트에서
```
