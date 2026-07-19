# 1. 보안 모니터링 계층 — S3 로그 버킷, CloudTrail, GuardDuty, CloudWatch Log Groups
# networking 모듈의 VPC Flow Logs가 참조할 로그 그룹을 먼저 생성한다.
module "security_monitoring" {
  source = "./modules/security_monitoring"

  project_name = var.project_name
  account_id   = local.account_id
  common_tags  = local.common_tags
}

# 2. 네트워킹 계층 — VPC, 서브넷, IGW, 라우팅, 보안그룹, VPC Flow Logs
module "networking" {
  source = "./modules/networking"

  project_name           = var.project_name
  common_tags            = local.common_tags
  flow_log_group_name    = module.security_monitoring.vpc_flow_log_group_name
  flow_log_group_arn     = module.security_monitoring.vpc_flow_log_group_arn
}

# 3. 애플리케이션 계층 — EC2, RDS, Elastic IP
module "app" {
  source = "./modules/app"

  project_name          = var.project_name
  key_pair_name         = var.key_pair_name
  db_username           = var.db_username
  db_password           = var.db_password
  common_tags           = local.common_tags
  public_subnet_id      = module.networking.public_subnet_id
  private_subnet_ids    = module.networking.private_subnet_ids
  ec2_security_group_id = module.networking.ec2_security_group_id
  rds_security_group_id = module.networking.rds_security_group_id
}
