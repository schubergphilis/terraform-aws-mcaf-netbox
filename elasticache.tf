resource "aws_elasticache_subnet_group" "default" {
  name       = "${var.name}-netbox"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_cluster" "default" {
  cluster_id           = "${var.name}-netbox"
  engine               = "redis"
  node_type            = "cache.t2.small"
  num_cache_nodes      = 1
  subnet_group_name    = aws_elasticache_subnet_group.default.name
  security_group_ids   = [aws_security_group.elasticache.id]
  parameter_group_name = "default.redis3.2"
  engine_version       = "3.2.10"
  port                 = 6379
  tags                 = var.tags
}

resource "aws_security_group" "elasticache" {
  name        = "${var.name}-netbox-cache"
  description = "Allow inbound traffic from the Fargate containers"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress {
    from_port       = 6379
    to_port         = 6379
    security_groups = concat([aws_security_group.ecs.id], var.allowed_security_group_ids)
    protocol        = "tcp"
  }
}
