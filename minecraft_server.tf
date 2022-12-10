terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }

    namecheap = {
      source  = "namecheap/namecheap"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket = "MYAWSS3BUCKET"
    region = "MYAWSREGION"
    key    = "MYAWSS3KEY"
  }
}

provider "namecheap" {
  user_name   = var.namecheap_user_name
  api_user    = var.namecheap_user_name
  api_key     = var.namecheap_api_key
  use_sandbox = false
}

provider "aws" {
  region = var.aws_region
}

locals {
  minecraft_server_icon = filebase64("${path.module}/server-icon.png")
  user_data             = <<EOF
#!/bin/sh
set -e
## setup swap
mkswap /dev/xvds
SWAPPINESS='vm.swappiness=1'
SWAPUUID=$(blkid | grep 'TYPE="swap"' | awk '{print $2}' | sed 's/"//g')
SWAPFSTAB="$SWAPUUID       swap    swap    defaults        0       0"
## setup nfs volume
NFSFSTAB="${aws_efs_mount_target.minecraft_server.dns_name}:/ /data       nfs       rw,hard,intr        0       0"
echo $SWAPFSTAB >> /etc/fstab
echo $NFSFSTAB >> /etc/fstab
mkdir /data
mount -a
echo "mounted on $(date)" >> /data/mounted.log
## setup minecraft dir
mkdir -p /data/mc
echo '${local.minecraft_server_icon}' | base64 -d > /data/mc/server-icon.png
## finish swap setup
swapon -a
echo $SWAPPINESS > /etc/sysctl.d/90-swappiness.conf
sysctl -p /etc/sysctl.d/90-swappiness.conf
## install/start docker and services
yum update -y
yum install -y docker htop
systemctl enable docker.service
systemctl start docker.service
docker pull ${var.minecraft_docker_image}
docker run -d --name=minecraft-server --restart=unless-stopped -p 25565:25565 -v /data/mc:/data -e "EULA=true" -e "INIT_MEMORY=${var.minecraft_java_xms}" -e "MAX_MEMORY=${var.minecraft_java_xmx}" ${var.minecraft_docker_image}
docker pull ${var.mumble_docker_image}
docker run -d --name=mumble-server --restart=unless-stopped -p 64738:64738 -v /data/mumble:/data -v /data/mumble/murmur.ini:/etc/murmur/murmur.ini:ro ${var.mumble_docker_image}
EOF
}

data "aws_ami" "amazonlinux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.*-hvm-2.*${var.aws_instance_arch}*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "ena-support"
    values = [true]
  }

  owners = ["137112412989"] #Amazon Linux
}

resource "aws_instance" "minecraft_server" {
  ami                    = data.aws_ami.amazonlinux.id
  instance_type          = var.aws_instance_type
  private_ip             = var.aws_private_ip
  subnet_id              = var.aws_subnet_id
  iam_instance_profile   = aws_iam_instance_profile.systems_manager.name
  vpc_security_group_ids = [aws_security_group.minecraft_server.id, aws_security_group.minecraft_nfs.id]
  ebs_optimized          = true
  user_data_base64       = base64encode(local.user_data)

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/xvds"
    volume_type           = "gp3"
    volume_size           = 4
    delete_on_termination = true
  }

  tags = {
    Name = "minecraft-server"
  }

  depends_on = [
    aws_efs_file_system.minecraft_server,
  ]
}

resource "aws_eip" "minecraft_server" {
  vpc                       = true
  instance                  = aws_instance.minecraft_server.id
  associate_with_private_ip = var.aws_private_ip
}

resource "aws_security_group" "minecraft_server" {
  name_prefix = "minecraft_server_"
  vpc_id      = var.aws_vpc_id

  ingress {
    from_port        = 25565
    to_port          = 25565
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 8
    to_port          = 0
    protocol         = "icmp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 64738
    to_port          = 64738
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 64738
    to_port          = 64738
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "minecraft_nfs" {
  name_prefix = "minecraft_server_"
  vpc_id      = var.aws_vpc_id

  ingress {
    from_port = 2049
    to_port   = 2049
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port = 2049
    to_port   = 2049
    protocol  = "udp"
    self      = true
  }

  egress {
    from_port = 2049
    to_port   = 2049
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port = 2049
    to_port   = 2049
    protocol  = "udp"
    self      = true
  }
}

## EFS
resource "aws_efs_file_system" "minecraft_server" {
  creation_token         = "minecraft_server"
  availability_zone_name = var.aws_availability_zone

  lifecycle_policy {
    transition_to_ia = "AFTER_14_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }
}

resource "aws_efs_mount_target" "minecraft_server" {
  file_system_id  = aws_efs_file_system.minecraft_server.id
  subnet_id       = var.aws_subnet_id
  security_groups = [aws_security_group.minecraft_nfs.id]
}

## IAM
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "role" {
  name               = "ec2_assumerole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy" "systems_manager" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "role-policy-attachment" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.role.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "systems_manager" {
  name = "ssm-profile"
  role = aws_iam_role.role.name
}

## NAMECHEAP DNS
resource "namecheap_domain_records" "minecraft_dns" {
  domain = var.namecheap_domain
  mode   = "OVERWRITE"

  record {
    hostname = var.namecheap_hostname
    type     = "A"
    address  = aws_eip.minecraft_server.public_ip
  }
}
