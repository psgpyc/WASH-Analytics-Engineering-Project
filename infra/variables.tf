variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "aws_profile" {
  type    = string
  default = null
}

variable "bucket_name" {

    type = string
    description = "Globally-unique S3 bucket name."
    nullable = false
  
}

variable "bucket_tags" {

  type = object({
    domain = string
    environment = string 
  })

  default = {
    domain = "raw"
    environment = "dev"
  }
  nullable = false
  description = "Tags for s3 bucket."
  
}

variable "bucket_force_destroy" {

  type = bool
  description = "Boolean that indicates all objects (including any locked objects) should be deleted from the bucket when the bucket is destroyed so that the bucket can be destroyed without error"
  default = false
  
}

variable "bucket_versioning_status" {
  type = string
  description = "Versioning state of the bucket."
  validation {
    condition = contains(["Enabled", "Suspended"], var.bucket_versioning_status)
    error_message = "bucket versioning status must be one of: Enabled, Suspended."
  }
  
}


# lifecycle rules

variable "current_v_lifecycle_rules" {

  type = list(
      object({
        id = string
        status = string
        prefix = optional(string, null)
        tags = optional(map(string), null)
        transition = list(object({
          days = number
          storage_class = string 
        }))
        expiration = optional(object({
          days = number 
        }), null)
       })
  )
}


variable "noncurrent_v_lifecycle_rules" {

  type = list(
      object({
        id = string
        status= string
        prefix = optional(string, null)
        tags = optional(map(string), null)
        noncurrent_version_transition = list(object({
          noncurrent_days = number
          storage_class = string 
        }))
        noncurrent_version_expiration = optional(object({
          noncurrent_days = number 
        }), null)
       })
  )
  
}