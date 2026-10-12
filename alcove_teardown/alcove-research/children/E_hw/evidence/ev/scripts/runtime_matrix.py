import subprocess,time,json,pathlib,datetime
root=pathlib.Path('/Users/devin/work/ev'); start=time.monotonic(); records=[]
def run(label,args,delay=2,shot=True):
 t=time.monotonic()-start
 try:
  p=subprocess.run(args,capture_output=True,text=True,timeout=12)
  result={'t':round(t,3),'label':label,'command':args,'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
 except subprocess.TimeoutExpired: result={'t':round(t,3),'label':label,'command':args,'timeout':True}
 records.append(result); print(json.dumps(result),flush=True); time.sleep(delay)
 if shot: subprocess.run(['screencapture','-x',str(root/'shots'/f'{label}.png')],timeout=8)
 (root/'logs'/'runtime_matrix.json').write_text(json.dumps(records,indent=2))
ff=subprocess.Popen(['/opt/homebrew/bin/ffmpeg','-y','-loglevel','warning','-f','avfoundation','-framerate','60','-capture_cursor','1','-i','0:none','-c:v','libx264','-preset','ultrafast','-crf','22','-pix_fmt','yuv420p',str(root/'clips'/'hardware_matrix.mp4')],stdin=subprocess.PIPE,stdout=open(root/'logs'/'recording_stdout.txt','w'),stderr=open(root/'logs'/'recording_stderr.txt','w'))
time.sleep(2)
run('brightness_up',[str(root/'scripts/hwkeys'),'2','4'],.25)
run('brightness_down',[str(root/'scripts/hwkeys'),'3','4'],.25)
run('brightness_fine',[str(root/'scripts/hwkeys'),'2','4','a0000'],.25)
run('volume_up',[str(root/'scripts/hwkeys'),'0','2'],.25)
run('mute',[str(root/'scripts/hwkeys'),'7','1'],.25)
run('keyboard_illum_up',[str(root/'scripts/hwkeys'),'21','2'],.25)
run('keyboard_illum_down',[str(root/'scripts/hwkeys'),'22','2'],2)
run('lowpower_on',['sudo','-n','pmset','-a','lowpowermode','1'],2)
run('lowpower_off',['sudo','-n','pmset','-a','lowpowermode','0'],2)
run('lowpower_battery_restore',['sudo','-n','pmset','-b','lowpowermode','0'],0,False)
for label,name in [('synthetic_locked','com.apple.screenIsLocked'),('synthetic_unlocked','com.apple.screenIsUnlocked'),('synthetic_lockui','com.apple.screenLockUIIsShown'),('synthetic_unlockui','com.apple.screenLockUIIsHidden'),('synthetic_screensaver_start','com.apple.screensaver.didstart'),('synthetic_screensaver_stop','com.apple.screensaver.didstop')]:
 run(label,[str(root/'scripts/postnotif'),name],2)
run('screensaver_launch',['open','-a','ScreenSaverEngine'],3)
run('screensaver_escape',['osascript','-e','tell application "System Events" to key code 53'],1)
run('display_sleep',['pmset','displaysleepnow'],1)
run('display_wake',['caffeinate','-u','-t','2'],2)
ff.communicate(b'q\n',timeout=20)
print('Recording done',flush=True)
for label,w,h in [('adjusted_width20',20,0),('adjusted_height10',0,10),('adjusted_restored',0,0)]:
 subprocess.run(['osascript','-e','tell application "Alcove" to quit'])
 subprocess.run(['defaults','write','com.henrikruscon.Alcove','notchAdjustedWidth','-float',str(w)])
 subprocess.run(['defaults','write','com.henrikruscon.Alcove','notchAdjustedHeight','-float',str(h)])
 run(label,['open','-a','Alcove'],3)
