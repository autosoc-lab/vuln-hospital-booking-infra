# 1. 보안 모니터링 계층 — S3 로그 버킷, CloudTrail, GuardDuty, CloudWatch Log Groups
# networking 모듈의 VPC Flow Logs가 참조할 로그 그룹을 먼저 생성한다.
module "security_monitoring" {
  source = "./modules/security_monitoring"

  project_name     = var.project_name
  account_id       = local.account_id
  common_tags      = local.common_tags
  enable_guardduty = var.enable_guardduty
}

# 2. 네트워킹 계층 — VPC, 서브넷, IGW, 라우팅, 보안그룹, VPC Flow Logs
module "networking" {
  source = "./modules/networking"

  project_name   = var.project_name
  common_tags    = local.common_tags
  log_bucket_arn = module.security_monitoring.log_bucket_arn
}

# EC2 SSH 키페어 — app/wazuh 모듈이 공유하므로 root에서 한 번만 생성
resource "aws_key_pair" "app" {
  key_name   = var.key_pair_name
  public_key = file("${path.root}/ssh/vuln-hospital-lab.pub")

  tags = local.common_tags
}

# 3. Wazuh 계층 — SIEM 매니저/인덱서/대시보드 (all-in-one)
# 앱 계층보다 먼저 생성되어야 함 (앱 EC2의 에이전트가 이 매니저 IP로 등록됨)
module "wazuh" {
  source = "./modules/wazuh"

  project_name          = var.project_name
  common_tags           = local.common_tags
  account_id            = local.account_id
  vpc_id                = module.networking.vpc_id
  public_subnet_id      = module.networking.public_subnet_id
  key_pair_name         = aws_key_pair.app.key_name
  app_security_group_id = module.networking.ec2_security_group_id
  log_bucket_name       = module.security_monitoring.log_bucket_name
  log_bucket_arn        = module.security_monitoring.log_bucket_arn
  wazuh_version         = var.wazuh_version
}

# 4. C2/수집 서버 — 공격자 소유로 가정하는 독립 EC2 (RCE/SSRF 실습에서 탈취 데이터를 받는 쪽)
module "c2" {
  source = "./modules/c2"

  project_name     = var.project_name
  common_tags      = local.common_tags
  public_subnet_id = module.networking.public_subnet_id
  key_pair_name    = aws_key_pair.app.key_name
  c2_git_ref       = var.c2_git_ref
  c2_lab_token     = var.c2_lab_token
}

# 5. 애플리케이션 계층 — EC2, RDS, Elastic IP
module "app" {
  source = "./modules/app"

  project_name             = var.project_name
  app_git_ref              = var.app_git_ref
  key_pair_name            = aws_key_pair.app.key_name
  db_username              = var.db_username
  db_password              = var.db_password
  common_tags              = local.common_tags
  account_id               = local.account_id
  public_subnet_id         = module.networking.public_subnet_id
  private_subnet_ids       = module.networking.private_subnet_ids
  ec2_security_group_id    = module.networking.ec2_security_group_id
  rds_security_group_id    = module.networking.rds_security_group_id
  wazuh_manager_private_ip = module.wazuh.manager_private_ip
  wazuh_version            = var.wazuh_version
}
