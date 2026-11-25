# Outputs: public IP and DNS, SSH user, key path and app URL

output "public_ip" {
  value = aws_instance.deploy.public_ip
}

output "public_dns" {
  value = aws_instance.deploy.public_dns
}

output "ssh_user" {
  description = "Default user on Amazon Linux 2"
  value       = "ec2-user"
}

output "private_key_path" {
  description = "Paste this file's contents into the Jenkins ec2_ssh credential"
  value       = local_sensitive_file.private_key.filename
}

output "ssh_command" {
  value = "ssh -i ${local_sensitive_file.private_key.filename} ec2-user@${aws_instance.deploy.public_ip}"
}

output "app_url" {
  value = "http://${aws_instance.deploy.public_dns}"
}
