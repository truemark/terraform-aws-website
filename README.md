# AWS Website

This terraform stands up infrastructure to host an SPA. This module is intended
to be used with the truemark/s3-iam/aws module.

Example Usage:
```hcl
module "s3" {
  source = "truemark/s3-iam/aws"
  version = "1.0.0"
  name = local.s3_bucket
}

module "website" {
  source = "truemark/website/aws"
  version = "1.0.0"
  s3_bucket = module.s3.s3_bucket_name
  name = local.name
  domain_names = [
    {
      record_name = "www"
      zone_name = "truemark.io"
    },
    {
      record_name = ""
      zone_name = "truemark.io"
    }
  ]
  certificate_domain = "www.truemark.io"
  depends_on = [module.s3]
}

# Allow the rw user to perform invalidations
resource "aws_iam_user_policy_attachment" "spa" {
  user = module.s3.iam_user_rw_name
  policy_arn = module.website.iam_policy_arn
}
```  
