#!/usr/bin/env python3
"""Salud del catálogo: huellas de WinGet desfasadas y URLs muertas.

Para cada app `winget` de apps.json busca en microsoft/winget-pkgs el manifiesto de la última versión,
descarga cada instalador (en streaming, con tope de tamaño) y compara su SHA-256 con `InstallerSha256`.
Una huella distinta es justo lo que en un PC real produce el error 0x8A150011 («la huella no coincide»).
Además comprueba las URLs propias del catálogo (`page`, `url`, `fallback.url`, `postInstall.link`).

Sale con 1 si hay errores (huella desfasada o URL con 404/410/DNS). Los avisos (403, 429, 5xx, tiempos de
espera, instaladores demasiado grandes) se listan pero no hacen fallar el trabajo. Solo lee; no instala nada.
"""
import argparse, concurrent.futures as cf, hashlib, json, os, re, sys, urllib.error, urllib.request

UA = {"User-Agent": "iWinInstaller-catalog-health"}
RAW = "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests"
API = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests"
MAX_BYTES = int(os.environ.get("MAX_INSTALLER_MB", "400")) * 1024 * 1024


def manifest_dir(winget_id):
    parts = winget_id.split(".")
    return "/".join([winget_id[0].lower()] + parts)


def version_key(name):
    # Orden tolerante: 1.10.2 > 1.9; las versiones con letras (rc, beta) quedan por debajo de la numérica igual
    core = re.split(r"[-+_ ]|(?<=\d)[A-Za-z]", name)[0]
    nums = [int(n) for n in re.findall(r"\d+", core)]
    return (nums, 0 if re.search(r"[A-Za-z]", name) else 1)


def http(url, headers=None, method="GET", timeout=45):
    req = urllib.request.Request(url, headers={**UA, **(headers or {})}, method=method)
    return urllib.request.urlopen(req, timeout=timeout)


def api_headers():
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    h = {"Accept": "application/vnd.github+json"}
    if token:
        h["Authorization"] = f"Bearer {token}"
    return h


def latest_version(winget_id):
    with http(f"{API}/{manifest_dir(winget_id)}", api_headers()) as r:
        entries = json.load(r)
    versions = [e["name"] for e in entries if e["type"] == "dir"]
    if not versions:
        raise LookupError("sin versiones en winget-pkgs")
    # La carpeta debe contener el manifiesto de instalador (no una subcarpeta de otro paquete anidado)
    for v in sorted(versions, key=version_key, reverse=True):
        return v
    raise LookupError("sin versiones")


def parse_installers(text):
    """Lee InstallerUrl/InstallerSha256 del YAML sin depender de PyYAML (el formato de winget-pkgs es plano)."""
    installers, current = [], None
    for line in text.splitlines():
        m = re.match(r"^\s*-\s+Architecture:\s*(\S+)", line)
        if m:
            current = {"arch": m.group(1)}
            installers.append(current)
            continue
        if current is None:
            continue
        m = re.match(r"^\s+InstallerUrl:\s*(\S+)", line)
        if m:
            current["url"] = m.group(1).strip("'\"")
        m = re.match(r"^\s+InstallerSha256:\s*([0-9A-Fa-f]{64})", line)
        if m:
            current["sha"] = m.group(1).lower()
    return [i for i in installers if i.get("url", "").startswith("http") and i.get("sha")]


def sha256_of(url):
    h, size = hashlib.sha256(), 0
    with http(url, timeout=60) as r:
        declared = int(r.headers.get("Content-Length") or 0)
        if declared > MAX_BYTES:
            return None, declared
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            size += len(chunk)
            if size > MAX_BYTES:
                return None, size
            h.update(chunk)
    return h.hexdigest(), size


def classify_http(error):
    if isinstance(error, urllib.error.HTTPError):
        return ("error" if error.code in (404, 410) else "aviso"), f"HTTP {error.code}"
    if isinstance(error, urllib.error.URLError):
        reason = str(error.reason)
        return ("error" if re.search(r"Name or service not known|nodename nor servname|getaddrinfo", reason) else "aviso"), reason
    return "aviso", f"{type(error).__name__}: {error}"


def check_winget(app):
    winget_id = app["winget"]
    try:
        version = latest_version(winget_id)
        base = f"{RAW}/{manifest_dir(winget_id)}/{version}/{winget_id}.installer.yaml"
        with http(base) as r:
            installers = parse_installers(r.read().decode("utf-8", "replace"))
    except Exception as e:  # sin manifiesto no se puede comparar: aviso, no error
        return [("aviso", app["id"], f"manifiesto de WinGet no disponible ({winget_id}): {e}")]
    if not installers:
        return [("aviso", app["id"], f"el manifiesto de {winget_id} {version} no tiene instaladores comprobables")]
    findings, seen = [], set()
    for inst in installers:
        if inst["url"] in seen:
            continue
        seen.add(inst["url"])
        try:
            digest, size = sha256_of(inst["url"])
        except Exception as e:
            level, why = classify_http(e)
            findings.append((level, app["id"], f"{winget_id} {version}: no se pudo descargar {inst['url']} ({why})"))
            continue
        if digest is None:
            findings.append(("aviso", app["id"], f"{winget_id} {version}: instalador de {size // 1048576} MB omitido (tope {MAX_BYTES // 1048576} MB)"))
        elif digest != inst["sha"]:
            findings.append(("error", app["id"], f"HUELLA DESFASADA {winget_id} {version}: el manifiesto dice {inst['sha'][:12]}…, el archivo {digest[:12]}… ({inst['url']})"))
    return findings


def catalog_urls(app):
    urls = [(k, app[k]) for k in ("page", "url") if isinstance(app.get(k), str) and app[k].startswith("http")]
    fb = app.get("fallback")
    if isinstance(fb, dict) and str(fb.get("url", "")).startswith("http"):
        urls.append(("fallback.url", fb["url"]))
    post = app.get("postInstall")
    if isinstance(post, dict) and str(post.get("link", "")).startswith("http"):
        urls.append(("postInstall.link", post["link"]))
    return urls


def check_url(app_id, field, url):
    last = None
    for method in ("HEAD", "GET"):
        try:
            with http(url, method=method, timeout=30) as r:
                if r.status < 400:
                    return []
        except Exception as e:
            last = e
            if isinstance(e, urllib.error.HTTPError) and e.code in (404, 410) and method == "GET":
                break
    level, why = classify_http(last) if last else ("aviso", "respuesta inesperada")
    return [(level, app_id, f"URL de «{field}» no responde: {url} ({why})")]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--catalog", default="apps.json")
    ap.add_argument("--solo", default="", help="ids de apps.json separados por espacios (vacío = todas)")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    apps = json.load(open(args.catalog, encoding="utf-8"))
    solo = set(args.solo.split())
    apps = [a for a in apps if not solo or a["id"] in solo]
    jobs = []
    with cf.ThreadPoolExecutor(args.workers) as pool:
        for a in apps:
            if a.get("type") == "winget" and a.get("source", "winget") == "winget" and isinstance(a.get("winget"), str):
                jobs.append(pool.submit(check_winget, a))
            for field, url in catalog_urls(a):
                jobs.append(pool.submit(check_url, a["id"], field, url))
        findings = [f for j in jobs for f in j.result()]

    errors = sorted(f for f in findings if f[0] == "error")
    warnings = sorted(f for f in findings if f[0] == "aviso")
    lines = [f"## Salud del catálogo · {len(apps)} apps revisadas", "", f"**{len(errors)} errores · {len(warnings)} avisos**", ""]
    for title, rows in (("Errores (huellas desfasadas y URLs muertas)", errors), ("Avisos (no hacen fallar el trabajo)", warnings)):
        if rows:
            lines += [f"### {title}", ""] + [f"- `{app_id}`: {text}" for _, app_id, text in rows] + [""]
    report = "\n".join(lines)
    print(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8").write(report + "\n")
    if args.out:
        json.dump({"checked": len(apps), "errors": errors, "warnings": warnings}, open(args.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
