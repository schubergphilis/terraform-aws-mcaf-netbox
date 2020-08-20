data "aws_route53_zone" "current" {
  zone_id = var.zone_id
}

resource "aws_route53_record" "default" {
  zone_id = var.zone_id
  name    = "netbox.${data.aws_route53_zone.current.name}"
  type    = "CNAME"
  ttl     = "5"
  records = [aws_alb.default.dns_name]
}

resource "aws_acm_certificate" "default" {
  domain_name       = aws_route53_record.default.fqdn
  validation_method = "DNS"
  tags              = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Pending https://github.com/terraform-providers/terraform-provider-aws/issues/14447
# workaround -> https://github.com/terraform-providers/terraform-provider-aws/issues/14447#issuecomment-668766123
resource "aws_route53_record" "certificate_validation" {
  name    = aws_acm_certificate.default.domain_validation_options.*.resource_record_name[0]
  records = [aws_acm_certificate.default.domain_validation_options.*.resource_record_value[0]]
  ttl     = 60
  type    = aws_acm_certificate.default.domain_validation_options.*.resource_record_type[0]
  zone_id = var.zone_id
}

resource "aws_acm_certificate_validation" "default" {
  certificate_arn         = aws_acm_certificate.default.arn
  validation_record_fqdns = [aws_route53_record.certificate_validation.fqdn]
}

resource "aws_alb" "default" {
  name            = "${var.name}-netbox"
  subnets         = var.public_subnet_ids
  security_groups = [aws_security_group.alb.id]
  tags            = var.tags

  timeouts {
    create = "20m"
  }
}

resource "aws_alb_target_group" "app" {
  name        = "${var.name}-netbox-app"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  tags        = var.tags
  vpc_id      = var.vpc_id

  health_check {
    interval            = 60
    timeout             = 30
    path                = "/login/?next=/"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = 200
  }
}

resource "aws_alb_target_group" "nginx" {
  name        = "${var.name}-netbox-nginx"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    interval            = 30
    timeout             = 10
    path                = "/static/img/netbox_logo.png"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = 200
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.default.id
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = 443
      host        = aws_route53_record.default.fqdn
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_alb.default.id
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
  certificate_arn   = aws_acm_certificate_validation.default.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.app.id
  }
}

resource "aws_alb_listener_rule" "static" {
  listener_arn = aws_alb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.nginx.arn
  }

  condition {
    path_pattern {
      values = ["/static/*"]
    }
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-netbox-alb"
  description = "Controls access to the ALB"
  vpc_id      = var.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}
