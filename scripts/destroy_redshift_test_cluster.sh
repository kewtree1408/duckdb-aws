#!/usr/bin/env bash
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-west-1}"
# PREFIX keeps resource names unique in a shared account.
PREFIX="${PREFIX:-vi}"
CLUSTER="$PREFIX-redshift-$AWS_DEFAULT_REGION"
ROLE="$CLUSTER-tickit-loader"

aws redshift delete-cluster --cluster-identifier "$CLUSTER" --skip-final-cluster-snapshot >/dev/null
aws redshift wait cluster-deleted --cluster-identifier "$CLUSTER"
aws iam delete-role-policy --role-name "$ROLE" --policy-name tickit-read
aws iam delete-role --role-name "$ROLE"
# Found by tag rather than by CIDR, because the caller's IP may have changed since create.
RULE_IDS=($(aws ec2 describe-security-group-rules --filters Name=tag:Name,Values="$CLUSTER" \
	--query 'SecurityGroupRules[].SecurityGroupRuleId' --output text)) || true
[[ ${#RULE_IDS[@]} -eq 0 ]] || aws ec2 revoke-security-group-ingress --group-name default --security-group-rule-ids "${RULE_IDS[@]}" >/dev/null
