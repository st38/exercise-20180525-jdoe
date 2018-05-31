#!/bin/bash

# Read variables
step_id="01"
step_name="Read variables"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
source variables.txt

# Define task name
task_name="${task02_name}"

# Verify hosts reachability
step_id="02"
step_name="Verify hosts reachability"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"

# Function to show probe status
function probe_status {
if [ "${status}" = "0" ]; then
  echo -e "\e[36m"${hostname}" - "${probe}" is UP\e[0m"
else
  echo -e "\e[35m"${hostname}" - "${probe}" is DOWN\e[0m"
fi
}

for prefix in ${prefixes}; do
  hostname="${prefix}"."${domain_name}"

  # Perform ICMP probe
  step_id="02-2-${prefix}"
  step_name="Perform ICMP probe"
  echo
  echo -e "\e[94m${step_id} - ${step_name}\e[0m"
  probe=ICMP
  ping -W 2 -c 4 "${hostname}" >/dev/null
  icmp_probe_status="$?"
  eval status="${icmp_probe_status}"
  probe_status

  # Perform TCP probe
  step_id="02-3-${prefix}"
  step_name="Perform TCP probe"
  echo -e "\e[94m${step_id} - ${step_name}\e[0m"
  probe=TCP
  nc -w 3 "${hostname}" "${tcp_port}"
  tcp_probe_status="$?"
  eval status="${tcp_probe_status}"
  probe_status

  # Perform HTTP probe
  step_id="02-4-${prefix}"
  step_name="Perform HTTP probe"
  echo -e "\e[94m${step_id} - ${step_name}\e[0m"
  probe=HTTP
  wget --tries=1 --timeout=3 --no-check-certificate --quiet --output-document=/dev/null "${http_protocol}"://"${hostname}":"${http_port}"/
  http_probe_status="$?"
  eval status="${http_probe_status}"
  probe_status
  overall_probes_status="$(($icmp_probe_status+$tcp_probe_status+$http_probe_status))"

  # Compute overall reachability and if backup should be performed
  step_id="02-5-${prefix}"
  step_name="Compute overall reachability and if backup should be performed"
  echo -e "\e[94m${step_id} - ${step_name}\e[0m"
  if [ "${overall_probes_status}" = "0" ]; then
    echo -e     "\e[36m"${hostname}" is UP - Backup should not be performed\e[0m"
  else
    echo -e     "\e[35m"${hostname}" is DOWN - Backup should be performed\e[0m"

    # Get unreachable instance public ip
    step_id="02-6-${prefix}"
    step_name="Get unreachable instance public ip"
    echo
    echo -e "\e[94m${step_id} - ${step_name}\e[0m"
    instance_public_ip="$(dig +short ${prefix}.${domain_name})"

    # Get unreachable and stopped instance id and name
    step_id="02-7-${prefix}"
    step_name="Get stopped instance id and name"
    echo
    echo -e "\e[94m${step_id} - ${step_name}\e[0m"
    backup_instance_id="$(aws ec2 describe-instances --region ${region} --filter "Name=instance-state-name,Values=stopped" "Name=tag:PublicIpAddress,Values=${instance_public_ip}" --query "Reservations[].Instances[].[InstanceId]" --output text)"
    backup_instance_name="$(aws ec2 describe-instances --region ${region} --filter "Name=instance-id,Values=${backup_instance_id}" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value]" --output text)"
    backup_instance_project="$(aws ec2 describe-instances --region ${region} --filter "Name=instance-id,Values=${backup_instance_id}" --query "Reservations[].Instances[].[Tags[?Key=='Project'].Value]" --output text)"
    backup_instance_environment="$(aws ec2 describe-instances --region ${region} --filter "Name=instance-id,Values=${backup_instance_id}" --query "Reservations[].Instances[].[Tags[?Key=='Environment'].Value]" --output text)"
    backup_instance_role="$(aws ec2 describe-instances --region ${region} --filter "Name=instance-id,Values=${backup_instance_id}" --query "Reservations[].Instances[].[Tags[?Key=='Role'].Value]" --output text)"

    if [ -z "${backup_instance_id}" ]; then
      echo -e "\e[35mNo instance with "${instance_public_ip}" public IP and stopped state found - No backup will be performed\e[0m"
    else
      echo -e "\e[36mInstance "${backup_instance_id}" with the name "${backup_instance_name}" have public IP "${instance_public_ip}" and it is in stopped state - Performing backup\e[0m"

      # Create ami image
      step_id="02-8-${prefix}"
      step_name="Create ami image"
      echo
      echo -e "\e[94m${step_id} - ${step_name}\e[0m"
      backup_date="$(date +%Y%m%d-%H%M%S)"
      image_name="${backup_instance_role}-${backup_instance_name}-${backup_date}"
      image_description="${backup_instance_project}, ${environment}, ${backup_instance_role}, ${backup_instance_name} - ${backup_date}"
      image_id="$(aws ec2 create-image --region "${region}" --instance-id "${backup_instance_id}" --name "${image_name}" --description "${image_description}" --query 'ImageId' --output text)"

      # Wait until image is available
      step_id="02-9-${prefix}"
      step_name="Wait until image is available"
      echo
      echo -e "\e[94m${step_id} - ${step_name}\e[0m"
      aws ec2 wait image-available --region "${region}" --image-ids "${image_id}"

      # Add tags to the created image
      step_id="02-10-${prefix}"
      step_name="Add tags to the created image"
      echo
      echo -e "\e[94m${step_id} - ${step_name}\e[0m"
      aws ec2 create-tags --region "${region}" --resources "${image_id}" --tags Key=Name,Value="${image_name}" Key=Project,Value="${backup_instance_project}" Key=Environment,Value="${backup_instance_environment}" Key=Creator,Value="${creator}" "Key=Description,Value='${image_description}'"

      # Terminate stopped instance
      step_id="02-11-${prefix}"
      step_name="Terminate stopped instance"
      echo
      echo -e "\e[94m${step_id} - ${step_name}\e[0m"
      aws ec2 terminate-instances --region "${region}" --instance-ids "${backup_instance_id}"
      echo -e "\e[33m${backup_instance_name} - ${backup_instance_id} - Terminating\e[0m"
      aws ec2 wait instance-terminated --region "${region}" --instance-ids "${backup_instance_id}"
      echo -e "\e[93m${backup_instance_name} - ${backup_instance_id} - Terminated\e[0m"
    fi
  fi
done

# Get list of ami images older than retention period
step_id="03"
step_name="Get list of ami images older than retention period"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
start_date="$(date --date="$images_retention_days day ago" +%Y-%m-%d)"
images_to_deregister="$(aws ec2 describe-images --region "${region}" --owner self --query "Images[?CreationDate<='${start_date}'].ImageId" --output text)"

# Show list of ami images older than retention period
step_id="04"
step_name="Show list of ami images older than retention period"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
start_date="$(date --date="$images_retention_days day ago" +%Y-%m-%d)"
aws ec2 describe-images --region "${region}" --owner self --query "Images[?CreationDate<='${start_date}'].[Name,ImageId,CreationDate,Description]" --output table

# Deregister amis older than retention period days and delete associated snapshots
step_id="05"
step_name="Deregister amis older than retention period days and delete associated snapshots"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
for image in ${images_to_deregister}; do
  snapshots_to_delete="$(aws ec2 describe-images --image-ids ${image} --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' --output text)"
  aws ec2 deregister-image --region "${region}" --image-id "${image}"
  for snapshot in ${snapshots_to_delete}; do
    aws ec2 delete-snapshot --region "${region}" --snapshot-id "${snapshot}"
  done
done

# Get list of instances
step_id="06"
step_name="Get list of instances"
echo
echo -e "\e[94m${step_id} - ${step_name}\e[0m"
aws ec2 describe-instances --region "${region}" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],Placement.AvailabilityZone,InstanceType,PublicIpAddress,State.Name,Tags[?Key=='Project'].Value|[0],Tags[?Key=='Environment'].Value|[0],Tags[?Key=='Creator'].Value|[0],LaunchTime]" --output text | sed  -e '1i Name AvailabilityZone InstanceType PublicIpAddress State Project Environment Creator LaunchTime' | column -t |  sed -e $'s/ *[^ ]* /\e[93m&\e[0m/5'

# Show task finish message
echo
echo -e "\e[96mTask '${task_name}' was finished\e[0m"
echo
echo -e "\e[96mYou may proceed with next task '${task03_name}': ${task03_file}\e[0m"
echo