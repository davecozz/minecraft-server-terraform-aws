# minecraft-server-terraform-aws

Create a Minecraft Server with a Mumble Chat Server running in AWS using Terraform. All of the server data and game state is saved to an EFS volume so the EC2 server and Docker containers are completely ephemeral, which makes it easy to do updates and config changes. 

Note: This example uses Namecheap for DNS but you could substitute others fairly easily.

### Prerequisites
- AWS account with [Terraform configured](https://registry.terraform.io/providers/hashicorp/aws/latest/docs).
- Namecheap account with [Terraform configured](https://registry.terraform.io/providers/namecheap/namecheap/latest/docs).
- Substitute your values for the [S3 backend](minecraft_server.tf#L15-L17) and in the [tfvars.json](tfvars.json) file. 

### Run Terraform
- `terraform init`
- `terraform plan -var-file=tfvars.json`
- `terraform apply -var-file=tfvars.json`
