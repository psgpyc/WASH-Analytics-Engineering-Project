{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3PublishToSNS",
      "Effect": "Allow",
      "Principal": { "Service": "s3.amazonaws.com" },
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:${current_region}:${account_id}:${topic_name}",
      "Condition": {
        "StringEquals": { "AWS:SourceAccount": "${account_id}" },
        "ArnLike": { "AWS:SourceArn": "arn:aws:s3:::${bucket_name}" }
      }
    }
  ]
}