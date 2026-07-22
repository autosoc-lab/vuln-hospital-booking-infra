output "manager_private_ip" {
  description = "Wazuh 매니저 프라이빗 IP (app 모듈 agent 등록용)"
  value       = aws_instance.wazuh.private_ip
}

output "dashboard_public_ip" {
  description = "Wazuh 대시보드 접속용 퍼블릭 IP (Elastic IP)"
  value       = aws_eip.wazuh.public_ip
}
