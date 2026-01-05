# ---------------------------------------------------------------------------
# VPC (base network boundary)
# - Provides isolated networking environment for all app components
# - DNS support/hostnames enabled to allow internal name resolution (ECS, RDS, etc.)
# - CIDR defined via var.vpc_cidr to keep network layout configurable
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true                    # Required for public/private DNS hostnames (e.g. when using load balancers, ECS, RDS)
  enable_dns_support   = true                    # Enables AmazonProvidedDNS in the VPC
  tags = {
    Name = "base-vpc"                            # Naming tag for identification
  }
}

# ---------------------------------------------------------------------------
# Internet Gateway
# - Attaches the VPC to the public Internet
# - Required for:
#   * Outbound traffic from public subnets (e.g. NAT Gateway EIP allocation, package repos)
#   * Inbound traffic to public-facing resources (ALB, bastion, etc.)
# - Referenced in the public route table (0.0.0.0/0 -> igw)
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "base-igw"          # Naming tag for clarity in console
  }
}

# ---------------------------------------------------------------------------
# Public Subnet (AZ "a")
# Purpose:
#   - Entry point for internet-facing components (ALB, bastion, etc.)
#   - Placement for NAT Gateway so private subnets get outbound Internet
# Key settings:
#   - cidr_block: from var.public_subnet_cidr to keep network design flexible
#   - availability_zone: fixed to first AZ ("a"); replicate for multi-AZ
#   - map_public_ip_on_launch = true so launched instances auto receive public IPv4
# Notes:
#   - Keep this subnet small if it only hosts load balancers / NAT
#   - Tag aids console identification and cost allocation
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-a"
  }
}

# ---------------------------------------------------------------------------
# Private Subnet (AZ "a")
# Purpose:
#   - Hosts internal (non-Internet-facing) application components (ECS tasks, RDS, caches)
#   - No public IP assignment; outbound Internet via NAT Gateway in public subnet
# Key settings:
#   - cidr_block: from var.private_subnet_a_cidr to keep layout configurable
#   - availability_zone: first AZ ("a") for redundancy when paired with subnet_b
#   - map_public_ip_on_launch = false ensures strict private networking
# Notes:
#   - Used in RDS subnet group and private route table association
#   - Add additional tags (env, cost center) if required
# ---------------------------------------------------------------------------
resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_a_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-a"
  }
}

# Private subnet B
# ---------------------------------------------------------------------------
# Private Subnet (AZ "b")
# Purpose:
#   - Provides second Availability Zone for high availability (ECS tasks, RDS multi-AZ, etc.)
#   - Keeps workloads non-Internet-facing; egress only via NAT in public subnet
# Key settings:
#   - cidr_block: driven by var.private_subnet_b_cidr for flexible addressing
#   - availability_zone: "${var.aws_region}b" complements AZ "a" for redundancy
#   - map_public_ip_on_launch = false enforces private-only addressing (no public IPv4)
# Notes:
#   - Associated to the shared private route table (adds 0.0.0.0/0 -> NAT)
#   - Paired with private_a in the RDS subnet group for multi-AZ deployments
#   - Add environment / cost center tags as needed
# ---------------------------------------------------------------------------
resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_b_cidr
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-b"
  }
}

# Elastic IP for NAT
# ---------------------------------------------------------------------------
# Elastic IP for NAT Gateway
# Purpose:
#   - Supplies a stable public IPv4 for the NAT Gateway so private subnets
#     can reach the Internet (package repos, external APIs) without exposing
#     their own instances directly.
#   - Enables external systems (firewalls, partner APIs) to whitelist a single
#     predictable egress IP.
# Key settings:
#   - domain = "vpc": Required for EIPs attached to VPC-scoped resources
#     (NAT Gateway, Network Interface). Classic domain is deprecated.
# Cost / operational notes:
#   - EIP incurs cost while allocated if not attached; release it if NAT is removed.
#   - For high availability (multi-AZ), create an additional NAT + EIP in the
#     second public subnet and adjust route tables accordingly.
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = { 
    Name = "eip-nat-1"         # Identifies the EIP as used by primary NAT
  }
}

# ---------------------------------------------------------------------------
# NAT Gateway (placed in the public subnet)
# Purpose:
#   - Provides outbound Internet access for resources in private subnets
#     (e.g. ECS tasks, RDS init, package downloads) without exposing them publicly.
# How it works:
#   - Private subnets route 0.0.0.0/0 to this NAT (see aws_route.private_nat).
#   - Outbound connections egress using the Elastic IP (aws_eip.nat) for a stable,
#     whitelisted source address.
# Key settings:
#   - allocation_id: Associates the pre-created Elastic IP so the egress IP is predictable.
#   - subnet_id: Must reside in a public subnet with a route to the Internet Gateway.
#   - depends_on: Ensures IGW is attached before NAT creation to avoid transient failures.
# Cost / scaling notes:
#   - NAT Gateway is billed hourly + data processed. Shut down if not needed.
#   - For high availability, deploy an additional NAT in another AZ and create
#     per-AZ private route tables pointing to the local NAT.
# ---------------------------------------------------------------------------
resource "aws_nat_gateway" "gw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.igw]
  tags = { 
    Name = "nat-1"          # Identifier for primary (single-AZ) NAT
  }
}

# Public route table
# ---------------------------------------------------------------------------
# Public Route Table
# Purpose:
#   - Provides routing for public subnet(s) that need direct Internet access.
#   - Used by resources requiring public ingress/egress (ALB, bastion host, NAT Gateway).
# How it works:
#   - Associated to aws_subnet.public (see aws_route_table_association.public_assoc).
#   - Default route (0.0.0.0/0) to Internet Gateway defined separately in aws_route.public_internet.
# Design notes:
#   - Do not associate private subnets here (they should use NAT-based route table).
#   - Add additional routes (VPC peering, TGW, on-prem) as architecture evolves.
#   - Can be shared across multiple public subnets; create per-AZ tables only if divergent routing is required.
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "rtb-public" # Identifies this as the public route table
  }
}

# ---------------------------------------------------------------------------
# Public Internet Route
# Purpose:
#   - Adds the default (catch‑all) IPv4 route to the public route table.
#   - Allows resources in subnets associated with aws_route_table.public
#     (ALBs, bastion hosts, NAT Gateway) to reach / be reached from the Internet.
# Mechanics:
#   - destination_cidr_block "0.0.0.0/0" matches all IPv4 addresses not
#     covered by more specific routes.
#   - gateway_id targets the Internet Gateway, enabling bi‑directional traffic
#     for resources with public IPs or Elastic IP associations.
# Guidance:
#   - Keep this ONLY on public route tables; private subnets should route
#     0.0.0.0/0 to a NAT Gateway instead.
#   - Layer in additional routes (peering, TGW, VPN) as architecture expands.
# ---------------------------------------------------------------------------
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# ---------------------------------------------------------------------------
# Public Subnet ⇄ Public Route Table Association
# Purpose:
#   - Binds the public subnet (aws_subnet.public) to the public route table
#     (aws_route_table.public) so its instances inherit routes (e.g. 0.0.0.0/0 -> IGW).
# Effects:
#   - Enables inbound/outbound Internet connectivity for resources with public IPs.
#   - Required for ALBs, bastion hosts, and the NAT Gateway residing in this subnet.
# Notes:
#   - Only associate truly public subnets here. Private subnets must instead use
#     a route table whose default route points to a NAT Gateway (not the IGW).
#   - Add additional associations if you later create more public subnets (multi‑AZ).
# ---------------------------------------------------------------------------
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id      # Target public subnet
  route_table_id = aws_route_table.public.id # Grants it Internet route via IGW
}

# Private route table (compartilhada para ambas privadas)
# ---------------------------------------------------------------------------
# Private Route Table
# Purpose:
#   - Supplies routing for internal (non‑public) subnets (private_a + private_b).
#   - Ensures instances/tasks in private subnets have controlled egress only
#     (default 0.0.0.0/0 route added below via NAT Gateway; no direct IGW path).
# How it fits:
#   - Shared by both private subnets to reduce duplication while using a
#     single NAT Gateway (cost‑optimized, single‑AZ design).
#   - aws_route.private_nat (below) injects the default route -> NAT.
# Security / design notes:
#   - No direct Internet Gateway route must be added here (would expose workloads).
#   - Add additional specific routes (VPC peering, TGW, VPN, on‑prem) as architecture evolves.
# High availability considerations:
#   - For true multi‑AZ resilience, create one NAT Gateway per AZ and
#     separate per‑AZ private route tables so each subnet points to its local NAT.
# IPv6 (future):
#   - If enabling IPv6, add ::/0 -> egress-only internet gateway instead of NAT.
# Maintenance:
#   - Changing to per‑AZ route tables later is non‑destructive; just create new
#     tables and re-associate subnets.
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "rtb-private" # Shared private route table (single NAT design)
  }
}

# ---------------------------------------------------------------------------
# Private Default Route (IPv4 Egress)
# Purpose:
#   - Provides Internet egress for workloads in private subnets (private_a & private_b)
#     by sending all non-local traffic through the NAT Gateway.
# Behavior:
#   - destination_cidr_block "0.0.0.0/0" = catch‑all for any IPv4 not matched by a
#     more specific route (VPC CIDR, peering, VPN, TGW, etc.).
#   - nat_gateway_id ensures source addresses are translated to the NAT's Elastic IP,
#     keeping instances unexposed while offering a stable outbound IP for allow‑listing.
# Guidance:
#   - Never add an Internet Gateway route (0.0.0.0/0 -> igw) to a private route table.
#   - Add additional specific routes (on‑prem, peered VPCs) alongside this when needed;
#     longest-prefix match still applies.
# High availability:
#   - For multi‑AZ resilience create a NAT per AZ and separate route tables so each
#     private subnet points to its local NAT (avoids cross‑AZ data charges / single SPOF).
# ---------------------------------------------------------------------------
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.gw.id
}

# ---------------------------------------------------------------------------
# Private Subnet A ⇄ Private Route Table Association
# Purpose:
#   - Attaches private subnet in AZ "a" (aws_subnet.private_a) to the shared
#     private route table (aws_route_table.private).
# Effect:
#   - Subnet inherits default route 0.0.0.0/0 -> NAT (aws_route.private_nat),
#     enabling controlled outbound Internet via the NAT Gateway while
#     remaining unreachable from the public Internet.
# Notes:
#   - Keep this association ONLY with private route tables (never to a table
#     that has 0.0.0.0/0 -> igw).
#   - If migrating to per‑AZ NATs later, replace this with an AZ‑specific
#     route table association.
# ---------------------------------------------------------------------------
resource "aws_route_table_association" "private_assoc_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# Private Subnet B ⇄ Private Route Table Association
# Purpose:
#   - Binds the second private subnet (AZ "b") to the same shared private
#     route table for consistent routing behavior.
# High availability considerations:
#   - Current design uses a single NAT in AZ "a". Traffic from this subnet
#     will hairpin cross‑AZ to that NAT. For production HA and to avoid
#     cross‑AZ data charges, deploy a second NAT + per‑AZ route tables.
# Extension:
#   - Add more associations here if you introduce additional private subnets.
# ---------------------------------------------------------------------------
resource "aws_route_table_association" "private_assoc_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# DB Subnet Group (para RDS)
# ---------------------------------------------------------------------------
# RDS DB Subnet Group
# Purpose:
#   - Defines the isolated network locations (subnets) where RDS instances can reside.
#   - Uses two private subnets in different AZs to enable Multi-AZ deployments / failover.
# Network / security:
#   - Subnets are private (no public IPs) so the database is not Internet-accessible.
# Operational notes:
#   - Add more private subnets (extra AZs) here to expand fault tolerance.
#   - Changing the subnet list may force recreation of the subnet group (and possibly DB).
# Naming:
#   - name kept explicit for clarity and stable cross-module references.
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-sqlserver-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "rds-subnet-group"
  }
}

resource "aws_db_subnet_group" "mongodbatlas_subnet_group" {
  name = "mongodbatlas-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "mongodbatlas-subnet-group"
  }
}