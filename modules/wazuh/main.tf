# --- 최신 Ubuntu 22.04 LTS AMI 조회 ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- 보안그룹: Wazuh 매니저용 ---
# INTENTIONALLY PERMISSIVE - FOR LAB USE ONLY
# 대시보드(443)/API(55000)는 실습 편의를 위해 0.0.0.0/0으로 개방 (다른 EC2 SG와 동일한 패턴)
resource "aws_security_group" "wazuh" {
  name        = "${var.project_name}-wazuh-sg"
  description = "Wazuh manager/indexer/dashboard"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH - INTENTIONALLY OPEN TO INTERNET FOR LAB USE ONLY"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Wazuh Dashboard"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Wazuh API"
    from_port   = 55000
    to_port     = 55000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Agent 이벤트 수신 (앱 EC2에서만)"
    from_port       = 1514
    to_port         = 1514
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  ingress {
    description     = "Agent 이벤트 수신 UDP (앱 EC2에서만)"
    from_port       = 1514
    to_port         = 1514
    protocol        = "udp"
    security_groups = [var.app_security_group_id]
  }

  ingress {
    description     = "Agent 등록 (앱 EC2에서만)"
    from_port       = 1515
    to_port         = 1515
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wazuh-sg"
  })
}

# --- IAM 역할: 로그 버킷(CloudTrail/VPC Flow Logs/GuardDuty) 읽기 전용 ---
resource "aws_iam_role" "wazuh_ec2" {
  name = "${var.project_name}-wazuh-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "wazuh_logs_read" {
  name = "${var.project_name}-wazuh-logs-read-policy"
  role = aws_iam_role.wazuh_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.log_bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${var.log_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "wazuh_ssm" {
  role       = aws_iam_role.wazuh_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "wazuh_ec2" {
  name = "${var.project_name}-wazuh-ec2-profile"
  role = aws_iam_role.wazuh_ec2.name
}

# --- Wazuh 매니저/인덱서/대시보드 (all-in-one 단일 노드) ---
resource "aws_instance" "wazuh" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.wazuh.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.wazuh_ec2.name

  root_block_device {
    volume_size = 50
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Wazuh all-in-one 설치 (manager + indexer + dashboard)
    curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
    bash wazuh-install.sh -a --ignore-check

    # wodle aws-s3: CloudTrail/VPC Flow Logs/GuardDuty를 S3에서 읽어오도록 설정
    printf '%s\n' \
      '  <wodle name="aws-s3">' \
      '    <disabled>no</disabled>' \
      '    <interval>10m</interval>' \
      '    <run_on_start>yes</run_on_start>' \
      '    <bucket type="cloudtrail">' \
      "      <name>${var.log_bucket_name}</name>" \
      '      <path>AWSLogs</path>' \
      '    </bucket>' \
      '    <bucket type="vpcflow">' \
      "      <name>${var.log_bucket_name}</name>" \
      '    </bucket>' \
      '    <bucket type="guardduty">' \
      "      <name>${var.log_bucket_name}</name>" \
      '      <path>guardduty</path>' \
      '    </bucket>' \
      '  </wodle>' > /tmp/wodle_block.xml

    sed -i '/<ossec_config>/r /tmp/wodle_block.xml' /var/ossec/etc/ossec.conf
    systemctl restart wazuh-manager
  EOF

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wazuh-server"
  })
}

# --- Elastic IP ---
resource "aws_eip" "wazuh" {
  instance = aws_instance.wazuh.id
  domain   = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wazuh-eip"
  })
}
