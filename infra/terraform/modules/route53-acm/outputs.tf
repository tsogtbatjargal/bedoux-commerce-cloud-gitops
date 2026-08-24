output "hosted_zone_id" {
  description = "Route 53 public hosted zone ID."
  value       = aws_route53_zone.this.zone_id
}

output "hosted_zone_name_servers" {
  description = "Authoritative Route 53 nameservers to configure at the domain registrar."
  value       = aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "DNS-validated regional ACM certificate ARN for the P12 ALB HTTPS listener; null during the hosted-zone-only stage."
  value       = try(aws_acm_certificate_validation.this[0].certificate_arn, null)
}

output "validation_record_fqdns" {
  description = "FQDNs of the Route 53 records used to validate the ACM certificate."
  value       = [for record in aws_route53_record.validation : record.fqdn]
}
