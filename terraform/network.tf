# 네트워크: VPC 1개 + 서브넷 4개(AZ 2개 × Public/Private) + 인터넷 게이트웨이 + 라우트 테이블
# NAT Gateway는 쓰지 않는다. Fargate task는 Public subnet에서 Public IP로 밖에 나간다.

locals {
  # 서브넷을 만들 가용 영역 2개. ALB와 RDS 서브넷 그룹이 AZ 2개 이상을 요구한다
  # 키(a, c)는 리소스 이름에 쓰고, 값은 실제 AZ 이름
  azs = {
    a = "${var.aws_region}a"
    c = "${var.aws_region}c"
  }

  vpc_cidr = "10.0.0.0/16"

  # Public: ALB, Fargate task / Private: RDS
  public_subnet_cidrs = {
    a = "10.0.1.0/24"
    c = "10.0.2.0/24"
  }
  private_subnet_cidrs = {
    a = "10.0.11.0/24"
    c = "10.0.12.0/24"
  }
}

# VPC: AWS 안에 만드는 우리 전용 네트워크
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true # VPC 안에서 DNS 사용 (RDS 주소, ECR 주소 해석)
  enable_dns_hostnames = true # 자원에 DNS 이름 부여 (RDS 접속 주소에 필요)

  tags = { Name = "${local.name_prefix}-vpc" }
}

# 인터넷 게이트웨이: VPC와 인터넷을 잇는 대문
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-igw" }
}

# Public subnet 2개 (2a, 2c): ALB와 Fargate task가 들어간다
resource "aws_subnet" "public" {
  for_each = local.public_subnet_cidrs

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = local.azs[each.key]

  # 서브넷 안 자원에 Public IP를 자동으로 주지 않는다
  # Fargate task는 ecs.tf의 assign_public_ip = true로 필요할 때만 받는다
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-public-${each.key}" }
}

# Private subnet 2개 (2a, 2c): RDS만 들어간다. 인터넷으로 나가는 길이 없다
resource "aws_subnet" "private" {
  for_each = local.private_subnet_cidrs

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = local.azs[each.key]

  tags = { Name = "${local.name_prefix}-private-${each.key}" }
}

# Public 라우트 테이블: "VPC 밖(0.0.0.0/0)으로 가는 요청은 인터넷 게이트웨이로"
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private 라우트 테이블: VPC 안(10.0.0.0/16)끼리만 통신. 인터넷 경로를 일부러 넣지 않는다
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
