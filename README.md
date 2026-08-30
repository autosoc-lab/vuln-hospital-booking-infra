# vuln-hospital-booking-infra

`vuln-hospital-booking` 앱을 위한 AWS 인프라를 Terraform으로 구성합니다.
SIEM/SOAR 실습을 위해 **의도적으로 취약하게** 구성된 환경이며, 공격 시뮬레이션 및 탐지 파이프라인 실습 용도입니다.

## 프로젝트 구조

```
modules/
  networking/            VPC · 서브넷 · IGW · 보안그룹
  app/                   WEB EC2 · RDS · Document S3 · WAF
  wazuh/                 Wazuh 매니저 EC2 · 커스텀 룰/디코더
  shuffle/                Shuffle(SOAR) EC2
  c2/                     공격자 C2 EC2
  security_monitoring/    CloudTrail · VPC Flow Logs · Logs S3 · GuardDuty(`enable_guardduty`로 끌 수 있음)
main.tf                   위 모듈을 조립하는 루트 구성
terraform.tfvars          실제 값 입력 (git 추적 제외)
ssh/                      유출 SSH 키 실습용 키페어
```

## 주의사항

- 이 인프라는 **보안 실습 전용**이며 프로덕션 사용을 금지합니다.
- GuardDuty(기본값 활성화), CloudTrail은 과금이 발생합니다 — 실습 후 반드시 `terraform destroy` 하세요. `enable_guardduty = false`로 끌 수 있습니다.
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

`terraform.tfvars`는 `.gitignore`에 포함되어 있어 직접 생성해야 합니다. 기본값이 없는 변수
(`key_pair_name`, `db_password`, `c2_lab_token`, `shuffle_admin_password`, `shuffle_encryption_modifier`,
`shuffle_opensearch_password`)는 반드시 채워야 `apply`가 됩니다.

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

## SSRF 기반 랜섬웨어 침해 실습

이 인프라는 앱 EC2에 SSRF → EC2 임시 자격증명 탈취 → S3 SSE-C 랜섬웨어까지 이어지는 체인이 가능하도록
의도적으로 과다 권한과 취약 설정을 함께 구성합니다.

구성 요소:

- `metadata_options`(`http_tokens = "optional"`): IMDSv1을 허용해 SSRF만으로 토큰 없이 임시 자격증명을 조회 가능
- EC2 IAM Role(`ec2_ssm`): `AmazonS3FullAccess`를 통째로 부여(의도적 과다 권한) + 자기 role 정책 열람·계정 전체 버킷 열거 권한 — 탈취한 자격증명만으로 반출부터 SSE-C 재암호화, lifecycle 삭제 설정까지 전체 체인 수행 가능
- Document S3 버킷(`documents`): 기본 서버측 암호화를 걸지 않음(SSE-C 업로드를 막는 AWS `BlockedEncryptionTypes` 정책 회피 목적) + 버저닝은 켜져 있지만 lifecycle로 이전 버전까지 삭제 가능
- C2 EC2(`modules/c2`): 재암호화한 문서를 반출받는 대상 서버

실습 커맨드는 Notion 문서를 참고하세요.

https://app.notion.com/p/SSRF-to-S3-SSE-C-Ransomware-Attack-Chain-PoC-3ababddcd58880cf9202eb18be524d89

## 유출 SSH 키 기반 EC2 침해 실습

이 인프라는 앱 EC2에 유출 SSH 키 시나리오용 `deploy` 계정과 의도적으로 취약한 root 백업 작업을 함께 구성합니다.

구성 요소:

- `deploy` 계정: `ssh/vuln-hospital-lab.pem` 키로 접속 가능, `hospital-ops` 그룹 소속
- `/etc/systemd/system/hospital-db-backup.timer`: root 권한으로 15분마다 백업 서비스 실행
- `/usr/local/sbin/hospital-db-backup.sh`: root 소유 백업 스크립트
- `/opt/hospital/bin/hospital-backup-helper`: root 백업 스크립트가 호출하지만 `hospital-ops` 그룹에 쓰기 권한이 있는 취약 헬퍼
- `/var/backups/hospital-db/hospital-backup-heartbeat.log`: 실제 DB 덤프 대신 helper 실행 시각과 실행 UID만 남기는 실습용 표식 로그
- `/etc/vuln-hospital-booking/app.env`: root만 읽을 수 있는 DB/S3 앱 설정
- auditd/Wazuh FIM: 정찰 명령, 백업 경로 조사, 헬퍼 변조, root 표식 파일, 설정 복사, 수집/압축/전송/삭제 행위 감시

실습 커맨드는 Notion 문서를 참고하세요.

https://app.notion.com/p/SSH-EC2-POC-3b6abddcd58880d3bbafc25ff184736b

## Wazuh 탐지 룰

SSRF·SSE-C·SSH 침해 시나리오별 커스텀 룰 ID, 레벨, MITRE 매핑, SOAR 자동 대응 연동은
[`WAZUH_RULES.md`](WAZUH_RULES.md)에 정리되어 있습니다.
