# github.py — Allow all GitHub traffic.
# GitHub domains are excluded from TLS interception via --ignore-hosts in
# 30-proxy.sh so that tools like `gh` see the real certificate.
# No check_request needed — all requests to these hosts are allowed.

ENVIRONMENT = {
    "hosts": {
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "raw.githubusercontent.com",
        "release-assets.githubusercontent.com",
    },
}
