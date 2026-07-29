output "public_ip" {
  description = "C2/수집 서버 퍼블릭 IP (Elastic IP)"
  value       = aws_eip.c2.public_ip
}
