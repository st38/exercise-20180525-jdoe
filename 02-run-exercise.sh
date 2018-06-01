#!/bin/bash

# Read variables
source variables.txt

# Verify hosts reachability

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
  probe=ICMP
  ping -W 2 -c 4 "${hostname}" >/dev/null
  icmp_probe_status="$?"
  eval status="${icmp_probe_status}"
  probe_status

  # Perform TCP probe
  probe=TCP
  nc -w 3 "${hostname}" "${tcp_port}"
  tcp_probe_status="$?"
  eval status="${tcp_probe_status}"
  probe_status

  # Perform HTTP probe
  probe=HTTP
  wget --tries=1 --timeout=3 --no-check-certificate --quiet --output-document=/dev/null "${http_protocol}"://"${hostname}":"${http_port}"/
  http_probe_status="$?"
  eval status="${http_probe_status}"
  probe_status
  overall_probes_status="$(($icmp_probe_status+$tcp_probe_status+$http_probe_status))"

  # Compute overall reachability and if backup should be performed
  if [ "${overall_probes_status}" = "0" ]; then
    echo -e     "\e[36m"${hostname}" is UP - Backup should not be performed\e[0m"
  else
    echo -e     "\e[35m"${hostname}" is DOWN - Backup should be performed\e[0m"

    # Get unreachable instance public ip
    instance_public_ip="$(dig +short ${prefix}.${domain_name})"

    # Get unreachable and stopped instance id and name
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
      backup_date="$(date +%Y%m%d-%H%M%S)"
      image_name="${backup_instance_role}-${backup_instance_name}-${backup_date}"
      image_description="${backup_instance_project}, ${environment}, ${backup_instance_role}, ${backup_instance_name} - ${backup_date}"
      image_id="$(aws ec2 create-image --region "${region}" --instance-id "${backup_instance_id}" --name "${image_name}" --description "${image_description}" --query 'ImageId' --output text)"

      # Wait until image is available
      aws ec2 wait image-available --region "${region}" --image-ids "${image_id}"

      # Add tags to the created image
      aws ec2 create-tags --region "${region}" --resources "${image_id}" --tags Key=Name,Value="${image_name}" Key=Project,Value="${backup_instance_project}" Key=Environment,Value="${backup_instance_environment}" Key=Creator,Value="${creator}" "Key=Description,Value='${image_description}'"

      # Terminate stopped instance
      aws ec2 terminate-instances --region "${region}" --instance-ids "${backup_instance_id}"
      aws ec2 wait instance-terminated --region "${region}" --instance-ids "${backup_instance_id}"
    fi
  fi
done

# Deregister amis older than retention period days and delete associated snapshots
start_date="$(date --date="$images_retention_days day ago" +%Y-%m-%d)"
images_to_deregister="$(aws ec2 describe-images --region "${region}" --owner self --query "Images[?CreationDate<='${start_date}'].ImageId" --output text)"
for image in ${images_to_deregister}; do
  snapshots_to_delete="$(aws ec2 describe-images --image-ids ${image} --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' --output text)"
  aws ec2 deregister-image --region "${region}" --image-id "${image}"
  for snapshot in ${snapshots_to_delete}; do
    aws ec2 delete-snapshot --region "${region}" --snapshot-id "${snapshot}"
  done
done

# Get list of instances
aws ec2 describe-instances --region "${region}" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],Placement.AvailabilityZone,InstanceType,PublicIpAddress,State.Name,Tags[?Key=='Project'].Value|[0],Tags[?Key=='Environment'].Value|[0],Tags[?Key=='Creator'].Value|[0],LaunchTime]" --output text | sed  -e '1i Name AvailabilityZone InstanceType PublicIpAddress State Project Environment Creator LaunchTime' | column -t |  sed -e $'s/ *[^ ]* /\e[93m&\e[0m/5'
