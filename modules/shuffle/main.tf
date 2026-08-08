# --- 최신 Ubuntu 22.04 LTS AMI 조회 ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- 보안그룹: Shuffle SOAR용 ---
# INTENTIONALLY PERMISSIVE - FOR LAB USE ONLY
# 대시보드/웹훅(3001)은 실습 편의를 위해 0.0.0.0/0으로 개방 (wazuh 모듈과 동일 패턴).
# 이렇게 열어야 브라우저로 워크플로를 만들면서 동시에 Wazuh가 보내는 웹훅도 같은
# 포트로 받을 수 있다. 운영 환경이라면 관리자 IP + wazuh SG로 제한할 것.
resource "aws_security_group" "shuffle" {
  name_prefix = "${var.project_name}-shuffle-sg-"
  description = "Shuffle SOAR frontend/webhook"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    description = "SSH - INTENTIONALLY OPEN TO INTERNET FOR LAB USE ONLY"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Shuffle dashboard / webhook intake (HTTP)"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Shuffle dashboard / webhook intake (HTTPS)"
    from_port   = 3443
    to_port     = 3443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-shuffle-sg"
  })
}

# --- IAM 역할: SSM 세션 접속용. 1단계(알림/티켓 중심)는 AWS API 조치를 하지 않으므로
# 그 외 쓰기 권한은 부여하지 않는다. 나중에 자동조치(예: iam:UpdateAccessKey로 유출된
# 키 비활성화)를 추가하려면 이 role에 최소 권한 정책을 별도로 붙일 것. ---
resource "aws_iam_role" "shuffle_ec2" {
  name = "${var.project_name}-shuffle-ec2-role"

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

resource "aws_iam_role_policy_attachment" "shuffle_ssm" {
  role       = aws_iam_role.shuffle_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "shuffle_ec2" {
  name = "${var.project_name}-shuffle-ec2-profile"
  role = aws_iam_role.shuffle_ec2.name
}

# --- Shuffle SOAR (frontend + backend + orborus + opensearch, docker compose 단일 노드) ---
resource "aws_instance" "shuffle" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.small"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.shuffle.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.shuffle_ec2.name
  # user_data는 최초 부팅 때만 실행되므로, 브랜치/시크릿이 바뀌면 새로 만들어 재실행되게 함
  user_data_replace_on_change = true

  # 기본 8GB로는 backend/frontend/orborus/opensearch/worker 이미지까지 받으면 디스크가 꽉 참
  root_block_device {
    volume_size = 40
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # t3.medium(4GB RAM)에서 opensearch + 나머지 컨테이너가 안정적으로 뜨도록 스왑 추가
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    apt-get update -y
    apt-get install -y git ca-certificates curl
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu

    git clone -b ${var.soar_git_ref} https://github.com/autosoc-lab/vuln-hospital-booking-soar /opt/soar
    cd /opt/soar

    mkdir -p shuffle-apps shuffle-files shuffle-database
    cp .env.example .env

    # IMDSv2 토큰 기반 조회 (계정이 IMDSv2를 강제하는 경우에도 동작)
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

    sed -i "s|^BASE_URL=.*|BASE_URL=http://$PUBLIC_IP:5001|" .env
    sed -i "s|^SSO_REDIRECT_URL=.*|SSO_REDIRECT_URL=http://$PUBLIC_IP:3001|" .env
    sed -i "s|^SHUFFLE_ENCRYPTION_MODIFIER=.*|SHUFFLE_ENCRYPTION_MODIFIER=${var.shuffle_encryption_modifier}|" .env
    sed -i "s|^SHUFFLE_OPENSEARCH_PASSWORD=.*|SHUFFLE_OPENSEARCH_PASSWORD=${var.shuffle_opensearch_password}|" .env
    sed -i "s|^OPENSEARCH_INITIAL_ADMIN_PASSWORD=.*|OPENSEARCH_INITIAL_ADMIN_PASSWORD=${var.shuffle_opensearch_password}|" .env
    sed -i "s|^SHUFFLE_DEFAULT_USERNAME=.*|SHUFFLE_DEFAULT_USERNAME=${var.shuffle_admin_username}|" .env
    sed -i "s|^SHUFFLE_DEFAULT_PASSWORD=.*|SHUFFLE_DEFAULT_PASSWORD=${var.shuffle_admin_password}|" .env

    docker compose up -d

    # 워크플로 자동 복원 (재배포 시 workflows/*.json 을 Shuffle 에 import).
    # 실패해도 부팅은 계속됨 — 그 경우 Shuffle UI(Workflows -> Import)로 수동 복원.
    bash /opt/soar/bootstrap-import.sh >> /var/log/shuffle-bootstrap.log 2>&1 || true
  EOF

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-shuffle-server"
  })
}

# --- Elastic IP ---
resource "aws_eip" "shuffle" {
  instance = aws_instance.shuffle.id
  domain   = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-shuffle-eip"
  })
}
