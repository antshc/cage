from mitmproxy import http

# Patched at startup by user-rules/github.py via the firewall loader.
ALLOWED_REPOS: list[str] = []

# api.github.com paths are prefixed with /repos/<org>/<repo>/...
_API_PREFIXES = ["/repos" + r for r in ALLOWED_REPOS] + ["/user", "/graphql", "/"]

_ALLOWED_GITHUB_PATHS = [
    "/login",
    "/session",
]

_FILTERED_HOSTS = {"github.com", "api.github.com"}

ENVIRONMENT = {
    "hosts": {
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "raw.githubusercontent.com",
        "release-assets.githubusercontent.com",
    },
}


def check_request(flow: http.HTTPFlow) -> None:
    host = flow.request.pretty_host.lower()
    if host not in _FILTERED_HOSTS:
        # objects/raw/release-assets hosts: no path restriction
        return
    path = flow.request.path
    if host == "api.github.com":
        prefixes = _API_PREFIXES
    else:
        prefixes = ALLOWED_REPOS + _ALLOWED_GITHUB_PATHS
    if not any(path.startswith(p) for p in prefixes):
        body = (
            "[Sandbox Firewall] Access to '{}{}' is blocked.\n"
            "Only the following repositories are allowed:\n{}"
        ).format(host, path, "\n".join("  github.com" + r for r in ALLOWED_REPOS))
        flow.response = http.Response.make(
            403,
            body.encode(),
            {"Content-Type": "text/plain"},
        )
