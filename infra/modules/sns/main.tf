resource "aws_sns_topic" "this" {

    name = var.sns_topic_name

    display_name = var.sns_topic_display_name

    delivery_policy = var.sns_delivery_policy

    policy = var.sns_topic_policy

    tags = var.sns_tags

}

