output "viewer_request_lambda_arn" {
  value = aws_lambda_function.viewer_request.arn
}

output "origin_request_lambda_arn" {
  value = aws_lambda_function.origin_request.arn
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
