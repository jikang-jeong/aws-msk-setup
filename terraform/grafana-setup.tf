# Grafana 초기 설정 자동화

# 현재 AWS 사용자 정보
data "aws_caller_identity" "current" {}

# Grafana Admin 권한 부여 (grafana_admin_user_id가 설정된 경우에만 실행)
resource "null_resource" "grafana_admin_permissions" {
  count = var.grafana_admin_user_id != "" ? 1 : 0

  triggers = {
    workspace_id  = aws_grafana_workspace.msk.id
    admin_user_id = var.grafana_admin_user_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws grafana update-permissions \
        --workspace-id ${aws_grafana_workspace.msk.id} \
        --region ${var.region} \
        --update-instruction-batch '[{
          "action": "ADD",
          "role": "ADMIN",
          "users": [{
            "id": "${var.grafana_admin_user_id}",
            "type": "SSO_USER"
          }]
        }]'
    EOT
  }

  depends_on = [aws_grafana_workspace.msk]
}

# Grafana 데이터 소스 설정 가이드 생성
resource "local_file" "grafana_datasource_guide" {
  filename = "${path.module}/grafana-datasource-setup.sh"

  content = <<-EOT
#!/bin/bash
# Grafana 데이터 소스 자동 설정 스크립트
#
# 사용 방법:
# 1. Grafana에서 Service Account를 생성하고 토큰을 받습니다
# 2. 아래 GRAFANA_TOKEN 변수에 토큰을 입력합니다
# 3. 이 스크립트를 실행합니다: bash grafana-datasource-setup.sh

# 설정 변수
GRAFANA_WORKSPACE_ID="${aws_grafana_workspace.msk.id}"
GRAFANA_ENDPOINT="https://${aws_grafana_workspace.msk.endpoint}"
PROMETHEUS_ENDPOINT="${aws_prometheus_workspace.msk.prometheus_endpoint}"
REGION="${var.region}"

# Grafana Service Account Token (여기에 입력)
GRAFANA_TOKEN=""

if [ -z "$GRAFANA_TOKEN" ]; then
  echo "Error: GRAFANA_TOKEN이 설정되지 않았습니다."
  echo ""
  echo "Grafana Service Account Token 생성 방법:"
  echo "1. Grafana 워크스페이스 접속: $GRAFANA_ENDPOINT"
  echo "2. Configuration (⚙️) → Service accounts 메뉴"
  echo "3. 'Add service account' 클릭"
  echo "4. Name: terraform-provisioner, Role: Admin"
  echo "5. 'Add service account token' 클릭하여 토큰 생성"
  echo "6. 생성된 토큰을 이 스크립트의 GRAFANA_TOKEN 변수에 입력"
  echo ""
  exit 1
fi

echo "=== Grafana 데이터 소스 설정 시작 ==="

# 1. Amazon Managed Prometheus 데이터 소스 추가
echo "1. Prometheus 데이터 소스 추가 중..."
curl -X POST "$GRAFANA_ENDPOINT/api/datasources" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Amazon Managed Prometheus",
    "type": "prometheus",
    "url": "'"$PROMETHEUS_ENDPOINT"'",
    "access": "proxy",
    "isDefault": true,
    "jsonData": {
      "httpMethod": "POST",
      "sigV4Auth": true,
      "sigV4AuthType": "default",
      "sigV4Region": "'"$REGION"'"
    }
  }'

echo ""
echo "2. CloudWatch 데이터 소스 추가 중..."
curl -X POST "$GRAFANA_ENDPOINT/api/datasources" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "CloudWatch",
    "type": "cloudwatch",
    "access": "proxy",
    "jsonData": {
      "authType": "default",
      "defaultRegion": "'"$REGION"'"
    }
  }'

echo ""
echo "=== 데이터 소스 설정 완료 ==="
echo ""
echo "Grafana 대시보드 URL: $GRAFANA_ENDPOINT"
EOT

  file_permission = "0755"

  depends_on = [
    aws_grafana_workspace.msk,
    aws_prometheus_workspace.msk
  ]
}

# Output: 데이터 소스 설정 가이드
output "grafana_datasource_setup_guide" {
  value = <<-EOT

  ===== Grafana 데이터 소스 자동 설정 =====

  Admin 권한이 부여되었습니다. 이제 데이터 소스를 추가하세요:

  방법 1: Grafana UI에서 수동 추가 (가장 쉬움)
  ----------------------------------------
  1. Grafana 접속: https://${aws_grafana_workspace.msk.endpoint}

  2. Prometheus 데이터 소스 추가:
     - Configuration (⚙️) → Data sources → Add data source
     - "Amazon Managed Service for Prometheus" 선택
     - Name: Amazon Managed Prometheus
     - Authentication: AWS SDK Default
     - Default Region: ${var.region}
     - Service endpoint: ${aws_prometheus_workspace.msk.prometheus_endpoint}
     - Save & test

  3. CloudWatch 데이터 소스 추가:
     - Add data source → "CloudWatch" 선택
     - Authentication: AWS SDK Default
     - Default Region: ${var.region}
     - Save & test

  방법 2: 자동 설정 스크립트 사용
  --------------------------------
  1. Service Account 생성:
     - Grafana에서 Configuration → Service accounts
     - "Add service account" (Name: terraform, Role: Admin)
     - "Add service account token" 클릭하여 토큰 생성

  2. 스크립트 실행:
     cd terraform
     # 스크립트에서 GRAFANA_TOKEN 변수에 토큰 입력
     ./grafana-datasource-setup.sh

  ==========================================
  EOT
}
