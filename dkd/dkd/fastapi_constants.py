import os

LOG_REQUEST = os.environ.get("LOG_REQUEST", "false").lower() == "true"
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8100"))
DKD_BASE_URL = os.environ.get("DKD_BASE_URL", "/dkd")
ALLOW_UNAUTHENTICATED = (
    os.environ.get("ALLOW_UNAUTHENTICATED", "false").lower() == "true"
)
ANONYMOUS_TOKEN = os.environ.get("ANONYMOUS_TOKEN", "put-some-token-here")
