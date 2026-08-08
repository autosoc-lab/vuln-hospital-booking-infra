output "public_ip" {
  description = "Shuffle EC2 퍼블릭 IP (Elastic IP)"
  value       = aws_eip.shuffle.public_ip
}

output "dashboard_url" {
  description = "Shuffle 웹 UI URL (워크플로 생성, 웹훅 URL 확인용)"
  value       = "http://${aws_eip.shuffle.public_ip}:3001"
}

output "security_group_id" {
  description = "Shuffle EC2 보안그룹 ID"
  value       = aws_security_group.shuffle.id
}
