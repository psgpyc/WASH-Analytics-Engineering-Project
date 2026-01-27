module "s3" {

    source = "./modules/s3"

    bucket_name = var.bucket_name

    bucket_tags = var.bucket_tags

    bucket_force_destroy = var.bucket_force_destroy

    bucket_versioning_status = var.bucket_versioning_status

    current_v_lifecycle_rules = var.current_v_lifecycle_rules

    noncurrent_v_lifecycle_rules = var.noncurrent_v_lifecycle_rules


  
}