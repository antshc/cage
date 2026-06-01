ALLOWED_PATTERNS = [
    # Allow a specific resource group (and all resources within it)
    r"management\.azure\.com/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>(/.*)?$",

    # Examples — uncomment and adjust as needed:

    # Allow all operations under a specific subscription
    # r"management\.azure\.com/subscriptions/a904e129-6f54-4bb7-9cc5-dd27ad5e296a(/.*)?$",

    # Allow a specific storage account (management plane)
    # r"management\.azure\.com/.*/Microsoft\.Storage/storageAccounts/mystorageaccount(/.*)?$",

    # Allow a specific storage account (data plane)
    # r"mystorageaccount\.blob\.core\.windows\.net(/.*)?$",

    # Allow a specific managed identity
    # r"management\.azure\.com/.*/Microsoft\.ManagedIdentity/userAssignedIdentities/my-identity(/.*)?$",

    # Allow a specific key vault (data plane)
    # r"myvault\.vault\.azure\.net(/.*)?$",
]
