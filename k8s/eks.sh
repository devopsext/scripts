#!/bin/bash
SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

. $SCRIPTS_DIR/std/utils.sh
. $SCRIPTS_DIR/k8s/kubectl.sh

K8S_EKS_ACCOUNT_ID=${K8S_EKS_ACCOUNT_ID:=""}
K8S_EKS_REGION=${K8S_EKS_REGION:=""}
K8S_EKS_DESTROY_K8S_RESOURCES=${K8S_EKS_DESTROY_K8S_RESOURCES:="true"}

function k8sEKSAfterCreate() {
  local tfState="$1"

  if [[ -z $(which aws) ]]; then
    stdLogErr "'aws cli is not installed or not found in $PATH"
    return 1
  fi

  stdLogInfo "Terraform state: $tfState"

  if [ -f "$tfState" ]; then

    local nodeARN=$(cat "$tfState" | jq -r '. | .resources[]? | select(.type=="aws_iam_role") | select(.name=="node") | .instances[]? | .attributes.arn')

    local cfgMapNotExist=$(kubectl get configmap aws-auth &>/dev/null || echo "$?")
    if [[ "$cfgMapNotExist" == "" ]]; then
      cfgMapNotExist=0
    fi

    stdLogInfo "Node ARN $nodeARN. Config map is not exists $cfgMapNotExist"

    if [[ "$nodeARN" != "" ]] && [[ "$cfgMapNotExist" == "1" ]]; then

      local tmpDir=$(mktemp -d)
      local cfgMapYML="$tmpDir/configmap.yml"

      cat <<EOF >${cfgMapYML}
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${nodeARN}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
EOF

      stdLogInfo "Applying config map..."
      kubectl apply -f "$cfgMapYML"
      rm -rf "$tmpDir"

    else
      stdLogWarn "Node ARN is not found or Config map doesn't exist!"
    fi

    #Get eks cluster VPC ID, for tagging subnets...
    stdLogInfo "Tagging subnets..."
    aws configure set region "$K8S_EKS_REGION"
    local eksClusterName=$(cat "$tfState" | jq -r '. | .resources[]? | select(.type=="aws_eks_cluster") | select (.module=="module.cluster") | .instances[]? | .attributes | .name')
    local eksClusterVPCIds=$(cat "$tfState" | jq -r '. | .resources[]? | select(.type=="aws_eks_cluster") | select (.module=="module.cluster") | .instances[]? | .attributes | .vpc_config[]? | .vpc_id')

    for vpcID in $(echo "$eksClusterVPCIds" | sed -E 's/\n//g'); do
      stdLogDebug "Processing subnets in vpc '$vpcID'..."

      local vpcSugnetsList=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$vpcID" | jq -r '.Subnets[]? | .SubnetId')
      for subnetID in $(echo "$vpcSugnetsList" | sed -E 's/\n//g'); do
        stdLogDebug "Tagging $subnetID with 'kubernetes.io/cluster/$eksClusterName=shared'"
        aws ec2 create-tags --resources "$subnetID" --tags Key="kubernetes.io/cluster/$eksClusterName",Value="shared"
      done

    done

  else
    stdLogWarn "Terraform state is not found..."
  fi
}

function k8sEKSAfterInit() {

  if [[ -z $(which aws) ]]; then
    stdLogErr "'aws cli is not installed or not found in $PATH"
    return 1
  fi

  local tfState="$1"
  #Searching for volumes to be tagged with project and owner
  stdLogDebug "Terraform state: $tfState"

  if [ -f "$tfState" ]; then

    #Tagging volumes
    aws configure set region "$K8S_EKS_REGION"
    local eksClusterOwnerTag=$(cat "$tfState" | jq -r '. | .resources[]? | select(.type=="aws_eks_cluster") | select (.module=="module.cluster") | .instances[]? | .attributes | .tags.owner')
    local eksClusterProjectTag=$(cat "$tfState" | jq -r '. | .resources[]? | select(.type=="aws_eks_cluster") | select (.module=="module.cluster") | .instances[]? | .attributes | .tags.project')

    if ([[ ! "$eksClusterOwnerTag" == "null" ]] && [[ ! "$eksClusterProjectTag" == "null" ]]); then
      stdLogInfo "Tagging volumes..."

      local eksClusterName=$(cat "$tfState" | jq -r '. | .resources[]? | select(.type=="aws_eks_cluster") | select (.module=="module.cluster") | .instances[]? | .attributes | .name')
      local volumesList=$(aws ec2 describe-volumes \
        --filters "Name=tag:kubernetes.io/cluster/$eksClusterName,Values=owned" \
        --query "Volumes[*].VolumeId" | jq -r '.[]?')

      for volumeID in $(echo "$volumesList" | sed -E 's/\n//g'); do
        stdLogDebug "Tagging $volumeID with 'owner=$eksClusterOwnerTag' & 'project=$eksClusterProjectTag'"
        aws ec2 create-tags --resources "$volumeID" \
          --tags Key="owner",Value="$eksClusterOwnerTag" \
          Key="project",Value="$eksClusterProjectTag" || stdLogWarn "Can't set tags to volume '$volumeID'"
      done
    else
      stdLogInfo "Project and owner tags are not set, skipping volumes tagging..."
    fi

  else
    stdLogWarn "Terraform state is not found..."
  fi
}

function k8sEKSBeforeDestroy() {
  local tfState="$1"
  local stateDir="$2"

  if [[ -z $(which aws) ]]; then
    stdLogErr "'aws cli is not installed or not found in $PATH"
    return 1
  fi

  stdLogDebug "Terraform state: $tfState"

  if [ -f "$tfState" ]; then

    #Get eks cluster VPC ID, for tagging subnets...
    stdLogInfo "Untagging subnets..."
    aws configure set region "$K8S_EKS_REGION"
    local eksClusterName=$(cat "$tfState" | jq -r '. | .resources[]? | select(.type=="aws_eks_cluster") | select (.module=="module.cluster") | .instances[]? | .attributes | .name')
    local eksClusterVPCIds=$(cat "$tfState" | jq -r '. | .resources[]? | select(.type=="aws_eks_cluster") | select (.module=="module.cluster") | .instances[]? | .attributes | .vpc_config[]? | .vpc_id')

    for vpcID in $(echo "$eksClusterVPCIds" | sed -E 's/\n//g'); do
      stdLogDebug "Processing subnets in vpc '$vpcID'..."

      local vpcSugnetsList=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$vpcID" | jq -r '.Subnets[]? | .SubnetId')
      for subnetID in $(echo "$vpcSugnetsList" | sed -E 's/\n//g'); do
        stdLogDebug "Removing tag 'kubernetes.io/cluster/$eksClusterName=shared' from subnet '$subnetID'"
        aws ec2 delete-tags --resources "$subnetID" --tags Key="kubernetes.io/cluster/$eksClusterName",Value="shared"
      done

    done
  else
    stdLogWarn "Terraform state is not found..."
  fi

  if [[ "$K8S_EKS_DESTROY_K8S_RESOURCES" == "true" ]]; then
    stdLogInfo "Destroying k8s resources before cluster destroy..."
    k8sKubectlRemoveK8SContent || true #Proceed with destroy even if cluster is destroyed or kubectl config is not valid
  else
    stdLogWarn "Removing k8s resources before cluster destroy is skipped..."
  fi
}
