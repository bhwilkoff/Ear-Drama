"""Serves the worktree at / and the scratch lab at /lab/; POST /result writes the harness's JSON.
usage: python -I lab_server.py <worktree> <lab dir> <result file> <port>"""
import http.server, os, sys, functools
root, lab, result, port = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
class H(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        p = path.split('?', 1)[0]
        if p.startswith('/lab/'):
            return os.path.join(lab, p[5:])
        return os.path.join(root, p.lstrip('/'))
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        open(result, 'wb').write(self.rfile.read(n))
        self.send_response(204)
        self.end_headers()
    def log_message(self, *a):
        pass
http.server.ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
