# PKI (Public Key Infrastructure) endpoints required for TLS certificate validation.
# Includes OCSP responders (real-time revocation checks), CRL distribution points
# (downloadable revocation lists), and legacy Symantec/Broadcom CA endpoints.
ENVIRONMENT = {
    "hosts": {
        "ocsp.digicert.com",
        "crl3.digicert.com",
        "crl4.digicert.com",
        "s.symcb.com",
        "ts-crl.ws.symantec.com",
        "www.microsoft.com",
    },
    "wildcards": {
        "*.digicert.com",
    },
}
