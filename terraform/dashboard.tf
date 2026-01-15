# CloudWatch Dashboard - Production Monitoring
resource "aws_cloudwatch_dashboard" "msk" {
  dashboard_name = "${var.cluster_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Overview
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "## 📊 MSK Cluster Overview"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "MessagesInPerSec", "Cluster Name", var.cluster_name, { stat = "Sum" }]
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "Messages In/sec (Cluster Total)"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "BytesInPerSec", "Cluster Name", var.cluster_name, { stat = "Sum" }]
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "Bytes In/sec (Cluster Total)"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "BytesOutPerSec", "Cluster Name", var.cluster_name, { stat = "Sum" }]
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "Bytes Out/sec (Consumer Read)"
          yAxis  = { left = { min = 0 } }
        }
      },

      # Row 2: Consumer Lag (Critical for Operations)
      {
        type   = "text"
        x      = 0
        y      = 7
        width  = 24
        height = 1
        properties = {
          markdown = "## ⏳ Consumer Lag (Critical)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "SumOffsetLag", "Cluster Name", var.cluster_name]
          ]
          period = 60
          stat   = "Maximum"
          region = var.region
          title  = "Total Consumer Lag (messages)"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "EstimatedMaxTimeLag", "Cluster Name", var.cluster_name]
          ]
          period = 60
          stat   = "Maximum"
          region = var.region
          title  = "Estimated Max Time Lag (seconds)"
          yAxis  = { left = { min = 0 } }
        }
      },

      # Row 3: Broker Health
      {
        type   = "text"
        x      = 0
        y      = 14
        width  = 24
        height = 1
        properties = {
          markdown = "## 💻 Broker Health"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 15
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "CpuUser", "Cluster Name", var.cluster_name, { stat = "Average" }],
            [".", "CpuSystem", ".", ".", { stat = "Average" }]
          ]
          period = 60
          stat   = "Average"
          region = var.region
          title  = "CPU Usage (%) - Target < 60%"
          yAxis  = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ value = 60, label = "Warning", color = "#ff7f0e" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 15
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "KafkaDataLogsDiskUsed", "Cluster Name", var.cluster_name, { stat = "Average" }]
          ]
          period = 60
          stat   = "Average"
          region = var.region
          title  = "Disk Usage (%) - Target < 85%"
          yAxis  = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ value = 85, label = "Critical", color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 15
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "MemoryUsed", "Cluster Name", var.cluster_name, { stat = "Average" }]
          ]
          period = 60
          stat   = "Average"
          region = var.region
          title  = "Memory Used (%)"
          yAxis  = { left = { min = 0, max = 100 } }
        }
      },

      # Row 4: Partition & Replication Health
      {
        type   = "text"
        x      = 0
        y      = 21
        width  = 24
        height = 1
        properties = {
          markdown = "## ⚠️ Partition & Replication (Alerts)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 22
        width  = 6
        height = 5
        properties = {
          metrics = [
            ["AWS/Kafka", "UnderReplicatedPartitions", "Cluster Name", var.cluster_name]
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "Under Replicated Partitions"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 22
        width  = 6
        height = 5
        properties = {
          metrics = [
            ["AWS/Kafka", "UnderMinIsrPartitionCount", "Cluster Name", var.cluster_name]
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "Under Min ISR Partitions"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 22
        width  = 6
        height = 5
        properties = {
          metrics = [
            ["AWS/Kafka", "OfflinePartitionsCount", "Cluster Name", var.cluster_name]
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "Offline Partitions (Critical!)"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 18
        y      = 22
        width  = 6
        height = 5
        properties = {
          metrics = [
            ["AWS/Kafka", "ActiveControllerCount", "Cluster Name", var.cluster_name]
          ]
          period = 60
          stat   = "Average"
          region = var.region
          title  = "Active Controller (should be 1)"
          yAxis  = { left = { min = 0, max = 2 } }
        }
      },

      # Row 5: Connection & Network
      {
        type   = "text"
        x      = 0
        y      = 27
        width  = 24
        height = 1
        properties = {
          markdown = "## 🔌 Connections & Network"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 28
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "ClientConnectionCount", "Cluster Name", var.cluster_name, { stat = "Sum" }]
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "Client Connections (Total)"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 28
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "ConnectionCreationRate", "Cluster Name", var.cluster_name, { stat = "Average" }]
          ]
          period = 60
          stat   = "Average"
          region = var.region
          title  = "Connection Creation Rate"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 28
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Kafka", "ProduceTotalTimeMsMean", "Cluster Name", var.cluster_name, { stat = "Average" }]
          ]
          period = 60
          stat   = "Average"
          region = var.region
          title  = "Produce Latency (ms)"
          yAxis  = { left = { min = 0 } }
        }
      },

      # Row 6: Lambda Functions
      {
        type   = "text"
        x      = 0
        y      = 34
        width  = 24
        height = 1
        properties = {
          markdown = "## 🔄 Lambda Functions"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 35
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.cluster_name}-producer", { label = "Producer" }],
            ["...", "${var.cluster_name}-consumer", { label = "Consumer" }]
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "Lambda Invocations"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 35
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", "${var.cluster_name}-producer", { label = "Producer Errors", color = "#d62728" }],
            ["...", "${var.cluster_name}-consumer", { label = "Consumer Errors", color = "#ff7f0e" }]
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "Lambda Errors (Producer/Consumer)"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 35
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "IteratorAge", "FunctionName", "${var.cluster_name}-consumer"]
          ]
          period = 60
          stat   = "Maximum"
          region = var.region
          title  = "Consumer Iterator Age (ms)"
          yAxis  = { left = { min = 0 } }
          annotations = {
            horizontal = [{ value = 60000, label = "1 min lag", color = "#ff7f0e" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 41
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.cluster_name}-producer", { label = "Producer" }],
            ["...", "${var.cluster_name}-consumer", { label = "Consumer" }]
          ]
          period = 60
          stat   = "Average"
          region = var.region
          title  = "Lambda Duration (ms)"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 41
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Throttles", "FunctionName", "${var.cluster_name}-producer", { label = "Producer Throttles" }],
            ["...", "${var.cluster_name}-consumer", { label = "Consumer Throttles" }]
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "Lambda Throttles"
          yAxis  = { left = { min = 0 } }
        }
      }
    ]
  })
}
