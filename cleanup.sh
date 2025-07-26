#!/bin/bash

# Flask Portfolio App - AWS Resource Cleanup Script
# Deletes all resources created by deploy.sh including custom VPC infrastructure

set -e

DEPLOYMENT_FILE="infra/deployment-info.txt"

echo "🧹 Starting Flask Portfolio App cleanup..."

# Check if deployment info file exists
if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "❌ Deployment info file not found: $DEPLOYMENT_FILE"
    echo "Cannot proceed with cleanup without deployment information."
    exit 1
fi

# Source the deployment information
source $DEPLOYMENT_FILE

echo "📋 Found deployment from $(head -1 $DEPLOYMENT_FILE)"
echo "🎯 Target resources:"
echo "   S3 Bucket: $S3_BUCKET"
echo "   RDS Instance: $RDS_IDENTIFIER"
echo "   EC2 Instance: $INSTANCE_ID"
echo "   VPC: $VPC_ID"
echo "   EC2 Security Group: $EC2_SECURITY_GROUP_ID"
echo "   RDS Security Group: $RDS_SECURITY_GROUP_ID"
echo "   IAM Role: $IAM_ROLE"
echo ""

read -p "⚠️  Are you sure you want to delete ALL these resources? (yes/no): " confirmation
if [ "$confirmation" != "yes" ]; then
    echo "❌ Cleanup cancelled."
    exit 0
fi

echo "🚀 Starting resource cleanup..."

# Step 1: Terminate EC2 Instance
if [ ! -z "$INSTANCE_ID" ]; then
    echo "🖥️ Step 1: Terminating EC2 instance..."
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID > /dev/null
    echo "✅ EC2 instance termination initiated: $INSTANCE_ID"
    
    echo "⏳ Waiting for instance to terminate..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
    echo "✅ EC2 instance terminated successfully"
else
    echo "⚠️ No EC2 instance ID found"
fi

# Step 2: Delete RDS Instance
if [ ! -z "$RDS_IDENTIFIER" ]; then
    echo "🗃️ Step 2: Deleting RDS database..."
    aws rds delete-db-instance \
        --db-instance-identifier $RDS_IDENTIFIER \
        --skip-final-snapshot \
        --delete-automated-backups > /dev/null
    echo "✅ RDS deletion initiated: $RDS_IDENTIFIER"
    
    echo "⏳ Waiting for RDS to be deleted (this may take several minutes)..."
    aws rds wait db-instance-deleted --db-instance-identifier $RDS_IDENTIFIER
    echo "✅ RDS database deleted successfully"
    
    # Delete DB subnet group
    if [ ! -z "$SUBNET_GROUP_NAME" ]; then
        aws rds delete-db-subnet-group --db-subnet-group-name $SUBNET_GROUP_NAME 2>/dev/null || echo "⚠️ DB subnet group not found or already deleted"
    else
        # Try default name
        aws rds delete-db-subnet-group --db-subnet-group-name "portfolio-app-subnet-group" 2>/dev/null || echo "⚠️ DB subnet group not found or already deleted"
    fi
else
    echo "⚠️ No RDS identifier found"
fi

# Step 3: Empty and delete S3 bucket
if [ ! -z "$S3_BUCKET" ]; then
    echo "📦 Step 3: Emptying and deleting S3 bucket..."
    
    # Empty bucket first
    aws s3 rm "s3://$S3_BUCKET" --recursive 2>/dev/null || echo "⚠️ S3 bucket already empty or not found"
    
    # Delete bucket
    aws s3 rb "s3://$S3_BUCKET" 2>/dev/null || echo "⚠️ S3 bucket not found or already deleted"
    echo "✅ S3 bucket deleted: $S3_BUCKET"
else
    echo "⚠️ No S3 bucket found"
fi

# Step 4: Delete Security Groups (order matters - RDS first, then EC2)
echo "🔒 Step 4: Deleting security groups..."

# Wait for resources to be fully terminated
echo "⏳ Waiting for resources to be fully terminated..."
sleep 30

if [ ! -z "$RDS_SECURITY_GROUP_ID" ]; then
    aws ec2 delete-security-group --group-id $RDS_SECURITY_GROUP_ID 2>/dev/null || echo "⚠️ RDS security group not found or has dependencies"
    echo "✅ RDS security group deleted: $RDS_SECURITY_GROUP_ID"
fi

if [ ! -z "$EC2_SECURITY_GROUP_ID" ]; then
    aws ec2 delete-security-group --group-id $EC2_SECURITY_GROUP_ID 2>/dev/null || echo "⚠️ EC2 security group not found or has dependencies"
    echo "✅ EC2 security group deleted: $EC2_SECURITY_GROUP_ID"
fi

# Step 5: Delete VPC Infrastructure (if we created a custom VPC)
if [ ! -z "$VPC_ID" ]; then
    echo "🌐 Step 5: Cleaning up VPC infrastructure..."
    
    # Check if this is a default VPC
    IS_DEFAULT=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].IsDefault' --output text 2>/dev/null || echo "false")
    
    if [ "$IS_DEFAULT" = "false" ]; then
        echo "🗑️ Deleting custom VPC infrastructure..."
        
        # Get VPC components
        IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "None")
        ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=false" --query 'RouteTables[].RouteTableId' --output text 2>/dev/null || echo "")
        SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
        
        # Delete subnets
        for subnet_id in $SUBNET_IDS; do
            if [ "$subnet_id" != "" ] && [ "$subnet_id" != "None" ]; then
                aws ec2 delete-subnet --subnet-id $subnet_id 2>/dev/null || echo "⚠️ Could not delete subnet: $subnet_id"
                echo "✅ Subnet deleted: $subnet_id"
            fi
        done
        
        # Delete custom route tables
        for rt_id in $ROUTE_TABLE_IDS; do
            if [ "$rt_id" != "" ] && [ "$rt_id" != "None" ]; then
                aws ec2 delete-route-table --route-table-id $rt_id 2>/dev/null || echo "⚠️ Could not delete route table: $rt_id"
                echo "✅ Route table deleted: $rt_id"
            fi
        done
        
        # Detach and delete internet gateway
        if [ "$IGW_ID" != "None" ] && [ "$IGW_ID" != "" ]; then
            aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID 2>/dev/null || echo "⚠️ IGW already detached"
            aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID 2>/dev/null || echo "⚠️ Could not delete IGW"
            echo "✅ Internet Gateway deleted: $IGW_ID"
        fi
        
        # Wait a bit more before trying to delete VPC
        sleep 10
        
        # Delete VPC
        aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null || echo "⚠️ Could not delete VPC (may have dependencies)"
        echo "✅ VPC deleted: $VPC_ID"
    else
        echo "ℹ️  VPC is default VPC - not deleting: $VPC_ID"
    fi
else
    echo "⚠️ No VPC ID found"
fi

# Step 6: Delete IAM resources
if [ ! -z "$IAM_ROLE" ]; then
    echo "🔐 Step 6: Deleting IAM role and policies..."
    
    # Remove role from instance profile
    aws iam remove-role-from-instance-profile \
        --instance-profile-name $IAM_ROLE \
        --role-name $IAM_ROLE 2>/dev/null || echo "⚠️ Role already removed from instance profile"
    
    # Delete instance profile
    aws iam delete-instance-profile --instance-profile-name $IAM_ROLE 2>/dev/null || echo "⚠️ Instance profile not found"
    
    # Delete inline policy
    aws iam delete-role-policy \
        --role-name $IAM_ROLE \
        --policy-name S3AccessPolicy 2>/dev/null || echo "⚠️ Inline policy not found"
    
    # Delete IAM role
    aws iam delete-role --role-name $IAM_ROLE 2>/dev/null || echo "⚠️ IAM role not found"
    
    echo "✅ IAM resources deleted"
else
    echo "⚠️ No IAM role found"
fi

# Step 7: Clean up local files
echo "🧽 Step 7: Cleaning up local files..."
if [ -f "$DEPLOYMENT_FILE" ]; then
    # Create backup before deleting
    cp $DEPLOYMENT_FILE "${DEPLOYMENT_FILE}.backup.$(date +%s)"
    rm $DEPLOYMENT_FILE
    echo "✅ Deployment info file deleted (backup created)"
fi

echo ""
echo "🎉 Cleanup completed successfully!"
echo "💰 All AWS resources have been terminated to avoid charges."
echo ""
echo "📋 Summary:"
echo "   ✅ EC2 instance terminated"
echo "   ✅ RDS database deleted"
echo "   ✅ S3 bucket emptied and deleted"
echo "   ✅ Security groups deleted"
echo "   ✅ VPC infrastructure cleaned up (if custom)"
echo "   ✅ IAM role and policies removed"
echo "   ✅ Local deployment files cleaned"
echo ""
echo "💡 You can now run ./deploy.sh again to create a fresh deployment."
echo "🔍 If any resources couldn't be deleted, please check the AWS console manually."
