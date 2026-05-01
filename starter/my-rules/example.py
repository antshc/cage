# Hosts allowed by default (built into the container image):
#
#   copilot.py  — api.github.com, api.githubcopilot.com,
#                 api.business.githubcopilot.com, copilot-proxy.githubusercontent.com,
#                 telemetry.business.githubcopilot.com, default.exp-tas.com
#   github.py   — github.com, api.github.com,
#                 objects.githubusercontent.com, raw.githubusercontent.com
#   npm.py      — registry.npmjs.org
#   nuget.py    — api.nuget.org, www.nuget.org
#
# Add your custom firewall rules here to extend the container's built-in defaults.
#
# Mount this directory in docker-compose.yml:
#   volumes:
#     - ./my-rules:/etc/mitmproxy/user-rules:ro
#
# Each .py file in the mounted directory is loaded automatically at startup.
# Files are processed in alphabetical order.
#
# Required: export an ENVIRONMENT dict with a "hosts" set.
# Optional: define a check_request(flow) function for per-request validation.
#
# Example:
#
# from mitmproxy import http
#
# ENVIRONMENT = {
#     "hosts": {
#         "registry.example.com",
#         "auth.example.com",
#     }
# }
#
# def check_request(flow: http.HTTPFlow) -> None:
#     # Block requests that don't carry an expected header.
#     if not flow.request.headers.get("Authorization"):
#         flow.response = http.Response.make(
#             403,
#             b"Missing Authorization header",
#             {"Content-Type": "text/plain"},
#         )
