resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-rds"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name}-rds"
  })
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "PostgreSQL ingress only from the EKS cluster security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-rds"
  })
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_eks" {
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.eks_cluster_security_group_id
  description                  = "PostgreSQL from EKS workloads"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_instance" "this" {
  identifier             = "${var.name}-postgres"
  engine                 = "postgres"
  engine_version         = "16.14"
  instance_class         = var.instance_class
  allocated_storage      = var.allocated_storage_gib
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = var.database_name
  username               = var.master_username
  password               = var.master_password
  port                   = 5432
  availability_zone      = var.availability_zone
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]

  publicly_accessible        = false
  multi_az                   = false
  deletion_protection        = false
  skip_final_snapshot        = true
  delete_automated_backups   = true
  backup_retention_period    = 0
  auto_minor_version_upgrade = false
  apply_immediately          = true

  tags = merge(var.tags, {
    Name = "${var.name}-postgres"
  })
}
