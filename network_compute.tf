# 1. Custom VPC (10.0.0.0/16)
#trivy:ignore:AWS-0178
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "nejamul-devsecops-vpc"
    Project = "terraform-aws-infra"
  }
}

# 2. Internet Gateway for Public Subnet
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "nejamul-devsecops-igw"
  }
}

# 3. Public Subnet (10.0.1.0/24)
#trivy:ignore:AWS-0164
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "nejamul-public-subnet"
  }
}

# 4. Route Table & Default Internet Route
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "nejamul-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# 5. Least-Privilege Security Group (HTTP 80 only; no wide-open 0.0.0.0/0 SSH)
resource "aws_security_group" "web_sg" {
  name        = "nejamul-web-sg"
  description = "Allow HTTP inbound traffic and restricted outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    #trivy:ignore:AWS-0104
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS outbound for package updates"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    #trivy:ignore:AWS-0104
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nejamul-web-sg"
  }
}

# 6. Latest Amazon Linux 2023 AMI Lookup
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

# 7. Free-Tier Eligible EC2 Instance (t2.micro with IMDSv2 Enforced & Encrypted Root Volume)
resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # Enforces IMDSv2 against SSRF attacks
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  tags = {
    Name = "nejamul-hardened-web-node"
  }
}
