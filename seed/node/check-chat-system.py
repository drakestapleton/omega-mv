import http.server, threading, subprocess, json, sys
exe=sys.argv[1]
requests=[]
candidate='fn identity x int to int\nret x\nend\n'
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        requests.append((self.path,body))
        out=json.dumps({'object':'chat.completion','choices':[{'message':{'role':'assistant','content':candidate},'finish_reason':'stop'}],'usage':{'prompt_tokens':31,'completion_tokens':12}}).encode()
        self.send_response(200); self.send_header('Content-Length',str(len(out))); self.end_headers(); self.wfile.write(out)
server=http.server.HTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
port=str(server.server_port)
def run(flag,extra=(),p=port):
    return subprocess.run([exe,flag,p,'128','5','User Ω "quoted"\nline']+list(extra),capture_output=True,timeout=8)
old=run('--chat'); assert old.returncode==0
assert requests[-1][1]['messages']==[{'role':'user','content':'User Ω "quoted"\nline'}]
sysmsg='System Ω "quoted"\nline'
new=run('--chat-system',[sysmsg]); assert new.returncode==0,new.stderr
assert new.stdout==old.stdout
assert requests[-1][1]['messages']==[{'role':'system','content':sysmsg},{'role':'user','content':'User Ω "quoted"\nline'}]
assert 'tools' not in requests[-1][1] and 'ollm_test_output' not in requests[-1][1]
for flag,args in [('--chat-system',[]),('--chat-system',['']),('--chat-system',['x'*3801]),('--chat-system',['ok','extra']),('--chat',['unexpected'])]:
    before=len(requests); z=run(flag,args); assert z.returncode==2,(flag,args[:1],z.returncode); assert len(requests)==before
assert run('--chat-system',['x'],p='18091').returncode==2
assert run('--chat-system',['x'*3800]).returncode==0
server.shutdown()
print('PASS exact explicit roles/Unicode/escaping/raw output/usage parity; no tools or test injection; bounds/arity/protected-port refusal')
