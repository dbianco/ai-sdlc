# PoC fixture — seeded findings

Deliberately insecure repo for testing Trivy + Semgrep (stand-in for
Opengrep) as the SDLC security gate. Seeds, each of which should surface
in the scan:

| Seed | Where | Tool that should catch it |
|------|-------|--------------------------|
| `urllib3==1.25.3` (CVE-2021-33503, etc.) | `requirements.txt` | Trivy SCA |
| `requests==2.20.0` (CVE-2023-32681 and others) | `requirements.txt` | Trivy SCA |
| `jinja2==2.10` (CVE-2019-10906, etc.) | `requirements.txt` | Trivy SCA |
| AWS access key pattern | `src/app.py` top of file | Trivy secret |
| `eval(user_input)` on a Flask POST body | `src/app.py` `/eval` handler | Semgrep SAST |
| `http.request("GET", request.args["url"])` SSRF | `src/app.py` `/fetch` handler | Semgrep SAST |
| Dockerfile running as root | `Dockerfile` (no `USER` directive) | Trivy misconfig |

Everything else is window dressing to make the fixture look like a real
small Flask service.
