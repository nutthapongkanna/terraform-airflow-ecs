resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name}-redis-subnets"
  subnet_ids = [for s in aws_subnet.public : s.id]
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id         = local.redis_cluster_id
  engine             = "redis"
  engine_version     = "7.0"
  node_type          = var.redis_node_type
  num_cache_nodes    = 1
  port               = 6379
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]
}
