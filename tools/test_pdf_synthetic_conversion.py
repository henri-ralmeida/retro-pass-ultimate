#!/usr/bin/env python3
"""Diagnostic ONLY: converts PDFs generated in this script, never user inputs.
This is NOT the app backend, is NOT sandboxed, and never enables capability.
Requires externally supplied Poppler, ReportLab and Pillow; installs nothing.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.pdfencrypt import StandardEncryption
from PIL import Image, ImageChops

OPTIONS = dict(dpi=144, max_edge=4096, max_pages=64,
               max_page_bytes=8 * 1024 * 1024, max_total_bytes=128 * 1024 * 1024)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(argv, timeout=20):
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                          stdin=subprocess.DEVNULL, check=False)

def fixture(root):
    info = shutil.which('pdfinfo')
    render = shutil.which('pdftoppm')
    if not info or not render:
        raise SystemExit('DIAGNOSTIC UNAVAILABLE: Poppler not installed; production remains disabled')
    version_result = run([render, '-v'])
    version = version_result.stderr.splitlines()[0].removeprefix('pdftoppm version ')
    assert version_result.returncode == 0 and version != version_result.stderr.splitlines()[0]
    source = root / 'synthetic.pdf'
    c = canvas.Canvas(str(source), pagesize=(360, 504), invariant=1)
    c.setFillColorRGB(.04,.12,.23); c.rect(0,0,360,504,stroke=0,fill=1)
    c.setFillColorRGB(.15,.85,1); c.setFont('Helvetica-Bold',20)
    c.drawString(28,440,'SYNTHETIC PDF MANUAL')
    c.setFont('Helvetica',13); c.drawString(28,408,'REAL PDF → PNG CONVERSION')
    c.drawString(28,380,'Internal QA only / no personal media')
    c.drawString(28,78,'1 / 3   Portrait'); c.showPage()
    c.showPage()  # Deliberately blank page: MUST NOT be omitted.
    c.setPageSize((504,360)); c.setFillColorRGB(.06,.23,.27)
    c.rect(0,0,504,360,stroke=0,fill=1); c.setFillColorRGB(1,1,1)
    c.setFont('Helvetica-Bold',18); c.drawString(24,300,'3 / 3   LANDSCAPE - SYNTHETIC')
    c.setFont('Helvetica',14); c.drawString(24,262,'Page 2 is intentionally blank.')
    c.drawString(24,232,'Arbitrary PDF conversion is NOT enabled.')
    c.showPage(); c.save()
    source_hash = sha(source)
    metadata = run([info, str(source)])
    assert metadata.returncode == 0 and 'Pages:           3' in metadata.stdout
    pages = []
    for number in range(1,4):
        prefix = root / f'page-{number:04d}'
        result = run([render,'-f',str(number),'-l',str(number),'-singlefile',
                      '-r','144','-png',str(source),str(prefix)], timeout=30)
        assert result.returncode == 0, result.stderr
        path = prefix.with_suffix('.png')
        with Image.open(path) as image:
            image.load(); width,height = image.size
            assert 0 < width <= 4096 and 0 < height <= 4096
            assert path.stat().st_size <= OPTIONS['max_page_bytes']
            blank = ImageChops.difference(image.convert('RGB'),Image.new('RGB',image.size,'white')).getbbox() is None
            assert blank == (number == 2)
            assert (width > height) == (number == 3)
        pages.append(dict(number=number,file=path.name,sha256=sha(path),
                          bytes=path.stat().st_size,width=width,height=height))
    assert sha(source) == source_hash
    key_payload = [source_hash,'poppler-diagnostic',version,OPTIONS]
    key = hashlib.sha256(json.dumps(key_payload,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    manifest = dict(version=1,complete=True,source_sha256=source_hash,
                    backend=dict(id='poppler-diagnostic',version=version),
                    options=OPTIONS,cache_key=key,page_count=3,pages=pages)
    # Only this diagnostic directory receives the manifest. Not app/cache publication.
    (root/'manifest.json').write_text(json.dumps(manifest,indent=2))
    encrypted = root/'encrypted.pdf'
    c = canvas.Canvas(str(encrypted),encrypt=StandardEncryption('qa-only-password'),invariant=1)
    c.drawString(30,400,'Synthetic encrypted test'); c.showPage(); c.save()
    bad = root/'invalid.pdf'; bad.write_bytes(b'%PDF-1.7\nsynthetic invalid structure\n')
    wrong = root/'wrong-header.pdf'; wrong.write_bytes(b'not a PDF - synthetic only')
    negatives = {}
    for path in [encrypted,bad,wrong]:
        check = run([info,str(path)])
        assert check.returncode != 0
        negatives[path.name] = check.returncode
    result = dict(status='synthetic_conversion_pass',production_backend_available=False,
                  containment_verified=False,backend_version=version,pages=3,
                  blank_preserved=True,landscape_preserved=True,source_unchanged=True,
                  generated_negatives=negatives,
                  not_tested=['arbitrary PDFs','safe production backend','disk full rollback',
                              'production timeout/cancel','production atomic PDF publication'])
    (root/'diagnostic.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(dict(output=str(root),**result),indent=2))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',help='New, nonexistent diagnostic directory; never a source PDF')
    args = parser.parse_args()
    if args.output:
        root = Path(args.output).absolute()
        root.mkdir(parents=False,exist_ok=False)  # Never overwrite existing files.
        fixture(root)
    else:
        with tempfile.TemporaryDirectory(prefix='retropass-pdf-synthetic-') as tmp:
            fixture(Path(tmp))
