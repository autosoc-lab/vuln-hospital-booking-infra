output "vpc_id" {
  description = "생성된 VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = aws_subnet.private.id
}

output "private_subnet_ids" {
  description = "RDS DB Subnet Group용 Private subnet ID 목록 (최소 2개 AZ)"
  value       = [aws_subnet.private.id, aws_subnet.private_2.id]
}

output "ec2_security_group_id" {
  description = "EC2용 보안그룹 ID"
  value       = aws_security_group.ec2.id
}

output "rds_security_group_id" {
  description = "RDS용 보안그룹 ID"
  value       = aws_security_group.rds.id
}
