#!/bin/bash

if command -v terraform &> /dev/null; then
  echo "Terraform is installed. Version:"
  terraform --version
else
  echo "Terraform is not installed."
  exit 1
fi

if command -v aws &> /dev/null; then
  echo "AWS CLI is installed. Version:"
  aws --version
else
  echo "AWS CLI is not installed."
  exit 1
fi

if command -v kubectl &> /dev/null; then
  echo "Kubectl is installed. Version:"
  kubectl version --client
else
  echo "Kubectl is not installed."
  exit 1
fi

echo "All tools are installed."

echo "Launch AWS sandbox environment using this link https://learn.acloud.guru/cloud-playground/cloud-sandboxes"
echo "Once launched, copy the credentials"
echo "configure the AWS CLI using the credentials"
echo "running aws configure"

aws configure

echo "AWS CLI is configured"

echo "Create EKS cluster using terraform"

echo "Run terraform init"
terraform init

echo "Run terraform validate"
terraform validate

echo "Run terraform plan"
terraform plan

echo "Run terraform apply"
terraform apply

echo "delete the kubeconfig file"
rm -rf "$HOME/.kube/ascode-cluster"

echo "get the kubeconfig file"
aws eks update-kubeconfig --name ascode-cluster --region us-east-1 --kubeconfig "$HOME/.kube/ascode-cluster"

echo "update the kubeconfig file"
export KUBECONFIG="$HOME/.kube/ascode-cluster"

echo "verify the cluster"
kubectl get nodes

echo "create namespace"
kubectl create namespace interview

echo "create all the resources in the namespace"
kubectl apply -f nginx/deployment-bad.yaml -n interview
kubectl apply -f nginx/service-bad.yaml -n interview
kubectl create configmap example-config --from-file=nginx/index.html -n interview

user=$(aws iam create-user --user-name candidate | jq -r '.User.Arn')
echo "User created: $user"
# {
#     "User": {
#         "Path": "/",
#         "UserName": "candidate",
#         "UserId": "AIDAZF3LEWLMJQYR267UY",
#         "Arn": "arn:aws:iam::631048024792:user/candidate",
#         "CreateDate": "2024-02-07T22:03:11+00:00"
#     }
# }

# Use https://onetimesecret.com to store the output of the access key and secret key
output=$(aws iam create-access-key --user-name candidate)
echo "output of create-access-key: $output"
access_key=$(echo $output | jq -r '.AccessKey.AccessKeyId')
secret_key=$(echo $output | jq -r '.AccessKey.SecretAccessKey')
echo "Access key created: $access_key"
echo "Secret key: $secret_key"

cluster_arn=$(aws eks describe-cluster --name ascode-cluster --region us-east-1 | jq -r '.cluster.arn')
echo "Cluster ARN: $cluster_arn"

# Create policy JSON document
cat << EOF > eks-kubectl-user-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster"
            ],
            "Resource": "$cluster_arn"
        }
    ]
}
EOF
# Create IAM policy
policy=$(aws iam create-policy --policy-name eks-kubectl-user-policy --policy-document file://eks-kubectl-user-policy.json | jq -r '.Policy.Arn')
# Attach to user using policy ARN from previous command
aws iam attach-user-policy --user-name candidate --policy-arn "$policy"

cat << EOF > patch.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapUsers: |
    - userarn: $user
      username: username
      groups:
        - system:masters
EOF
# give the user access to the cluster
kubectl patch configmap/aws-auth -n kube-system --patch "$(cat patch.yaml)"

aws configure --profile candidate
aws --profile candidate eks update-kubeconfig --name ascode-cluster --region us-east-1 --kubeconfig "$HOME/.kube/candidate-ascode-cluster"
export KUBECONFIG="$HOME/.kube/candidate-ascode-cluster"

echo "verify the permissions"
kubectl get namespaces