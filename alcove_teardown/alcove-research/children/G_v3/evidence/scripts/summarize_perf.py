import datetime
import json
import pathlib
import re
import statistics
from zoneinfo import ZoneInfo

root = pathlib.Path(__file__).resolve().parent
perf = root / 'ev/perf'
tz = ZoneInfo('America/Los_Angeles')


def stamp(value, fmt):
    return datetime.datetime.strptime(value, fmt).replace(tzinfo=tz).timestamp()


def stats(values):
    if not values:
        return None
    values = sorted(values)
    return dict(n=len(values), mean=statistics.mean(values), median=statistics.median(values),
                min=values[0], max=values[-1], p95=values[min(len(values)-1, int(len(values)*.95))])


def mem(value):
    m = re.match(r'([0-9.]+)([BKMGT])', value)
    return float(m[1]) * 1024**('BKMGT'.index(m[2])-2)


tops = []
t = None
top_text = (perf / 'top_workloads.txt').read_text()
if (perf / 'top_extension.txt').exists():
    top_text += '\n' + (perf / 'top_extension.txt').read_text()
for line in top_text.splitlines():
    if re.match(r'^\d{4}/\d{2}/\d{2} ', line):
        t = stamp(line, '%Y/%m/%d %H:%M:%S')
    if re.match(r'^3840\s+Alcove\s', line):
        x = line.split()
        tops.append(dict(time=t, cpu_percent=float(x[2]), footprint_mib=mem(x[3]),
                         top_power=float(x[4]), threads=int(x[5].split('/')[0]),
                         idlew_counter=int(x[7].rstrip('+-')), csw_counter=int(x[8].rstrip('+-'))))

powers = []
power_text = (perf / 'powermetrics_workloads.txt').read_text()
if (perf / 'powermetrics_extension.txt').exists():
    power_text += '\n' + (perf / 'powermetrics_extension.txt').read_text()
for line in power_text.splitlines():
    m = re.search(r'Sampled system activity \((.+)\) \(([0-9.]+)ms elapsed\)', line)
    if m:
        t = datetime.datetime.strptime(m[1], '%a %b %d %H:%M:%S %Y %z').timestamp()
    if re.match(r'^Alcove\s+3840\s', line):
        x = line.split()
        powers.append(dict(time=t, cpu_ms_per_s=float(x[2]), interrupt_wakeups_per_s=float(x[6]),
                           package_idle_wakeups_per_s=float(x[7]), gpu_ms_per_s=float(x[8]), energy_impact=float(x[9])))

tops = list({x['time']: x for x in tops}.values())
powers = list({x['time']: x for x in powers}.values())
growth = []
for line in (perf / 'growth.jsonl').read_text().splitlines():
    x = json.loads(line)
    p = x.get('ps', '').split()
    if p:
        growth.append(dict(utc=x['utc'], elapsed_s=x['elapsed'], pid=int(p[0]), rss_mib=int(p[1])/1024,
                           ps_lifetime_cpu_percent=float(p[2]), uptime=p[4]))

results = dict(top_samples=len(tops), power_samples=len(powers),
               growth_samples=len(growth), growth_duration_s=growth[-1]['elapsed_s']-growth[0]['elapsed_s'],
               growth_pid_set=sorted(set(x['pid'] for x in growth)),
               growth_rss_mib=stats([x['rss_mib'] for x in growth]),
               growth_first=growth[0], growth_last=growth[-1],
               growth_delta_mib=growth[-1]['rss_mib']-growth[0]['rss_mib'], phases=[])
phase_path = perf / 'phases.json'
if phase_path.exists():
    for phase in json.loads(phase_path.read_text()):
        start = datetime.datetime.fromisoformat(phase['start']).timestamp()
        end = datetime.datetime.fromisoformat(phase['end']).timestamp()
        top = [x for x in tops if start <= x['time'] < end]
        power = [x for x in powers if start <= x['time'] < end]
        row = dict(phase=phase)
        for key in ['cpu_percent', 'footprint_mib', 'top_power', 'threads']:
            row[key] = stats([x[key] for x in top])
        for key in ['cpu_ms_per_s', 'interrupt_wakeups_per_s', 'package_idle_wakeups_per_s', 'gpu_ms_per_s', 'energy_impact']:
            row[key] = stats([x[key] for x in power])
        results['phases'].append(row)

(perf / 'top_parsed.json').write_text(json.dumps(tops, indent=2))
(perf / 'powermetrics_parsed.json').write_text(json.dumps(powers, indent=2))
(perf / 'growth_parsed.json').write_text(json.dumps(growth, indent=2))
(perf / 'summary.json').write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(11, 4))
    ax.plot([x['elapsed_s']/60 for x in growth], [x['rss_mib'] for x in growth], 'o-', markersize=3)
    ax.set(xlabel='Minutes since measurement start', ylabel='RSS (MiB)', title='Alcove PID 3840: mixed-workload resident memory')
    ax.grid(alpha=.3)
    fig.tight_layout()
    fig.savefig(perf / 'growth_rss.png', dpi=140)
    plt.close(fig)
except ImportError:
    pass
