#!/usr/bin/env python3
"""Construye el BAT autosuficiente con un ZIP y su comprobación SHA256."""
import base64
import hashlib
import sys
from pathlib import Path


def build_installer(zip_path: Path, output: Path, root: Path) -> None:
    payload = zip_path.read_bytes()
    header = (root / 'installer-header.bat').read_bytes()
    source = (root / 'install.ps1').read_bytes()
    metadata = f'\r\n#PAYLOAD_ZIP#\r\n{hashlib.sha256(payload).hexdigest()}\r\n'
    output.write_bytes(header + source + metadata.encode('ascii') + base64.b64encode(payload) + b'\r\n')


if __name__ == '__main__':
    build_installer(Path(sys.argv[1]), Path(sys.argv[2]), Path(__file__).resolve().parents[1])
