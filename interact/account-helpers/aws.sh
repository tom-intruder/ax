#!/bin/bash

AXIOM_PATH="$HOME/.axiom"
source "$AXIOM_PATH/interact/includes/vars.sh"

token=""
region=""
provider=""
size=""

BASEOS="$(uname)"
case $BASEOS in
'Linux')
    BASEOS='Linux'
    ;;
'FreeBSD')
    BASEOS='FreeBSD'
    alias ls='ls -G'
    ;;
'WindowsNT')
    BASEOS='Windows'
    ;;
'Darwin')
    BASEOS='Mac'
    ;;
'SunOS')
    BASEOS='Solaris'
    ;;
'AIX') ;;
*) ;;
esac

installed_version=$(aws --version 2>/dev/null | cut -d ' ' -f 1 | cut -d '/' -f 2)

# Check if the installed version matches the recommended version
if [[ "$(printf '%s\n' "$installed_version" "$AWSCliVersion" | sort -V | head -n 1)" != "$AWSCliVersion" ]]; then
    echo -e "${Yellow}AWS CLI is either not installed or version is lower than the recommended version in ~/.axiom/interact/includes/vars.sh${Color_Off}"

    # Determine the OS type and handle installation accordingly
    if [[ $BASEOS == "Mac" ]]; then
        echo -e "${BGreen}Installing/Updating AWS CLI on macOS...${Color_Off}"
        curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
        sudo installer -pkg AWSCLIV2.pkg -target /
        rm AWSCLIV2.pkg

    elif [[ $BASEOS == "Linux" ]]; then
        if uname -a | grep -qi "Microsoft"; then
            OS="UbuntuWSL"
        else
            OS=$(lsb_release -i 2>/dev/null | awk '{ print $3 }')
            if ! command -v lsb_release &> /dev/null; then
                OS="unknown-Linux"
                BASEOS="Linux"
            fi
        fi

        # Install AWS CLI based on specific Linux distribution
        if [[ $OS == "Ubuntu" ]] || [[ $OS == "Debian" ]] || [[ $OS == "Linuxmint" ]] || [[ $OS == "Parrot" ]] || [[ $OS == "Kali" ]] || [[ $OS == "unknown-Linux" ]] || [[ $OS == "UbuntuWSL" ]]; then
            echo -e "${BGreen}Installing/Updating AWS CLI on $OS...${Color_Off}"
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
            cd /tmp
            unzip awscliv2.zip
            sudo ./aws/install
            rm -rf /tmp/aws
            rm /tmp/awscliv2.zip
        elif [[ $OS == "Fedora" ]]; then
            echo -e "${BGreen}Installing/Updating AWS CLI on Fedora...${Color_Off}"
            sudo dnf install -y unzip
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
            cd /tmp
            unzip awscliv2.zip
            sudo ./aws/install
            rm -rf /tmp/aws
            rm /tmp/awscliv2.zip
        else
            echo -e "${BRed}Unsupported Linux distribution: $OS${Color_Off}"
        fi
    fi

    echo "AWS CLI updated to version $AWSCliVersion."
else
    echo "AWS CLI is already at or above the recommended version $AWSCliVersion."
fi

function awssetup(){

echo -e "${BYellow}If this conductor runs on an EC2 instance with an IAM role attached, you can leave the credentials blank and the AWS CLI will use the instance metadata automatically.${Color_Off}"
echo -e -n "${Green}Please enter your AWS Access Key ID (leave blank to use EC2 instance profile): \n>> ${Color_Off}"
read ACCESS_KEY

echo -e -n "${Green}Please enter your AWS Secret Access Key (leave blank to use EC2 instance profile): \n>> ${Color_Off}"
read SECRET_KEY

if [[ -n "$ACCESS_KEY" && -n "$SECRET_KEY" ]]; then
    aws configure set aws_access_key_id "$ACCESS_KEY"
    aws configure set aws_secret_access_key "$SECRET_KEY"
    echo -e "${BGreen}AWS credentials configured.${Color_Off}"
else
    ACCESS_KEY="null"
    SECRET_KEY="null"
    echo -e "${BGreen}No credentials provided — will use EC2 instance profile / environment credentials.${Color_Off}"
fi
aws configure set output json

default_region="us-west-2"
echo -e -n "${Green}Please enter your default region (you can always change this later with axiom-region select \$region): Default '$default_region', press enter \n>> ${Color_Off}"
read region
	if [[ "$region" == "" ]]; then
	 echo -e "${Blue}Selected default option '$default_region'${Color_Off}"
	 region="$default_region"
        fi

echo -e -n "${Green}Please enter your default size (you can always change this later with axiom-sizes select \$size): Default 't2.micro', press enter \n>> ${Color_Off}"
read size
	if [[ "$size" == "" ]]; then
	 echo -e "${Blue}Selected default option 't2.micro'${Color_Off}"
         size="t2.micro"
        fi

echo -e -n "${Green}Please enter your default disk size in GB (you can always change this later with axiom-disks select \$disk_size): Default '20', press enter \n>> ${Color_Off}"
read disk_size
if [[ "$disk_size" == "" ]]; then
  disk_size="20"
  echo -e "${Blue}Selected default option '20'${Color_Off}"
fi

echo -e -n "${Green}Please enter an IAM instance profile name to attach to instances (e.g. axiom-worker-role). Leave blank to skip: \n>> ${Color_Off}"
read iam_instance_profile
if [[ "$iam_instance_profile" == "" ]]; then
  iam_instance_profile="null"
  echo -e "${Blue}No IAM instance profile set. Instances will use the default credentials chain.${Color_Off}"
else
  echo -e "${BGreen}Instances will be launched with IAM instance profile '$iam_instance_profile'.${Color_Off}"
fi

echo -e -n "${Green}Please enter your VPC subnet ID to launch instances into (e.g. subnet-xxxxxxxx). Leave blank to use the default VPC (public IPs): \n>> ${Color_Off}"
read subnet_id
if [[ "$subnet_id" == "" ]]; then
  echo -e "${Blue}No subnet specified, instances will use the default VPC with public IPs.${Color_Off}"
  subnet_id="null"
else
  echo -e "${Blue}Instances will be launched into subnet '$subnet_id' and reachable via private IP (conductor assumed to be on the same VPC).${Color_Off}"
fi

echo -e -n "${Green}Please enter this conductor's private IP for Redis queue mode (e.g. 10.0.1.5). Leave blank to auto-detect from EC2 metadata, or skip if not using queue mode: \n>> ${Color_Off}"
read conductor_ip
if [[ "$conductor_ip" == "" ]]; then
  # Try EC2 instance metadata (IMDSv2)
  token=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 10" 2>/dev/null)
  if [[ -n "$token" ]]; then
    conductor_ip=$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
      "http://169.254.169.254/latest/meta-data/local-ipv4" 2>/dev/null)
  fi
  if [[ -n "$conductor_ip" ]]; then
    echo -e "${BGreen}Auto-detected conductor IP from EC2 metadata: $conductor_ip${Color_Off}"
  else
    conductor_ip="null"
    echo -e "${Blue}No conductor IP set. Queue mode will not be available until conductor_ip is added to axiom.json.${Color_Off}"
  fi
fi

aws configure set default.region "$region"

# Print available security groups
echo -e "${BGreen}Printing Available Security Groups:${Color_Off}"
(
  echo -e "GroupName\tGroupId\tOwnerId\tVpcId\tFromPort\tToPort"
  aws ec2 describe-security-groups \
    --query 'SecurityGroups[*].{GroupName:GroupName,GroupId:GroupId,OwnerId:OwnerId,VpcId:VpcId,FromPort:IpPermissions[0].FromPort,ToPort:IpPermissions[0].ToPort}' \
    --output json | jq -r '.[] | [.GroupName, .GroupId, .OwnerId, .VpcId, .FromPort, .ToPort] | @tsv'
) | column -t

# Prompt user to enter a security group name
echo -e -n "${Green}Please enter a security group name above or press enter to create a new security group with a random name \n>> ${Color_Off}"
read SECURITY_GROUP

# Get all available AWS regions
all_regions=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

echo -e "${BGreen}Creating or reusing the security group '$SECURITY_GROUP' in ALL AWS regions...${Color_Off}"

# We will track the "last" group_id and group_owner_id found or created
# so the script can still store them as before.
last_group_id=""
group_owner_id=""

# If no security group name is provided, generate one (same name will be used in all regions)
if [[ "$SECURITY_GROUP" == "" ]]; then
  axiom_sg_random="axiom-$(date +%m-%d_%H-%M-%S-%1N)"
  SECURITY_GROUP=$axiom_sg_random
  echo -e "${BGreen}No Security Group provided, will create a new one: '$SECURITY_GROUP' in each region.${Color_Off}"
fi

first_group_id=""
first_owner_id=""

for r in $all_regions; do
(
  echo -e "\n${BGreen}--- Region: $r ---${Color_Off}"

  existing_group_id=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SECURITY_GROUP" \
    --region "$r" \
    --query "SecurityGroups[*].GroupId" \
    --output text 2>/dev/null)

  if [[ "$existing_group_id" == "None" ]] || [[ -z "$existing_group_id" ]]; then
    echo -e "${BGreen}Creating Security Group '$SECURITY_GROUP' in region $r...${Color_Off}"
    create_output=$(aws ec2 create-security-group \
      --group-name "$SECURITY_GROUP" \
      --description "Axiom SG" \
      --region "$r" 2>&1)

    if [[ $? -ne 0 ]]; then
      echo -e "${BRed}Failed to create security group in region $r: $create_output${Color_Off}"
      exit 0
    fi

    new_group_id=$(echo "$create_output" | jq -r '.GroupId' 2>/dev/null)
    if [[ "$new_group_id" == "null" ]]; then
      echo -e "${BRed}Could not parse GroupId from creation output. Raw output:\n$create_output${Color_Off}"
      exit 0
    fi

    echo -e "${BGreen}Created Security Group: $new_group_id in region $r${Color_Off}"
    group_id="$new_group_id"
  else
    echo -e "${BGreen}Security Group '$SECURITY_GROUP' already exists in region $r (GroupId: $existing_group_id).${Color_Off}"
    group_id="$existing_group_id"
  fi

 # Attempt to add the rule (port 2266 for 0.0.0.0/0)
 # If it already exists, AWS will throw an error that we can catch
  group_rules=$(aws ec2 authorize-security-group-ingress \
    --group-id "$group_id" \
    --protocol tcp \
    --port 2266 \
    --cidr 0.0.0.0/0 \
    --region "$r" 2>&1)
  cmd_exit_status=$?

  if [[ $cmd_exit_status -ne 0 ]]; then
    if echo "$group_rules" | grep -q "InvalidPermission.Duplicate"; then
      echo -e "${BGreen}Ingress rule already exists in region $r.${Color_Off}"
    else
      echo -e "${BRed}Failed to add rule in region $r: $group_rules${Color_Off}"
    fi
  else
    echo -e "${BGreen}Rule added successfully in region $r.${Color_Off}"
  fi

  owner_id=$(aws ec2 describe-security-groups \
    --group-ids "$group_id" \
    --region "$r" \
    --query "SecurityGroups[*].OwnerId" \
    --output text 2>/dev/null)

  if [[ -z "$first_group_id" ]]; then
    mkdir -p "$AXIOM_PATH/tmp/"
    echo "$group_id" > "$AXIOM_PATH/tmp/sg_id"
    echo "$owner_id" > "$AXIOM_PATH/tmp/sg_owner"
  fi
) &
done
wait

# Load stored first group id and owner id
if [[ -f "$AXIOM_PATH/tmp/sg_id" ]]; then
  last_group_id=$(cat "$AXIOM_PATH/tmp/sg_id")
  group_owner_id=$(cat "$AXIOM_PATH/tmp/sg_owner")
  rm "$AXIOM_PATH/tmp/sg_id" "$AXIOM_PATH/tmp/sg_owner"
else
  echo -e "${BRed}Could not determine final group ID. No group was created successfully.${Color_Off}"
  exit 1
fi

data="$(echo "{\"aws_access_key\":\"$ACCESS_KEY\",\"aws_secret_access_key\":\"$SECRET_KEY\",\"group_owner_id\":\"$group_owner_id\",\"security_group_name\":\"$SECURITY_GROUP\",\"security_group_id\":\"$last_group_id\",\"region\":\"$region\",\"provider\":\"aws\",\"default_size\":\"$size\",\"default_disk_size\":\"$disk_size\",\"iam_instance_profile\":\"$iam_instance_profile\",\"subnet_id\":\"$subnet_id\",\"conductor_ip\":\"$conductor_ip\",\"redis_port\":\"6379\"}")"

echo -e "${BGreen}Profile settings below: ${Color_Off}"
if [[ "$SECRET_KEY" != "null" ]]; then
    echo "$data" | jq '.aws_secret_access_key = "*************************************"'
else
    echo "$data" | jq '.'
fi
echo -e "${BWhite}Press enter if you want to save these to a new profile, type 'r' if you wish to start again.${Color_Off}"
read ans

if [[ "$ans" == "r" ]];
then
    $0
    exit
fi

echo -e -n "${BWhite}Please enter your profile name (e.g 'aws', must be all lowercase/no specials)\n>> ${Color_Off}"
read title

if [[ "$title" == "" ]]; then
    title="aws"
    echo -e "${BGreen}Named profile 'aws'${Color_Off}"
fi

echo "$data" | jq > "$AXIOM_PATH/accounts/$title.json"
echo -e "${BGreen}Saved profile '$title' successfully!${Color_Off}"
$AXIOM_PATH/interact/axiom-account "$title"

}

awssetup

