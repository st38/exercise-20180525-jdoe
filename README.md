# Exercise - JDOE

 1. [Goals](#goals)
 2. [Prerequisites](#prerequisites)
 3. [Limitations](#limitations)
 4. [Requirements](#requirements)
 5. [Duration](#duration)
 6. [Usage](#usage)


## Goals

 1. Create a Shell/Python script using Amazon SDK which should check some AWS EC2 instances reachability by DNS names/IPs using at least TCP and HTTP probes and based on the results should:
    * Create an AMI image of the unreachable instances which are in stopped state.
    * After AMI creation unreachable and stopped instances should be terminated.
 2. Script also should clean up all AMIs older than 7 days.
 3. Script also should print all instances in fine-grained output, including terminated ones, with highlighting their current state.


## Prerequisites

 1. Run three AWS EC2 instances with HTTP listeners.
 2. Create three DNS records on domain.tld which should point to the instances PublicIps.
 3. Two instances should be in running state and a third one should be in stopped state.


## Limitations

 1. Variables `project_name`, `environment`, role and `creator` should not contain spaces.
 2. TCP and HTTP probes should use same port.
 3. Security group name must be unique within the VPC.
 4. Script use default VPC.


## Requirements

 1. Linux OS with [installed aws cli](https://docs.aws.amazon.com/cli/latest/userguide/installing.html).
 2. AWS account with AmazonEC2FullAccess permissions.

## Duration

 Task can be accomplished in for about 10 minutes.


## Usage

 1. Get scripts from GitHub:
	```bash
	github_username="st38"
	repository_name="exercise-20180525-jdoe"
	
	git clone https://github.com/"${github_username}"/"${repository_name}"
	```

 2. Modify variables in variables.txt:
	```bash
	cd "${repository_name}"
	
	vi variables.txt
	```

 3. Provide AWS credentials
	```bash
	export AWS_ACCESS_KEY_ID=access key
	export AWS_SECRET_ACCESS_KEY=secret access key
	export AWS_DEFAULT_REGION=eu-central-1
	```

 4. Prepare environment by running `01-prepare-environment.sh` script:
	```bash
	bash 01-prepare-environment.sh
	```
	After script execution point DNS records to the IPs from the script output. Wait some time before proceeding with next step in order to permit DNS records propagation.

 5. Execute exercise by running `02-run-exercise.sh` script:
	```bash
	bash 02-run-exercise.sh
	```

 6. Clean up environment by running `03-clean-environment.sh` script:
	```bash
	bash 03-clean-environment.sh
	```

 7. Remove data downloaded from GitHub:
	```bash
	cd ..
	
	rm -rf "${repository_name}"
	```