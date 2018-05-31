#!/bin/bash

# Read variables
step_id="01"
step_name="Read variables"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
source variables.txt

# Define task name
task_name="${task01_name}"

# Get default VPC id
step_id="02"
step_name="Get default VPC id"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
vpc_id="$(aws ec2 describe-vpcs --region "${region}" --filters "Name=is-default,Values=true" --query 'Vpcs[*].{VpcId:VpcId}' --output text)"

# Create security group
step_id="03"
step_name="Create security group"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
security_group_id="$(aws ec2 create-security-group --region "${region}" --group-name "${security_group_name}" --description "${security_group_description}" --vpc-id "${vpc_id}" --output text)"

# Add tags to the created security group
step_id="04"
step_name="Add tags to the created security group"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 create-tags --region "${region}" --resources "${security_group_id}" --tags Key=Project,Value="${project_name}" Key=Environment,Value="${environment}" Key=Creator,Value="${creator}"

# Add ingress rule to the security group - Allow ping to the server
step_id="05"
step_name="Add ingress rule to the security group - Allow ping to the server"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 authorize-security-group-ingress --region "${region}" --group-id "${security_group_id}" --ip-permissions '[{"IpProtocol": "icmp", "FromPort": -1, "ToPort": -1, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow ping from Any"}]}]'

# Add ingress rule to the security group - Allow incoming SSH connections to the server
step_id="06"
step_name="Add ingress rule to the security group - Allow incoming SSH connections to the server"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 authorize-security-group-ingress --region "${region}" --group-id "${security_group_id}" --ip-permissions '[{"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow SSH from Any"}]}]'

# Add ingress rule to the security group - Allow incoming TCP connections to the server
step_id="07"
step_name="Add ingress rule to the security group - Allow incoming TCP connections to the server"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 authorize-security-group-ingress --region "${region}" --group-id "${security_group_id}" --ip-permissions '[{"IpProtocol": "tcp", "FromPort": '${tcp_port}', "ToPort": '${tcp_port}', "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow TCP from Any"}]}]'

# Add ingress rule to the security group - Allow incoming HTTP connections to the server
step_id="08"
step_name="Add ingress rule to the security group - Allow incoming HTTP connections to the server"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
if [ "${tcp_port}" == "${http_port}" ]
then
  echo -e "\e[35mHTTP port is same as TCP port - No additional rule for HTTP is required\e[0m"
else
  aws ec2 authorize-security-group-ingress --region "${region}" --group-id "${security_group_id}" --ip-permissions '[{"IpProtocol": "tcp", "FromPort": '${http_port}', "ToPort": '${http_port}', "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow HTTP from Any"}]}]'
fi

# Get latest Ubuntu AMI id
step_id="09"
step_name="Get latest Ubuntu AMI id"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
image_id="$(aws ec2 describe-images --region "${region}" --owner 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*" "Name=virtualization-type,Values=hvm" --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)"

# Run a, b and c instances and wait until they will start
step_id="10"
step_name="Run ${prefixes} instances and wait until they will start"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
for prefix in ${prefixes}; do
  instance_id="$(aws ec2 run-instances --region "${region}" --image-id "${image_id}" --count 1 --instance-type "${instance_type}" --security-group-ids "${security_group_id}" --instance-initiated-shutdown-behavior stop --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='${prefix}.${domain_name}'},{Key=Project,Value='${project_name}'},{Key=Environment,Value='${environment}'},{Key=Role,Value='${role}'},{Key=Creator,Value='${creator}'}]' --user-data file://"${user_data_file}" --query 'Instances[].[InstanceId]' --output text)"
  echo -e "\e[33m${prefix}.${domain_name} - Starting\e[0m"
  aws ec2 wait instance-running --region "${region}" --instance-ids "${instance_id}"
  echo -e "\e[93m${prefix}.${domain_name} - Started\e[0m"
  public_dns_name="$(aws ec2 describe-instances --region "${region}" --instance-ids ${instance_id} --query "Reservations[].Instances[].[PublicDnsName]" --output text)"
  aws ec2 create-tags --region "${region}" --resources "${instance_id}" --tags Key=PublicDnsName,Value="${public_dns_name}"
  public_ip_address="$(aws ec2 describe-instances --region "${region}" --instance-ids ${instance_id} --query "Reservations[].Instances[].[PublicIpAddress]" --output text)"
  aws ec2 create-tags --region "${region}" --resources "${instance_id}" --tags Key=PublicIpAddress,Value="${public_ip_address}"
done

# Compute instance id which should be stopped
step_id="11"
step_name="Compute instance id which should be stopped"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
instance_id_to_stop="$(aws ec2 describe-instances --region "${region}" --filter "Name=tag:Project,Values=${project_name}" "Name=instance-state-name,Values=running" "Name=tag:Name,Values=${stop_instance_prefix}.${domain_name}" --query "Reservations[].Instances[].[InstanceId]" --output text)"

# Stop instance with computd id
step_id="12"
step_name="Stop instance with computd id"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 stop-instances --instance-ids "${instance_id_to_stop}"

# Show instances and their state
step_id="13"
step_name="Show instances and their state"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 describe-instances --region "${region}" --filter "Name=instance-state-name,Values=running,stopping,stopped" "Name=tag:Project,Values=${project_name}" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],InstanceId,Placement.AvailabilityZone,InstanceType,PublicIpAddress,State.Name,LaunchTime]" --output table


# Get instances public DNS names
step_id="14"
step_name="Get instances public DNS names"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
echo -e "\e[94mPlease add A or CNAME DNS records on DNS zone hoster side with the following data:\e[0m"
aws ec2 describe-instances --region "${region}" --filter "Name=instance-state-name,Values=running,stopping,stopped" "Name=tag:Project,Values=${project_name}" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],Tags[?Key=='PublicIpAddress'].Value|[0],Tags[?Key=='PublicDnsName'].Value|[0]]" --output text

# Show task finish message
echo
echo -e "\e[96mTask '${task_name}' was finished\e[0m"
echo
echo -e "\e[96mAfter adding DNS records you may proceed with next task '${task02_name}': ${task02_file}\e[0m"
echo