variable "name" {
  description = "The application name being deployed. ex. website"
}

variable "path" {
  default = "/terraform/"
}

variable "s3_bucket" {}

variable "domain_names" {
  description = "List of domain names serviced by the SPA"
  type = list(object({
    record_name = string
    zone_name = string
    create_record = bool
  }))
}

variable "certificate_domain" {}

# See https://aws.amazon.com/cloudfront/pricing/
variable "price_class" {
  description = "Price class for the CloudFront Distribution"
  default = "PriceClass_100"
}

# See https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-web-values-specify.html#DownloadDistValues-security-policy
variable "minimum_protocol_version" {
  description = "Security policy to apply to the CloudFront distribution"
  default = "TLSv1.2_2019"
}

variable "error_404_response_page_path" {
  default = "/index.html"
}

variable "error_404_response_code" {
  default = "200"
}

variable "error_404_caching_min_ttl" {
  default = "600"
}

variable "error_403_response_page_path" {
  default = "/index.html"
}

variable "error_403_response_code" {
  default = "200"
}

variable "error_403_caching_min_ttl" {
  default = "600"
}
