import sys, time
path, n, limit = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
t = time.time()
while time.time() - t < limit:
    txt = open(path).read()
    lines = txt.strip().splitlines()
    if sum('manifest' in l for l in lines) >= n or (len(lines) > 1 and 'load averages' in lines[-1]):
        break
    time.sleep(5)
print(open(path).read())
