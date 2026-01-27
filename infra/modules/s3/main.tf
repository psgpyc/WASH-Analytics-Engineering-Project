# This module enforces PRIVATE S3 buckets only.
# If a public bucket is needed, a separate dedicated module must be created.
resource "aws_s3_bucket" "this" {

    bucket = var.bucket_name

    tags = var.bucket_tags

    force_destroy = var.bucket_force_destroy

}

resource "aws_s3_bucket_versioning" "this" {

    bucket = aws_s3_bucket.this.id

    versioning_configuration {

      status = var.bucket_versioning_status

    }
}

resource "aws_s3_bucket_ownership_controls" "this" {

    bucket = aws_s3_bucket.this.id

    rule {
        object_ownership = "BucketOwnerEnforced"
     }
  
}

resource "aws_s3_bucket_public_access_block" "this" {

    bucket = aws_s3_bucket.this.id

    # Guardrail: block any public access via ACLs or bucket policy.
    block_public_acls = true

    # prevents creating or updating a bucket policy that would make the bucket public(principal: *).
    block_public_policy = true
    ignore_public_acls = true

    # if the bucket is already public, still block public/anon access.
    restrict_public_buckets = true

    depends_on = [ aws_s3_bucket_ownership_controls.this ]

}


resource "aws_s3_bucket_lifecycle_configuration" "this" {

    bucket = aws_s3_bucket.this.id

    dynamic "rule" {

        for_each = var.current_v_lifecycle_rules

        content {

            id = rule.value.id

            status = rule.value.status

            dynamic "filter" {

                for_each = rule.value.prefix == null && rule.value.tags == null ?  [1] : []

                content {
                  
                }
            }

            dynamic "filter" {
                for_each = rule.value.prefix != null && rule.value.tags == null ? [1] : []

                content {

                  prefix = rule.value.prefix

                }
              
            }

            dynamic "filter" {

                for_each = rule.value.tags != null && rule.value.prefix == null ? [1] : []

                content {
                  and {
                    tags = rule.value.tags
                  }
                }
              
            }

            dynamic "filter" {
                for_each = rule.value.tags != null && rule.value.prefix != null ? [1] : []

                content {
                  and {
                    prefix = rule.value.prefix
                    tags = rule.value.tags
                  }
                }
              
            }

            dynamic "transition" {

                for_each = rule.value.transition

                content {
                  days = transition.value.days
                  storage_class = transition.value.storage_class
                }
              
            }


            dynamic "expiration" {

                for_each = rule.value.expiration == null ? [] : [rule.value.expiration]

                content {
                    days = expiration.value.days
                  
                }
            }
          
        }
      
    }

    dynamic "rule" {
        for_each = var.noncurrent_v_lifecycle_rules

        content {

          id = rule.value.id

          status = rule.value.status

            dynamic "filter" {
                for_each = rule.value.prefix != null && rule.value.tags == null ? [1] : []

                content {
                  prefix = rule.value.prefix
                }
              
            }

            dynamic "filter" {
                for_each = rule.value.tags != null && rule.value.prefix == null ? [1] : []

                content {
                  and {
                    tags = rule.value.tags
                  }
                }
              
            }

            dynamic "filter" {
                for_each = rule.value.tags != null && rule.value.prefix != null ? [rule.value.tags] : []

                content {
                  and {
                    prefix = filter.value.prefix
                    tags = filter.value.tags
                  }
                }
              
            }

            dynamic "noncurrent_version_transition" {

                for_each = rule.value.noncurrent_version_transition

                content {
                  noncurrent_days = noncurrent_version_transition.value.noncurrent_days 
                  storage_class = noncurrent_version_transition.value.storage_class
                }
              
            }


            dynamic "noncurrent_version_expiration" {

                for_each = rule.value.noncurrent_version_expiration == null ? [] : [rule.value.noncurrent_version_expiration]

                content {
                
                    noncurrent_days = noncurrent_version_expiration.value.noncurrent_days
                  
                }
            }


        }
      
    }


}





