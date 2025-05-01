import csv
from collections import defaultdict
from statistics import mean, median
import matplotlib.pyplot as plt

# file paths and excluded block hashes
input_csv, output_csv, metrics_txt = (
    "../logs/block_profiler.csv",
    "block_profiler_analyzed.csv",
    "block_profiler_metrics.txt",
)
excluded_blocks = {}

# read and group events by block hash
events_by_block = defaultdict(list)
with open(input_csv) as f:
    for timestamp, block_hash, event in csv.reader(f):
        events_by_block[block_hash].append((int(timestamp), event))

# prepare data containers
announcement_latencies = []
header_validations     = []
contained_validations  = []
preprocessing_times    = []
broadcast_times        = []
processing_times       = []
total_times            = []

sync_blocks_count      = 0
async_blocks_count     = 0
announcement_count     = 0
broadcasted_count      = 0
processed_count        = 0

output_records = []

# process each block's events
for block_hash, events_list in events_by_block.items():
    events_list.sort()
    # find all announcement timestamps
    announcements = [t for t, e in events_list if e == "ANOUNCEMENT"]
    if not announcements:
        continue
    first_announcement = min(announcements)
    announcement_count += len(announcements)

    # init timestamps and flags
    proc_start = header_time = contained_time = pre_start = pre_end = None
    broadcast_time = proc_end = None
    proc_sync = proc_async = False

    for t, e in events_list:
        if e == "PROCESSING_START":
            proc_start = proc_start or t
        elif e == "VALIDATION_BLOCK_HEADER":
            header_time = header_time or t
        elif e == "VALIDATION_BLOCK_CONTAINED":
            contained_time = contained_time or t
        elif e == "VALIDATION_PREPROCESS_START":
            pre_start = pre_start or t
        elif e == "VALIDATION_PREPROCESS_END":
            pre_end = pre_end or t
        elif e == "BROADCASTED":
            broadcast_time = broadcast_time or t
        elif e == "PROCESSING_SYNC":
            proc_sync = True
        elif e == "PROCESSING_ASYNC":
            proc_async = True
        elif e == "PROCESSING_END":
            proc_end = proc_end or t

    # compute partial latencies
    if proc_start:
        announcement_latencies.append(proc_start - first_announcement)
    if header_time and contained_time:
        header_validations.append(contained_time - header_time)
    if contained_time and pre_start:
        contained_validations.append(pre_start - contained_time)
    if pre_start and pre_end:
        preprocessing_times.append(pre_end - pre_start)

    # compute full durations if broadcast and end present
    if broadcast_time is not None and proc_end is not None:
        bt = (broadcast_time - proc_start) if proc_start else (broadcast_time - first_announcement)
        pt = proc_end - broadcast_time
        tot = proc_end - first_announcement

        broadcast_times.append(bt)
        processing_times.append(pt)
        total_times.append(tot)

        sync_blocks_count  += proc_sync
        async_blocks_count += proc_async
        broadcasted_count   += 1
        processed_count     += 1

        output_records.append([
            block_hash,
            announcement_latencies[-1] if proc_start else None,
            header_validations[-1]   if header_time and contained_time else None,
            contained_validations[-1] if contained_time and pre_start else None,
            preprocessing_times[-1]   if pre_start and pre_end else None,
            bt,
            pt,
            tot
        ])

# PRINT ANALYSIS

def fmt_stat(name, data):
    return f"{name}: avg={mean(data):.2f}ms, med={median(data):.2f}ms" if data else f"{name}: No data"

metrics = [
    fmt_stat("Announcement Latency", announcement_latencies),
    fmt_stat("Broadcast Time", broadcast_times),
    fmt_stat("Complete Processing Time", processing_times),
    "\n--------------\n",
    fmt_stat("Lifecycle Time", total_times),
    "\n--------------\n",
    fmt_stat("Header Validation", header_validations),
    fmt_stat("Block-in-queue Validation", contained_validations),
    fmt_stat("Preprocessing", preprocessing_times),
    "\n--------------\n",
    f"Synchronous blocks: {sync_blocks_count}",
    f"Asynchronous blocks: {async_blocks_count}",
    "\n--------------\n",
    f"Total Announcements: {announcement_count}",
    f"Blocks Broadcasted: {broadcasted_count}",
    f"Blocks Fully Processed: {processed_count}",
]

print("\n".join(metrics))

# WRITE TO CSV

with open(output_csv, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow([
        "Block",
        "AnnouncementLatency",
        "HeaderValidation",
        "ContainedValidation",
        "Preprocessing",
        "BroadcastTime",
        "ProcessingTime",
        "TotalConsumedTime"
    ])
    writer.writerows(output_records)

with open(metrics_txt, "w") as f:
    f.write("\n".join(metrics))

# PLOTS

# plot cumulative timeline per block
indices = list(range(min(len(total_times), 1000)))
ann_cumulative = [announcement_latencies[i] for i in indices]
bcast_cumulative = [announcement_latencies[i] + broadcast_times[i] for i in indices]
total_cumulative = [total_times[i] for i in indices]

plt.figure(figsize=(12, 7))

for series, label in zip(
    (ann_cumulative, bcast_cumulative, total_cumulative),
    ("Announcement", "Broadcasting", "Complete Processing")
):
    plt.scatter(indices, series, label=f"{label}")

plt.xticks([]);
plt.xlabel("Index")
plt.ylabel("Time (ms)")
plt.title("Lifecycle per Block")
plt.legend()
plt.grid(axis="y")
plt.tight_layout()
plt.show()

# stacked bar: average vs median
avg_vals = [mean(announcement_latencies), mean(broadcast_times), mean(processing_times)]
med_vals = [median(announcement_latencies), median(broadcast_times), median(processing_times)]
colors = ["tab:blue", "tab:orange", "tab:green"]
x_positions = [0, 1]
width = 0.5

plt.figure(figsize=(8, 6))

# average bar
bottom = 0
for val, col in zip(avg_vals, colors):
    plt.bar(x_positions[0], val, width, bottom=bottom, color=col)
    bottom += val

# median bar
bottom = 0
for val, col in zip(med_vals, colors):
    plt.bar(x_positions[1], val, width, bottom=bottom, color=col)
    bottom += val

plt.xticks(x_positions, ["Average", "Median"])
plt.ylabel("Time (ms)")
plt.title("Average & Median Block Lifecycle")
plt.legend(["Announcement", "Broadcasting", "Complete Processing"], loc="upper left")
plt.grid(axis="y")
plt.tight_layout()
plt.show()

