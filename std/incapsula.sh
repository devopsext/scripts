#!/bin/bash
SCRIPTS_DIR=${SCRIPTS_DIR:="/scripts"}

  . /scripts/std/utils.sh
  . /scripts/k8s/state.sh

  function AddIncapsulaWhitelistAli () {

    local terraformState="$1"
    local response=""
    local resCode=""
    local resMsg=""
    local currSiteDomain=""
    local siteId=""
    local siteName="$2"

    local incapsulaURL=${INCAPSULA_URL:="https://my.imperva.com"}

    local incapsulaAPIURL="${incapsulaURL}/api/prov/v1"
    local incapsulaAPIId="${INCAPSULA_API_ID}"
    local incapsulaAPIKey="${INCAPSULA_API_KEY}"

    stdLogInfo "___INCAPSULA:"

    #Getting Nat Gateway external IP
    vpcid=$(cat "$terraformState" | jq -r '.resources[] | select(.name == "vpc") | .instances[]?.attributes.id')

    echo "$vpcid"

    natgatewayid=$(aliyun ecs DescribeNatGateways | jq -r '.NatGateways.NatGateway[] | select(.VpcId == '\"$vpcid\"') | .NatGatewayId')
    echo "$natgatewayid"

    natextip=$(aliyun vpc DescribeEipAddresses | jq -r '.EipAddresses.EipAddress[] | select(.InstanceId == '\"$natgatewayid\"') | .IpAddress')
    echo "$natextip"

    #Getting site ID
    response=$(curl --silent -m 60 --data "api_id=$incapsulaAPIId&api_key=$incapsulaAPIKey" "${incapsulaAPIURL}/sites/list") || stdLogErr "Error getting list of incapsula sites..."
    resCode=$(stdGetValueFromJson "$response" ".res") || stdLogExit
    resMsg=$(stdGetValueFromJson "$response" ".res_message") || stdLogExit

    if [[ ! "$resCode" -eq 0 ]]; then
      stdLogErr "$resMsg"
    else

      local sites=$(echo "$response" | jq '.sites')
      local arrayLength=$(echo "$sites" | jq 'length')

      for(( i=0; i<"$arrayLength"; i++));do
        currSiteDomain=$(stdGetValueFromJson "$sites" "["$i"].domain" ) || return 1
        if [[ "$currSiteDomain" == "$siteName" ]]; then
          siteId=$(stdGetValueFromJson "$sites" "["$i"].site_id" ) || return 1
          break
        fi	
      done

      if [[ -z "$siteId" ]]; then
        stdLogErr "Can't find incapsula site ID for site '$siteName'..."
        return
      fi	
    fi	

    stdLogInfo "Start getting White List for $siteName ($siteId)..."

    wafrules=$(echo $response | jq -r '.sites[] | select(.site_id == '"$siteId"') | .security.waf.rules')
    wafexceptions=$(echo $wafrules | jq -r '.[] | select(.id == "api.threats.bot_access_control") | .exceptions')
    exceptionid=$(echo $wafexceptions | jq -r '.[] | select((.values[]?.ips[]? | contains('\"$natextip\"')) and (.values[]?.id == "api.rule_exception_type.client_ip")) | .id')

    if [[ -z "$exceptionid" ]]; then
      stdLogInfo "Adding $natextip to exceptions"
    else
      stdLogErr "Exception with id $exceptionid contains $natextip"
    fi

    ruleId="api.acl.whitelisted_ips"
    aclsrules=$(echo $response | jq -r '.sites[] | select(.site_id == '"$siteId"') | .security.acls.rules')
    aclwhitelistcontain=$(echo $aclsrules| jq -r '.[] | select((.ips[]? | contains('\"$natextip\"')) and (.id == "api.acl.whitelisted_ips")) | .ips')

    iparray=$(echo $aclsrules | jq -r '.[] | select(.id == "api.acl.whitelisted_ips") | .ips | join (",")')
    
    if [[ -z "$aclwhitelistcontain" ]]; then
      stdLogInfo "Adding "$natextip" to whitelist"
      newiparray="${iparray},${natextip}"
      echo "New whitelist $newiparray"
      pushwhitelist=$(curl --silent -m 60 --data "api_id=$incapsulaAPIId&api_key=$incapsulaAPIKey&site_id=$siteId&rule_id=$ruleId&ips=$newiparray" "${incapsulaAPIURL}/sites/configure/acl") || stdLogErr "Error updating whitelist, check the response message..."
      resCode=$(stdGetValueFromJson "$pushwhitelist" ".res") || stdLogExit
      resMsg=$(stdGetValueFromJson "$pushwhitelist" ".res_message") || stdLogExit
      if [[ ! "$resCode" -eq 0 ]]; then
        stdLogErr "$resMsg"
      else
        stdLogDebug "Incapsula whitelist updated..."	
      fi
    else
      stdLogErr "Whitelist contains $natextip"
    fi
  }

  function DelIncapsulaWhitelistAli () {

    local terraformState="$1"
    local response=""
    local resCode=""
    local resMsg=""
    local currSiteDomain=""
    local siteId=""
    local siteName="$2"

    local incapsulaURL=${INCAPSULA_URL:="https://my.imperva.com"}

    local incapsulaAPIURL="${incapsulaURL}/api/prov/v1"
    local incapsulaAPIId="${INCAPSULA_API_ID}"
    local incapsulaAPIKey="${INCAPSULA_API_KEY}"

    stdLogInfo "___INCAPSULA:"

    #Getting Nat Gateway external IP
    vpcid=$(cat "$terraformState" | jq -r '.resources[] | select(.name == "vpc") | .instances[]?.attributes.id')

    echo "$vpcid"

    natgatewayid=$(aliyun ecs DescribeNatGateways | jq -r '.NatGateways.NatGateway[] | select(.VpcId == '\"$vpcid\"') | .NatGatewayId')
    echo "$natgatewayid"

    natextip=$(aliyun vpc DescribeEipAddresses | jq -r '.EipAddresses.EipAddress[] | select(.InstanceId == '\"$natgatewayid\"') | .IpAddress')
    echo "$natextip"

    #Getting site ID
    response=$(curl --silent -m 60 --data "api_id=$incapsulaAPIId&api_key=$incapsulaAPIKey" "${incapsulaAPIURL}/sites/list") || stdLogErr "Error getting list of incapsula sites..."
    resCode=$(stdGetValueFromJson "$response" ".res") || stdLogExit
    resMsg=$(stdGetValueFromJson "$response" ".res_message") || stdLogExit

    if [[ ! "$resCode" -eq 0 ]]; then
      stdLogErr "$resMsg"
    else

      local sites=$(echo "$response" | jq '.sites')
      local arrayLength=$(echo "$sites" | jq 'length')

      for(( i=0; i<"$arrayLength"; i++));do
        currSiteDomain=$(stdGetValueFromJson "$sites" "["$i"].domain" ) || return 1
        if [[ "$currSiteDomain" == "$siteName" ]]; then
          siteId=$(stdGetValueFromJson "$sites" "["$i"].site_id" ) || return 1
          break
        fi	
      done

      if [[ -z "$siteId" ]]; then
        stdLogErr "Can't find incapsula site ID for site '$siteName'..."
        return
      fi	
    fi	

    stdLogInfo "Start getting White List for $siteName ($siteId)..."

    wafrules=$(echo $response | jq -r '.sites[] | select(.site_id == '"$siteId"') | .security.waf.rules')
    wafexceptions=$(echo $wafrules | jq -r '.[] | select(.id == "api.threats.bot_access_control") | .exceptions')
    exceptionid=$(echo $wafexceptions | jq -r '.[] | select((.values[]?.ips[]? | contains('\"$natextip\"')) and (.values[]?.id == "api.rule_exception_type.client_ip")) | .id')

    if [[ -z "$exceptionid" ]]; then
      stdLogErr "Exceptions don't contain $natextip"
    else
      stdLogInfo "Removing $natextip from exceptions"
    fi

    ruleId="api.acl.whitelisted_ips"
    aclsrules=$(echo $response | jq -r '.sites[] | select(.site_id == '"$siteId"') | .security.acls.rules')
    aclwhitelistcontain=$(echo $aclsrules| jq -r '.[] | select((.ips[]? | contains('\"$natextip\"')) and (.id == "api.acl.whitelisted_ips")) | .ips')

    iparray=$(echo $aclsrules | jq -r '.[] | select(.id == "api.acl.whitelisted_ips") | .ips | join (",")')
    
    if [[ -z "$aclwhitelistcontain" ]]; then
      stdLogErr "Whitelist doesn't contains $natextip"
    else
      stdLogInfo "Removing "$natextip" from whitelist"
      newiparray=$(echo $iparray | sed 's/'"$natextip"'//' | sed 's/,,/,/' | sed 's/^,//' | sed 's/,*\r*$//')
      echo "New whitelist $newiparray"
      pushwhitelist=$(curl --silent -m 60 --data "api_id=$incapsulaAPIId&api_key=$incapsulaAPIKey&site_id=$siteId&rule_id=$ruleId&ips=$newiparray" "${incapsulaAPIURL}/sites/configure/acl") || stdLogErr "Error updating whitelist, check the response message..."
      resCode=$(stdGetValueFromJson "$pushwhitelist" ".res") || stdLogExit
      resMsg=$(stdGetValueFromJson "$pushwhitelist" ".res_message") || stdLogExit
      if [[ ! "$resCode" -eq 0 ]]; then
        stdLogErr "$resMsg"
      else
        stdLogDebug "Incapsula whitelist updated..."	
      fi
    fi
  }


  function AddIncapsulaWhitelistAws () {

    local terraformState="$1"
    local response=""
    local resCode=""
    local resMsg=""
    local currSiteDomain=""
    local siteId=""
    local siteName="$2"

    local incapsulaURL=${INCAPSULA_URL:="https://my.imperva.com"}

    local incapsulaAPIURL="${incapsulaURL}/api/prov/v1"
    local incapsulaAPIId="${INCAPSULA_API_ID}"
    local incapsulaAPIKey="${INCAPSULA_API_KEY}"

    stdLogInfo "___INCAPSULA:"

    #Getting Nat Gateway external IP
    vpcid=$(cat "$terraformState" | jq -r '.resources[] | select(.name == "vpc") | .instances[]?.attributes.id')
    echo "$vpcid"

    for natextip in $(cat "$terraformState" | jq -r '.resources[] | select(.name == "nat_gw_eip") | .instances[].attributes.public_ip')
    do 
      echo "$natextip"

      #Getting site ID
      response=$(curl --silent -m 60 --data "api_id=$incapsulaAPIId&api_key=$incapsulaAPIKey" "${incapsulaAPIURL}/sites/list") || stdLogErr "Error getting list of incapsula sites..."
      resCode=$(stdGetValueFromJson "$response" ".res") || stdLogExit
      resMsg=$(stdGetValueFromJson "$response" ".res_message") || stdLogExit

      if [[ ! "$resCode" -eq 0 ]]; then
        stdLogErr "$resMsg"
      else

        local sites=$(echo "$response" | jq '.sites')
        local arrayLength=$(echo "$sites" | jq 'length')

        for(( i=0; i<"$arrayLength"; i++));do
          currSiteDomain=$(stdGetValueFromJson "$sites" "["$i"].domain" ) || return 1
          if [[ "$currSiteDomain" == "$siteName" ]]; then
            siteId=$(stdGetValueFromJson "$sites" "["$i"].site_id" ) || return 1
            break
          fi	
        done

        if [[ -z "$siteId" ]]; then
          stdLogErr "Can't find incapsula site ID for site '$siteName'..."
          return
        fi	
      fi	

      stdLogInfo "Start getting White List for $siteName ($siteId)..."

      wafrules=$(echo $response | jq -r '.sites[] | select(.site_id == '"$siteId"') | .security.waf.rules')
      wafexceptions=$(echo $wafrules | jq -r '.[] | select(.id == "api.threats.bot_access_control") | .exceptions')
      exceptionid=$(echo $wafexceptions | jq -r '.[] | select((.values[]?.ips[]? | contains('\"$natextip\"')) and (.values[]?.id == "api.rule_exception_type.client_ip")) | .id')

      if [[ -z "$exceptionid" ]]; then
        stdLogInfo "Adding $natextip to exceptions"
      else
        stdLogErr "Exception with id $exceptionid contains $natextip"
      fi

      ruleId="api.acl.whitelisted_ips"
      aclsrules=$(echo $response | jq -r '.sites[] | select(.site_id == '"$siteId"') | .security.acls.rules')
      aclwhitelistcontain=$(echo $aclsrules| jq -r '.[] | select((.ips[]? | contains('\"$natextip\"')) and (.id == "api.acl.whitelisted_ips")) | .ips')

      iparray=$(echo $aclsrules | jq -r '.[] | select(.id == "api.acl.whitelisted_ips") | .ips | join (",")')

      if [[ -z "$aclwhitelistcontain" ]]; then
        stdLogInfo "Adding "$natextip" to whitelist"
        newiparray="${iparray},${natextip}"
        echo "New whitelist $newiparray"
        pushwhitelist=$(curl --silent -m 60 --data "api_id=$incapsulaAPIId&api_key=$incapsulaAPIKey&site_id=$siteId&rule_id=$ruleId&ips=$newiparray" "${incapsulaAPIURL}/sites/configure/acl") || stdLogErr "Error updating whitelist, check the response message..."
        resCode=$(stdGetValueFromJson "$pushwhitelist" ".res") || stdLogExit
        resMsg=$(stdGetValueFromJson "$pushwhitelist" ".res_message") || stdLogExit
        if [[ ! "$resCode" -eq 0 ]]; then
          stdLogErr "$resMsg"
        else
          stdLogDebug "Incapsula whitelist updated..."	
        fi
      else
        stdLogErr "Whitelist contains $natextip"
      fi
    done
  }

  function DelIncapsulaWhitelistAws () {

    local terraformState="$1"
    local response=""
    local resCode=""
    local resMsg=""
    local currSiteDomain=""
    local siteId=""
    local siteName="$2"

    local incapsulaURL=${INCAPSULA_URL:="https://my.imperva.com"}

    local incapsulaAPIURL="${incapsulaURL}/api/prov/v1"
    local incapsulaAPIId="${INCAPSULA_API_ID}"
    local incapsulaAPIKey="${INCAPSULA_API_KEY}"

    stdLogInfo "___INCAPSULA:"

    #Getting Nat Gateway external IP
    vpcid=$(cat "$terraformState" | jq -r '.resources[] | select(.name == "vpc") | .instances[]?.attributes.id')

    echo "$vpcid"

    for natextip in $(cat "$terraformState" | jq -r '.resources[] | select(.name == "nat_gw_eip") | .instances[].attributes.public_ip')
    do
      echo "$natextip"

      #Getting site ID
      response=$(curl --silent -m 60 --data "api_id=$incapsulaAPIId&api_key=$incapsulaAPIKey" "${incapsulaAPIURL}/sites/list") || stdLogErr "Error getting list of incapsula sites..."
      resCode=$(stdGetValueFromJson "$response" ".res") || stdLogExit
      resMsg=$(stdGetValueFromJson "$response" ".res_message") || stdLogExit

      if [[ ! "$resCode" -eq 0 ]]; then
        stdLogErr "$resMsg"
      else

        local sites=$(echo "$response" | jq '.sites')
        local arrayLength=$(echo "$sites" | jq 'length')

        for(( i=0; i<"$arrayLength"; i++));do
          currSiteDomain=$(stdGetValueFromJson "$sites" "["$i"].domain" ) || return 1
          if [[ "$currSiteDomain" == "$siteName" ]]; then
            siteId=$(stdGetValueFromJson "$sites" "["$i"].site_id" ) || return 1
            break
          fi	
        done

        if [[ -z "$siteId" ]]; then
          stdLogErr "Can't find incapsula site ID for site '$siteName'..."
          return
        fi	
      fi	

      stdLogInfo "Start getting White List for $siteName ($siteId)..."

      wafrules=$(echo $response | jq -r '.sites[] | select(.site_id == '"$siteId"') | .security.waf.rules')
      wafexceptions=$(echo $wafrules | jq -r '.[] | select(.id == "api.threats.bot_access_control") | .exceptions')
      exceptionid=$(echo $wafexceptions | jq -r '.[] | select((.values[]?.ips[]? | contains('\"$natextip\"')) and (.values[]?.id == "api.rule_exception_type.client_ip")) | .id')

      if [[ -z "$exceptionid" ]]; then
        stdLogErr "Exceptions don't contain $natextip"
      else
        stdLogInfo "Removing $natextip from exceptions"
      fi

      ruleId="api.acl.whitelisted_ips"
      aclsrules=$(echo $response | jq -r '.sites[] | select(.site_id == '"$siteId"') | .security.acls.rules')
      aclwhitelistcontain=$(echo $aclsrules| jq -r '.[] | select((.ips[]? | contains('\"$natextip\"')) and (.id == "api.acl.whitelisted_ips")) | .ips')

      iparray=$(echo $aclsrules | jq -r '.[] | select(.id == "api.acl.whitelisted_ips") | .ips | join (",")')

      if [[ -z "$aclwhitelistcontain" ]]; then
        stdLogErr "Whitelist doesn't contains $natextip"
      else
        stdLogInfo "Removing "$natextip" from whitelist"
        newiparray=$(echo $iparray | sed 's/'"$natextip"'//' | sed 's/,,/,/' | sed 's/^,//' | sed 's/,*\r*$//')
        echo "New whitelist $newiparray"
        pushwhitelist=$(curl --silent -m 60 --data "api_id=$incapsulaAPIId&api_key=$incapsulaAPIKey&site_id=$siteId&rule_id=$ruleId&ips=$newiparray" "${incapsulaAPIURL}/sites/configure/acl") || stdLogErr "Error updating whitelist, check the response message..."
        resCode=$(stdGetValueFromJson "$pushwhitelist" ".res") || stdLogExit
        resMsg=$(stdGetValueFromJson "$pushwhitelist" ".res_message") || stdLogExit
        if [[ ! "$resCode" -eq 0 ]]; then
          stdLogErr "$resMsg"
        else
          stdLogDebug "Incapsula whitelist updated..."	
        fi
      fi
    done
  }

  function AddProviderByState () {
    local terraformState="$1"
    local siteName="$2"
    provider=$(cat $terraformState | jq -r '.resources[] | select(.name == "cluster" and .type == "alicloud_cs_managed_kubernetes" or .type == "aws_eks_cluster") | .provider')

    if [[ $provider == 'module.cluster.provider.alicloud' ]]; then
      AddIncapsulaWhitelistAli $terraformState $siteName
    elif [[ $provider == 'module.cluster.provider.aws' ]]; then
      AddIncapsulaWhitelistAws $terraformState $siteName
    else
      echo "Unsupported provider "
    fi
  }

  function DelProviderByState () {
    local terraformState="$1"
    local siteName="$2"
    provider=$(cat $terraformState | jq -r '.resources[] | select(.name == "cluster" and .type == "alicloud_cs_managed_kubernetes" or .type == "aws_eks_cluster") | .provider')

    if [[ $provider == 'module.cluster.provider.alicloud' ]]; then
      DelIncapsulaWhitelistAli $terraformState $siteName
    elif [[ $provider == 'module.cluster.provider.aws' ]]; then
      DelIncapsulaWhitelistAws $terraformState $siteName
    else
      echo "Unsupported provider "
    fi
  }
