#!/usr/bin/env python3
"""Check portable documentation links and reject private artifacts."""
from pathlib import Path
import re, sys
root = Path(__file__).resolve().parents[1]
errors = []
files = [p for p in root.rglob('*') if p.is_file() and not any(x == '.git' or x == 'build' or x.startswith('build_') or x == '__pycache__' for x in p.relative_to(root).parts)]
for p in files:
    rel = p.relative_to(root)
    if p.name in {'.git_auth', '.remote_auth'} or p.suffix in {'.o', '.a', '.so', '.dylib', '.log'}:
        errors.append(f'Excluded artifact: {rel}')
    try:
        text = p.read_text()
    except UnicodeDecodeError:
        if p.suffix.lower() in {'.png', '.jpg', '.jpeg', '.svg'}:
            continue
        errors.append(f'Unexpected binary: {rel}')
        continue
    if re.search(r'gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{25,}|-----BEGIN [A-Z ]*PRIVATE KEY-----', text):
        errors.append(f'Credential pattern: {rel}')
    if p.suffix == '.md':
        for target in re.findall(r'\]\(([^)]+)\)', text):
            target = target.strip('<>').split('#')[0]
            if not target or target.startswith(('https://', 'http://', 'mailto:')):
                continue
            if target.startswith('/') or not (p.parent / target).exists():
                errors.append(f'Broken local link: {rel}: {target}')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print(f'PASS: {len(files)} public text files; local Markdown links and excluded-artifact checks')
