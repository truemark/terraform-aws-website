output "redirect_lambda_arn" {
  value = aws_lambda_function.redirect.arn
}

output "cloudfront_distribution_arn" {
  value = aws_cloudfront_distribution.spa.arn
}

output "route53_record_ids" {
  value = aws_route53_record.spa.*.id
}

output "iam_policy_arn" {
  value = aws_iam_policy.spa.arn
}
