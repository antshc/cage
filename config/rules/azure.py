import re

from mitmproxy import http

ARM_RE = re.compile(
    r"^/subscriptions/([^/]+)/resourceGroups/([^/?#]+)(/.*)?$",
    re.IGNORECASE,
)

ENVIRONMENT = {
    "hosts": {
        "management.azure.com",
        "login.microsoftonline.com",
    },
    "subscriptions": {
        "00000000-0000-0000-0000-000000000000",
    },
    "resource_groups": {
        "rg-dev-sandbox",
        "rg-ci-tests",
    },
}


def check_request(flow: http.HTTPFlow) -> None:
    """Validate Azure ARM requests against allowed subscriptions and resource groups."""
    match = ARM_RE.match(flow.request.path)
    if not match:
        flow.response = http.Response.make(
            403,
            b"Blocked Azure ARM path",
            {"Content-Type": "text/plain"},
        )
        return

    subscription_id = match.group(1).lower()
    resource_group = match.group(2)

    if subscription_id not in ENVIRONMENT["subscriptions"]:
        flow.response = http.Response.make(
            403,
            b"Blocked Azure subscription",
            {"Content-Type": "text/plain"},
        )
        return

    if resource_group not in ENVIRONMENT["resource_groups"]:
        flow.response = http.Response.make(
            403,
            b"Blocked Azure resource group",
            {"Content-Type": "text/plain"},
        )
