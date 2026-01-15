# Lambda IAM Role
resource "aws_iam_role" "lambda" {
  name = "${var.cluster_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_msk" {
  name = "${var.cluster_name}-lambda-msk"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kafka:*", "kafka-cluster:*"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Security Group
resource "aws_security_group" "lambda" {
  name   = "${var.cluster_name}-lambda-sg"
  vpc_id = aws_vpc.msk.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Producer Lambda
resource "aws_lambda_function" "producer" {
  filename         = "${path.module}/../app/producer.zip"
  function_name    = "${var.cluster_name}-producer"
  role             = aws_iam_role.lambda.arn
  handler          = "producer.handler"
  runtime          = "python3.12"
  timeout          = 30

  vpc_config {
    subnet_ids         = aws_subnet.msk[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      BOOTSTRAP_SERVERS = aws_msk_cluster.main.bootstrap_brokers_tls
      TOPIC             = var.kafka_topic
    }
  }
}

# Consumer Lambda
resource "aws_lambda_function" "consumer" {
  filename         = "${path.module}/../app/consumer.zip"
  function_name    = "${var.cluster_name}-consumer"
  role             = aws_iam_role.lambda.arn
  handler          = "consumer.handler"
  runtime          = "python3.12"
  timeout          = 30

  vpc_config {
    subnet_ids         = aws_subnet.msk[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }
}

# MSK Event Source Mapping (Consumer 트리거)
resource "aws_lambda_event_source_mapping" "msk" {
  event_source_arn  = aws_msk_cluster.main.arn
  function_name     = aws_lambda_function.consumer.arn
  topics            = [var.kafka_topic]
  starting_position = "LATEST"
  batch_size        = 100
}

# API Gateway
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.cluster_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "producer" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.producer.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "producer" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /publish"
  target             = "integrations/${aws_apigatewayv2_integration.producer.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
