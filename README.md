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
