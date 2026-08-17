# --- 최신 Ubuntu 22.04 LTS AMI 조회 ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# admin_cidr에 마스크(/32 등)가 없으면 단일 IP로 보고 /32를 자동으로 붙인다.
# (사용자가 "1.2.3.4"만 넣어도 "1.2.3.4/32"로 처리)
locals {
  admin_cidr_norm = var.admin_cidr == "" ? "" : (
    length(regexall("/", var.admin_cidr)) > 0 ? var.admin_cidr : "${var.admin_cidr}/32"
  )
  app_instance_name      = "${var.project_name}-app-server"
  leaked_s3_key_user     = "${var.project_name}-leaked-s3-key"
  leaked_s3_key_user_arn = "arn:aws:iam::${var.account_id}:user/${local.leaked_s3_key_user}"
  documents_bucket_name  = "${var.project_name}-documents-${var.account_id}"
  documents_bucket_arn   = "arn:aws:s3:::${local.documents_bucket_name}"
}

# --- 보안그룹: Shuffle SOAR용 ---
# INTENTIONALLY PERMISSIVE - FOR LAB USE ONLY
# 3001/3443은 0.0.0.0/0으로 열지 않는다. 웹훅은 Wazuh가 VPC 내부(사설IP)로 보내므로
# vpc_cidr만 허용하면 되고, 대시보드는 관리자 IP(admin_cidr)만 허용한다. 이렇게 하면
# git에 웹훅 hook id가 있어도 외부에서 위조 POST를 보낼 수 없다(외부 도달 자체가 차단).
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
    description = "Shuffle HTTP - VPC internal (Wazuh webhook) + admin IP (dashboard)"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = compact([var.vpc_cidr, local.admin_cidr_norm])
  }

  ingress {
    description = "Shuffle HTTPS - VPC internal + admin IP"
    from_port   = 3443
    to_port     = 3443
    protocol    = "tcp"
    cidr_blocks = compact([var.vpc_cidr, local.admin_cidr_norm])
  }

  ingress {
    description = "SOAR response API - VPC internal Wazuh callback"
    from_port   = 8088
    to_port     = 8088
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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

resource "aws_iam_role_policy" "shuffle_soar_response" {
  name = "${var.project_name}-shuffle-soar-response-policy"
  role = aws_iam_role.shuffle_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeForTriage"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeSecurityGroups", "cloudtrail:LookupEvents"]
        Resource = "*"
      },
      {
        Sid      = "QuarantineOnlyLabAppInstance"
        Effect   = "Allow"
        Action   = ["ec2:ModifyInstanceAttribute", "ec2:CreateTags"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = var.project_name
            "ec2:ResourceTag/Name"    = local.app_instance_name
          }
        }
      },
      {
        Sid      = "DisableOnlyLabLeakedKey"
        Effect   = "Allow"
        Action   = ["iam:ListAccessKeys", "iam:UpdateAccessKey"]
        Resource = local.leaked_s3_key_user_arn
      },
      {
        Sid      = "ReadDocumentBucketForImpactReview"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:GetLifecycleConfiguration", "s3:ListBucket"]
        Resource = local.documents_bucket_arn
      },
      {
        Sid      = "ReadDocumentObjectMetadataForImpactReview"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${local.documents_bucket_arn}/*"
      }
    ]
  })
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

    # t3.small(2GB RAM)에서 opensearch + 나머지 컨테이너가 뜨도록 스왑 2G 추가 (총 4GB)
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    apt-get update -y
    apt-get install -y git ca-certificates curl awscli
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu

    git clone -b ${var.soar_git_ref} https://github.com/autosoc-lab/vuln-hospital-booking-soar /opt/soar
    cd /opt/soar

    # SOAR 대응 헬퍼는 Terraform 모듈에서도 직접 설치한다. 이렇게 해야 GitHub의
    # soar_git_ref가 아직 갱신되지 않아도 terraform apply 즉시 자동 대응이 동작한다.
    install -d -m 755 /opt/soar/scripts
    cat > /opt/soar/scripts/respond-ssh-compromise.sh <<'SOAR_RESPONSE_SCRIPT'
    ${file("${path.module}/files/respond-ssh-compromise.sh")}
    SOAR_RESPONSE_SCRIPT
    cat > /opt/soar/scripts/soar-response-api.py <<'SOAR_RESPONSE_API'
    ${file("${path.module}/files/soar-response-api.py")}
    SOAR_RESPONSE_API
    chmod 755 /opt/soar/scripts/respond-ssh-compromise.sh /opt/soar/scripts/soar-response-api.py

    mkdir -p shuffle-apps shuffle-files shuffle-database
    cp .env.example .env

    # IMDSv2 토큰 기반 조회 (계정이 IMDSv2를 강제하는 경우에도 동작)
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
    # orborus/worker가 backend에 도달할 때 쓰는 호스트. 컨테이너 기본값(shuffle-backend)으로
    # 두면 swarm worker가 backend를 못 찾아 워크플로가 EXECUTING에서 멈춘다 → 사설IP로 고정.
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

    sed -i "s|^BASE_URL=.*|BASE_URL=http://$PUBLIC_IP:5001|" .env
    sed -i "s|^SSO_REDIRECT_URL=.*|SSO_REDIRECT_URL=http://$PUBLIC_IP:3001|" .env
    sed -i "s|^OUTER_HOSTNAME=.*|OUTER_HOSTNAME=$PRIVATE_IP|" .env
    sed -i "s|^SHUFFLE_ENCRYPTION_MODIFIER=.*|SHUFFLE_ENCRYPTION_MODIFIER=${var.shuffle_encryption_modifier}|" .env
    sed -i "s|^SHUFFLE_OPENSEARCH_PASSWORD=.*|SHUFFLE_OPENSEARCH_PASSWORD=${var.shuffle_opensearch_password}|" .env
    sed -i "s|^OPENSEARCH_INITIAL_ADMIN_PASSWORD=.*|OPENSEARCH_INITIAL_ADMIN_PASSWORD=${var.shuffle_opensearch_password}|" .env
    sed -i "s|^SHUFFLE_DEFAULT_USERNAME=.*|SHUFFLE_DEFAULT_USERNAME=${var.shuffle_admin_username}|" .env
    sed -i "s|^SHUFFLE_DEFAULT_PASSWORD=.*|SHUFFLE_DEFAULT_PASSWORD=${var.shuffle_admin_password}|" .env

    # Discord 웹훅 URL을 .env에 추가 → bootstrap-import.sh가 워크플로의 Discord url에 주입.
    # .env.example엔 없는 키라 append. 빈 값이면 bootstrap이 주입을 건너뛴다.
    echo "DISCORD_WEBHOOK_URL=${var.discord_webhook_url}" >> .env
    echo "AWS_REGION=ap-northeast-2" >> .env
    echo "SOAR_APP_INSTANCE_TAG_NAME=${local.app_instance_name}" >> .env
    echo "SOAR_APP_SECURITY_GROUP_ID=${var.app_security_group_id}" >> .env
    echo "SOAR_QUARANTINE_SECURITY_GROUP_ID=${var.quarantine_security_group_id}" >> .env
    echo "SOAR_LEAKED_S3_KEY_USER_NAME=${local.leaked_s3_key_user}" >> .env
    echo "SOAR_DOCUMENTS_BUCKET=${local.documents_bucket_name}" >> .env

    cat > /etc/systemd/system/soar-response-api.service <<'SERVICE'
    [Unit]
    Description=Vuln Hospital SOAR response API
    After=network-online.target

    [Service]
    Type=simple
    EnvironmentFile=/opt/soar/.env
    ExecStart=/usr/bin/python3 /opt/soar/scripts/soar-response-api.py
    Restart=always
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
    SERVICE
    systemctl daemon-reload
    systemctl enable --now soar-response-api.service

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
