#!/bin/bash
set -e

main() {
    echo "=== Script Started ==="
    
    az account list --output table

    subscriptions=$(az account list --query '[].id' -o tsv)

    for sub in $subscriptions; do
        az account set --subscription "$sub"
        
        echo -e "\n========================================="
        echo "SUBSCRIPTION DETAILS:"
        az account show --query '[name, id, tenantId]' -o tsv | awk '{print "Name: " $1 "\nID: " $2 "\nTenant ID: " $3}'
        echo "========================================="

        echo -e "\nResources:"
        az resource list --output table
    done
    
    echo -e "\n=== Script Completed Successfully ==="
    exit 0
}

main