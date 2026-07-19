output "ec2_public_ip" {
  description = "EC2 인스턴스 퍼블릭 IP (Elastic IP)"
  value       = aws_eip.app.public_ip
}

output "rds_endpoint" {
  description = "RDS PostgreSQL 엔드포인트"
  value       = aws_db_instance.postgres.endpoint
}
