locals {
  validation_options = var.certificate_enabled ? {
    for option in aws_acm_certificate.this[0].domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  } : {}

  website_alias_names = var.website_aliases_enabled ? toset(concat(
    [var.domain_name],
    var.subject_alternative_names,
  )) : toset([])
}

resource "aws_route53_zone" "this" {
  name = var.domain_name

  tags = merge(var.tags, {
    Name = var.domain_name
  })
}

resource "aws_acm_certificate" "this" {
  count = var.certificate_enabled ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = var.domain_name
  })
}

resource "aws_route53_record" "validation" {
  for_each = local.validation_options

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = var.validation_record_ttl
  type            = each.value.type
  zone_id         = aws_route53_zone.this.zone_id
}

resource "aws_acm_certificate_validation" "this" {
  count = var.certificate_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]

  timeouts {
    create = "45m"
  }
}

resource "aws_route53_record" "website_alias" {
  for_each = local.website_alias_names

  name    = each.value
  type    = "A"
  zone_id = aws_route53_zone.this.zone_id

  alias {
    evaluate_target_health = true
    name                   = var.website_alias_dns_name
    zone_id                = var.website_alias_zone_id
  }

  lifecycle {
    precondition {
      condition = (
        var.certificate_enabled &&
        var.website_alias_dns_name != "" &&
        var.website_alias_zone_id != ""
      )
      error_message = "Website aliases require the issued-certificate stage and a discovered ALB DNS name/zone ID."
    }
  }
}
