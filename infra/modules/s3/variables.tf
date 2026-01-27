variable "bucket_name" {

    type = string
    description = "Globally-unique S3 bucket name."
    nullable = false

    validation {
      condition = (
        length(var.bucket_name) >= 3 
        && length(var.bucket_name) <=63
        && can(regex("^[a-z0-9]*[a-z0-9.-]*[a-z0-9]$", var.bucket_name))
        && !can(regex("([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.bucket_name))
        && !can(regex("\\.\\.", var.bucket_name))
        && !can(regex("( \\.- | -\\. )", var.bucket_name))
      )
      error_message = "bucket_name must be 3-63 chars, lowercase letters/numbers/dot/hyphen, no '..' or '.-' or '-.', and not look like an IP address."
    }
  
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
  

  validation {

    condition = alltrue([

      for r in var.current_v_lifecycle_rules: alltrue([
            contains(["Enabled", "Disabled"], r.status),

            length(trimspace(r.id)) > 0,

            r.prefix == null
              ? true
              : length(r.prefix) > 0,

            length(r.transition) >= 1,

            alltrue([
              for i in range(1, length(r.transition)): r.transition[i].days >  0
            ]),

            alltrue([
              for each in r.transition: contains([
                "STANDARD_IA",
                "ONEZONE_IA",
                "INTELLIGENT_TIERING",
                "GLACIER",
                "DEEP_ARCHIVE"
              ], each.storage_class)
            ]),

            r.expiration == null 
              ? true
              : r.expiration.days >=1  
        ]) 
    ])

    error_message = "Invalid current life cycle rules: check state, non-empty id, prefix (null or non-empty), >=1 transition, increasing transition days, allowed storage_class, and expiration.days >= 1 (or null)."

  }
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
  

  validation {

    condition = alltrue([
      for r in var.noncurrent_v_lifecycle_rules:

        alltrue([
            contains(["Enabled", "Disabled"], r.status),

            length(trimspace(r.id)) > 0,

            r.prefix == null
              ? true
              : length(r.prefix) > 0,

            length(r.noncurrent_version_transition) >= 1,

  
            alltrue([
              for each in r.noncurrent_version_transition: contains([
                "STANDARD_IA",
                "ONEZONE_IA",
                "INTELLIGENT_TIERING",
                "GLACIER",
                "DEEP_ARCHIVE"
              ], each.storage_class)
            ]),

            r.noncurrent_version_expiration == null 
              ? true
              : r.noncurrent_version_expiration.noncurrent_days >=1  
        ]) 
    ])

    error_message = "Invalid non current version life cycle rs: check state, non-empty id, prefix (null or non-empty), >=1 transition, increasing transition days, allowed storage_class, and expiration.days >= 1 (or null)."

  }
}