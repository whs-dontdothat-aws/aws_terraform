# outputs.tf
############################################
# 필요한 두 가지만 출력
############################################

output "alb_dns" {
  description = "Application Load Balancer DNS"
  value       = aws_lb.alb.dns_name
}

output "dvwa_public_ip" {
  description = "Public IP of the DVWA EC2 instance"
  value       = aws_instance.dvwa.public_ip
}
