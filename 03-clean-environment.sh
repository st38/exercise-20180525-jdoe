#!/bin/bash

# Read variables
step_id="01"
step_name="Read variables"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
source variables.txt

# Define task name
task_name="${task03_name}"

# Get list of instances to terminate
step_id="02"
step_name="Get list of instances to terminate"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
instances_to_terminate="$(aws ec2 describe-instances --region "${region}" --filter "Name=instance-state-name,Values=running,stopped" "Name=tag:Project,Values=${project_name}" "Name=tag:Environment,Values=${environment}" "Name=tag:Creator,Values=${creator}" --query "Reservations[].Instances[].[InstanceId]" --output text)"

# Show list of instances to terminate
step_id="03"
step_name="Show list of instances to terminate"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 describe-instances --region "${region}" --filter "Name=instance-state-name,Values=running,stopped" "Name=tag:Project,Values=${project_name}" "Name=tag:Environment,Values=${environment}" "Name=tag:Creator,Values=${creator}" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],InstanceId,Placement.AvailabilityZone,InstanceType,State.Name,LaunchTime]" --output table

# Terminate instances
step_id="04"
step_name="Terminate instances"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
for instance in ${instances_to_terminate}; do
  aws ec2 terminate-instances --region "${region}" --instance-ids "${instance}"
  instance_name="$(aws ec2 describe-instances --region ${region} --filter "Name=instance-id,Values=${instance}" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value]" --output text)"
  echo -e "\e[33m${instance_name} - ${instance} - Terminating\e[0m"
  aws ec2 wait instance-terminated --region "${region}" --instance-ids "${instance}"
  echo -e "\e[93m${instance_name} - ${instance} - Terminated\e[0m"
done

# Get list of ami images to deregister
step_id="05"
step_name="Get list of ami images to deregister"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
images_to_deregister="$(aws ec2 describe-images --region "${region}" --owner self --filters "Name=tag:Project,Values=${project_name}" "Name=tag:Environment,Values=${environment}" "Name=tag:Creator,Values=${creator}" --query "Images[].ImageId" --output text)"

# Show list of ami images to deregister
step_id="06"
step_name="Show list of ami images to deregister"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 describe-images --region "${region}" --owner self --filters "Name=tag:Project,Values=${project_name}" "Name=tag:Environment,Values=${environment}" "Name=tag:Creator,Values=${creator}" --query "Images[].[Name,ImageId,CreationDate,Description]" --output table

# Deregister ami images and delete associated snapshots
step_id="07"
step_name="Deregister ami images and delete associated snapshots"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
for image in ${images_to_deregister}; do
  snapshots_to_delete="$(aws ec2 describe-images --image-ids ${image} --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' --output text)"
  aws ec2 deregister-image --region "${region}" --image-id "${image}"
  for snapshot in ${snapshots_to_delete}; do
    aws ec2 delete-snapshot --region "${region}" --snapshot-id "${snapshot}"
  done
done

# Get security group to delete
step_id="08"
step_name="Get security group to delete"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
security_group_to_delete="$(aws ec2 describe-security-groups --region "${region}" --filters "Name=group-name,Values=${security_group_name}" --query 'SecurityGroups[].{GroupId:GroupId}' --output text)"

# Show security group to delete
step_id="09"
step_name="Show security group to delete"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 describe-security-groups --region "${region}" --filters "Name=group-name,Values=${security_group_name}" --query 'SecurityGroups[].[GroupName,Description,GroupId]' --output table

# Delete security group
step_id="10"
step_name="Delete security group"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 delete-security-group --group-id "${security_group_to_delete}"

# Show list of instances after termination
step_id="11"
step_name="Show list of instances after termination"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 describe-instances --region "${region}" --filter "Name=tag:Project,Values=${project_name}" "Name=tag:Environment,Values=${environment}" "Name=tag:Creator,Values=${creator}" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],InstanceId,Placement.AvailabilityZone,InstanceType,State.Name,LaunchTime]" --output text

# Show list of ami images after deregistering ami images and deletions associated snapshots
step_id="12"
step_name="Show list of ami images after deregistering ami images and deletions associated snapshots"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 describe-images --region "${region}" --owner self --filters "Name=tag:Project,Values=${project_name}" "Name=tag:Environment,Values=${environment}" "Name=tag:Creator,Values=${creator}" --query "Images[].[Name,ImageId,CreationDate,Description]" --output table

# Show security group after deletions
step_id="13"
step_name="Show security group after deletions"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 describe-security-groups --region "${region}" --filters "Name=group-name,Values=${security_group_name}" --query 'SecurityGroups[].[GroupName,Description,GroupId]' --output table

# Show task finish message
echo
echo -e "\e[96mTask '${task_name}' was finished\e[0m"
echo