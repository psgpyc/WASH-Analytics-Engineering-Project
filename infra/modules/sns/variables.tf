variable "sns_topic_name" {
  type        = string
  nullable    = false
  description = "SNS topic name. Must be 1–256 chars, and contain only letters, numbers, hyphens (-), and underscores (_)."

  validation {
    condition = (
      length(trimspace(var.sns_topic_name)) >= 1 &&
      length(trimspace(var.sns_topic_name)) <= 256 &&
      can(regex("^[A-Za-z0-9_-]+$", trimspace(var.sns_topic_name)))
    )
    error_message = "sns_topic_name must be 1–256 characters and contain only letters, numbers, hyphens (-), and underscores (_)."
  }
}

variable "sns_topic_display_name" {
  type        = string
  nullable    = false
  description = "SNS topic DisplayName (used for SMS subscriptions). Max 100 characters."

  validation {
    condition = (
      length(var.sns_topic_display_name) <= 100
    )
    error_message = "sns_topic_display_name must be <= 100 characters."
  }
}

variable "sns_delivery_policy" {

    type = string

    description = "value"

    nullable = true

    validation {
      condition = (
        var.sns_delivery_policy == null
        ? true
        : can(jsondecode(var.sns_delivery_policy))
      )

      error_message = "sns_delivery_policy must be a valid JSON object when provided."
    }
  
}

variable "sns_topic_policy" {

  type        = string
  nullable    = false
  description = "SNS topic access policy (JSON). Must be valid JSON with a policy-like structure (Version + Statement)."

  validation {
    condition = (
      can(jsondecode(var.sns_topic_policy))
    )
    error_message = "sns_topic_policy must be valid JSON"
  }
}


variable "sns_tags" {

  type        = map(string)
  nullable    = true
  description = "Optional tags for the SNS topic. Tag key max 128 chars, value max 256 chars. Keys must not start with reserved prefix 'aws:'."

}