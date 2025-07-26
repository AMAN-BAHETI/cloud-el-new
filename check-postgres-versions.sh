#!/bin/bash

# Check Available PostgreSQL Versions in AWS RDS
# This script helps you find what PostgreSQL versions are available in your region

set -e

REGION=${1:-"ap-south-1"}

echo "🔍 Checking available PostgreSQL versions in region: $REGION"
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ AWS CLI not configured. Run 'aws configure' first."
    exit 1
fi

echo "📋 Available PostgreSQL versions for RDS:"
echo "=========================================="

# Get all available PostgreSQL versions
aws rds describe-db-engine-versions \
    --engine postgres \
    --region $REGION \
    --query 'DBEngineVersions[?contains(SupportedEngineModes, `provisioned`)].[EngineVersion,DBEngineDescription]' \
    --output table

echo ""
echo "🎯 Recommended versions for Free Tier:"
echo "======================================"

# Get the latest versions for each major version
echo "PostgreSQL 14 (Latest stable):"
aws rds describe-db-engine-versions \
    --engine postgres \
    --region $REGION \
    --query 'DBEngineVersions[?starts_with(EngineVersion, `14.`) && contains(SupportedEngineModes, `provisioned`)] | [0].EngineVersion' \
    --output text

echo ""
echo "PostgreSQL 15 (Newer):"
aws rds describe-db-engine-versions \
    --engine postgres \
    --region $REGION \
    --query 'DBEngineVersions[?starts_with(EngineVersion, `15.`) && contains(SupportedEngineModes, `provisioned`)] | [0].EngineVersion' \
    --output text

echo ""
echo "PostgreSQL 16 (Latest):"
aws rds describe-db-engine-versions \
    --engine postgres \
    --region $REGION \
    --query 'DBEngineVersions[?starts_with(EngineVersion, `16.`) && contains(SupportedEngineModes, `provisioned`)] | [0].EngineVersion' \
    --output text

echo ""
echo "💡 The deploy script will automatically select an available version."
echo "   You can also manually specify a version by editing the script."

echo ""
echo "🔧 To check versions for a different region:"
echo "   ./check-postgres-versions.sh us-east-1"
