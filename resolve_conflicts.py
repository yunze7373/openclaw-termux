import subprocess, sys

REPO = 'd:/repos/yunze7373/openclaw-termux'
KEEP_FILES = {'src/agents/bash-tools.exec.ts'}

r = subprocess.run(['git','diff','--name-only','--diff-filter=U'],
    cwd=REPO, capture_output=True, text=True)
files = [f.strip() for f in r.stdout.splitlines() if f.strip()]
print(f'Total remaining conflicts: {len(files)}', flush=True)

to_resolve = [f for f in files if f not in KEEP_FILES]
print(f'Resolving {len(to_resolve)} files with --theirs...', flush=True)

failed = []
for f in to_resolve:
    res = subprocess.run(['git','checkout','--theirs','--',f],
        cwd=REPO, capture_output=True, text=True)
    if res.returncode != 0:
        failed.append((f, res.stderr.strip()))
        print(f'  FAIL: {f}: {res.stderr.strip()[:80]}', flush=True)
    else:
        subprocess.run(['git','add','--',f], cwd=REPO)

print(f'\nFailed count: {len(failed)}', flush=True)

r2 = subprocess.run(['git','diff','--name-only','--diff-filter=U'],
    cwd=REPO, capture_output=True, text=True)
remaining = [f.strip() for f in r2.stdout.splitlines() if f.strip()]
print(f'Remaining conflicts: {len(remaining)}', flush=True)
for f in remaining:
    print(f'  {f}', flush=True)
