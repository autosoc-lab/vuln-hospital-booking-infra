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

- EC2 user_data가 `var.app_git_ref`(기본값 `lab/sqli-ec2-rds`, SQLi 실습 코드 병합 브랜치)를 clone하고, `docker-compose.yml`의 `DATABASE_URL`을 RDS 엔드포인트로 교체합니다.
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
