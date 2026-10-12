import time,subprocess,pathlib,json,datetime
root=pathlib.Path('/Users/devin/alcove-uncovered/ev/perf');root.mkdir(exist_ok=True)
start=time.monotonic()
with (root/'growth.jsonl').open('w') as out:
    for n in range(42):
        ids=subprocess.run(['pgrep','-f','/Applications/Alcove.app/Contents/MacOS/Alcove'],capture_output=True,text=True).stdout.strip().split()
        row={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'elapsed':time.monotonic()-start,'pids':ids}
        if ids:
            row['ps']=subprocess.run(['ps','-p',','.join(ids),'-o','pid=,rss=,%cpu=,time=,etime='],capture_output=True,text=True).stdout.strip()
            row['top']=subprocess.run(['top','-l','2','-s','1','-pid',ids[0],'-stats','pid,command,cpu,mem,power,threads,time,idlew,csw'],capture_output=True,text=True).stdout
        out.write(json.dumps(row)+'\n');out.flush()
        print(n,row['utc'],row.get('ps','not running'),flush=True)
        if n<41:time.sleep(max(0,start+(n+1)*30-time.monotonic()))
