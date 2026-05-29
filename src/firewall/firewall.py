import importlib.util
import logging
import os
from datetime import datetime, timezone

from mitmproxy import ctx, http
from pythonjsonlogger.json import JsonFormatter


# --- ECS JSON logger setup ---

class _EcsJsonFormatter(JsonFormatter):
    """Rename stdlib fields to ECS names: levelname→level, name→logger."""

    def formatTime(self, record: logging.LogRecord, datefmt: str | None = None) -> str:
        ct = datetime.fromtimestamp(record.created, tz=timezone.utc)
        if datefmt:
            return ct.strftime(datefmt)
        return ct.isoformat()

    def add_fields(self, log_record: dict, record: logging.LogRecord, message_dict: dict) -> None:
        super().add_fields(log_record, record, message_dict)
        log_record["level"] = log_record.pop("levelname", record.levelname)
        log_record["logger"] = log_record.pop("name", record.name)


def _setup_json_logger() -> logging.Logger:
    log_dir = "/var/log/mitmproxy"
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, f"events_{datetime.now(timezone.utc).strftime('%Y%m%d')}.json")
    logger = logging.getLogger("mitmproxy.firewall")
    logger.setLevel(logging.DEBUG)
    logger.propagate = False
    handler = logging.FileHandler(log_path, encoding="utf-8")
    handler.setFormatter(_EcsJsonFormatter(
        fmt="%(asctime)s %(levelname)s %(message)s",
        rename_fields={"asctime": "@timestamp"},
        datefmt="%Y-%m-%dT%H:%M:%S.%fZ",
    ))
    logger.addHandler(handler)
    return logger


_json_logger = _setup_json_logger()


ALLOWED_HOSTS: set[str] = set()
ALLOWED_WILDCARDS: list[str] = []  # suffixes like ".digicert.com" from "*.digicert.com"
HOST_HANDLERS: dict[str, callable] = {}


def _load_rules_from_dir(rules_dir: str) -> None:
    """Load ENVIRONMENT and optional check_request from every .py file in rules_dir."""
    if not os.path.isdir(rules_dir):
        return
    for fname in sorted(os.listdir(rules_dir)):
        if not fname.endswith(".py"):
            continue
        fpath = os.path.join(rules_dir, fname)
        spec = importlib.util.spec_from_file_location(fname[:-3], fpath)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        env = getattr(module, "ENVIRONMENT", {})
        hosts = env.get("hosts", set())
        ALLOWED_HOSTS.update(hosts)
        for pattern in env.get("wildcards", set()):
            if pattern.startswith("*."):
                ALLOWED_WILDCARDS.append(pattern[1:])  # store as ".digicert.com"
        if hasattr(module, "check_request"):
            for host in hosts:
                HOST_HANDLERS[host] = module.check_request


# --- Built-in rules: every .py file present in rules/ is active ---

_BUILTIN_RULES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rules")
_load_rules_from_dir(_BUILTIN_RULES_DIR)

# --- User-supplied extension rules (active when mounted) ---

_load_rules_from_dir("/etc/mitmproxy/user-rules")


# --- mitmproxy lifecycle hook ---

def running() -> None:
    _json_logger.info("proxy started", extra={"event": {"action": "startup"}})


# --- Main request handler ---

def request(flow: http.HTTPFlow) -> None:
    host = flow.request.pretty_host.lower()

    if host not in ALLOWED_HOSTS and not any(host.endswith(w) for w in ALLOWED_WILDCARDS):
        ctx.log.warn(f"[BLOCKED] {flow.request.method} {flow.request.pretty_url}")
        _json_logger.warning(
            f"[BLOCKED] {flow.request.method} {flow.request.pretty_url}",
            extra={
                "event": {"action": "blocked"},
                "http": {"request": {"method": flow.request.method}},
                "url": {"full": flow.request.pretty_url, "domain": host},
            },
        )
        body = (
            f"[Sandbox Firewall] Access to '{host}' is blocked.\n"
            f"This is not a rejection from the remote site — the sandbox proxy blocked the request.\n"
            f"To allow this host, add it to a rule file in my-rules/ and mount the directory:\n"
            f"  -v ./my-rules:/etc/mitmproxy/user-rules:ro\n"
            f"See my-rules/example.py for the format."
        )
        flow.response = http.Response.make(
            403,
            body.encode(),
            {"Content-Type": "text/plain"},
        )
        return

    ctx.log.info(f"[ALLOWED] {flow.request.method} {flow.request.pretty_url}")
    _json_logger.info(
        f"[ALLOWED] {flow.request.method} {flow.request.pretty_url}",
        extra={
            "event": {"action": "allowed"},
            "http": {"request": {"method": flow.request.method}},
            "url": {"full": flow.request.pretty_url, "domain": host},
        },
    )

    handler = HOST_HANDLERS.get(host)
    if handler:
        handler(flow)
        if flow.response:
            ctx.log.warn(f"[BLOCKED] {flow.request.method} {flow.request.pretty_url}")
            _json_logger.warning(
                f"[BLOCKED] {flow.request.method} {flow.request.pretty_url}",
                extra={
                    "event": {"action": "blocked-by-handler"},
                    "http": {"request": {"method": flow.request.method}},
                    "url": {"full": flow.request.pretty_url, "domain": host},
                },
            )


def response(flow: http.HTTPFlow) -> None:
    host = flow.request.pretty_host.lower()
    if flow.response and host in ALLOWED_HOSTS or any(host.endswith(w) for w in ALLOWED_WILDCARDS):
        ctx.log.info(
            f"[RESPONSE] {flow.request.method} {flow.request.pretty_url}"
            f" << {flow.response.status_code} {flow.response.reason}"
        )
        _json_logger.info(
            f"[RESPONSE] {flow.request.method} {flow.request.pretty_url}"
            f" << {flow.response.status_code} {flow.response.reason}",
            extra={
                "event": {"action": "response"},
                "http": {
                    "request": {"method": flow.request.method},
                    "response": {
                        "status_code": flow.response.status_code,
                        "reason": flow.response.reason,
                    },
                },
                "url": {"full": flow.request.pretty_url, "domain": host},
            },
        )


def error(flow: http.HTTPFlow) -> None:
    msg = flow.error.msg if flow.error else "unknown error"
    if flow.request:
        method = flow.request.method
        url = flow.request.pretty_url
        host = flow.request.pretty_host.lower()
    else:
        method = "CONNECT"
        url = ""
        host = ""
    ctx.log.warn(f"[ERROR] {msg}")
    _json_logger.error(
        f"[ERROR] {msg}",
        extra={
            "event": {"action": "error"},
            "error": {"message": msg},
            "http": {"request": {"method": method}},
            "url": {"full": url, "domain": host},
        },
    )