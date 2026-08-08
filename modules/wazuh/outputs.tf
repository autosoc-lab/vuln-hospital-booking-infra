output "manager_private_ip" {
  description = "Wazuh 매니저 프라이빗 IP (app 모듈 agent 등록용)"
  value       = aws_instance.wazuh.private_ip
}

output "manager_public_ip" {
  description = "Wazuh 매니저 퍼블릭 IP (SSH/API/대시보드 접속용, Elastic IP)"
  value       = aws_eip.wazuh.public_ip
}

output "security_group_id" {
  description = "Wazuh 매니저 보안그룹 ID (shuffle 모듈이 이 SG발 웹훅 트래픽만 허용하기 위해 참조)"
  value       = aws_security_group.wazuh.id
}
