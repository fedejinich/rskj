import csv
from collections import defaultdict
from statistics import mean, median
import matplotlib.pyplot as plt

# Input and output
csv_input  = "../logs/block_profiler.csv"
csv_output = "block_profiler_analyzed.csv"

# Blocks to exclude from the plot
EXCLUDED_BLOCK_HASHES = [
    "db58f0a1033b7fba60ff54f92ad1223904aaf3633aa7edbecbca95236e4affa7",
    "5ce8fdaa288be18be7da8c224d4a845b06bab375ad971791ea4f8291d22dbe40",
    "2ef854d61d456e4ba4df6c9501936310e667da38054693ec062ad7a5f2d984d1",
    "6d7e47efc4cdf2f9cda7afede90c730db4f98f97394e45682dd096378329c518",
]

# Read CSV and group by hash
blocks = defaultdict(list)
with open(csv_input, newline="") as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) != 3:
            continue
        instant, block_hash, phase = row
        blocks[block_hash].append((int(instant), phase))

# Sort events by time for each block
for ev in blocks.values():
    ev.sort(key=lambda x: x[0])

# Metric containers
announcement_times            = []
header_to_contained_times     = []
contained_to_preprocess_times = []
preprocessing_times           = []
broadcasting_times            = []
processing_times              = []
total_consumed_times          = []

# Counters
total_announcements = 0
announced_blocks    = 0
broadcasted_blocks  = 0
propagated_blocks   = 0

# For CSV output and detailed metrics
block_infos      = []
detailed_metrics = []

# Process each block
for block_hash, events in blocks.items():
    announcement_instants = []
    processing_start      = None
    v_header              = None
    v_contained           = None
    v_pre_start           = None
    v_pre_end             = None
    broadcasted           = None
    processing_end        = None

    # Classify timestamps
    for t, phase in events:
        if phase == "ANOUNCEMENT":
            announcement_instants.append(t)
        elif phase == "PROCESSING_START":
            processing_start = processing_start or t
        elif phase == "VALIDATION_BLOCK_HEADER":
            v_header = v_header or t
        elif phase == "VALIDATION_BLOCK_CONTAINED":
            v_contained = v_contained or t
        elif phase == "VALIDATION_PREPROCESS_START":
            v_pre_start = v_pre_start or t
        elif phase == "VALIDATION_PREPROCESS_END":
            v_pre_end = v_pre_end or t
        elif phase == "BROADCASTED":
            broadcasted = broadcasted or t
        elif phase == "PROCESSING_END":
            processing_end = processing_end or t

    # Skip if no announcement
    if not announcement_instants:
        continue

    # First announcement timestamp
    first_ann = min(announcement_instants)
    announced_blocks += 1
    total_announcements += len(announcement_instants)

    # Initialize metrics
    ann_lat    = None
    hdr_valid  = None
    cont_val   = None
    preproc    = None
    b_time     = None
    proc_time  = None
    total_time = None

    if processing_start is not None:
        ann_lat = processing_start - first_ann
        announcement_times.append(ann_lat)

    if v_header is not None and v_contained is not None:
        hdr_valid = v_contained - v_header
        header_to_contained_times.append(hdr_valid)

    if v_contained is not None and v_pre_start is not None:
        cont_val = v_pre_start - v_contained
        contained_to_preprocess_times.append(cont_val)

    if v_pre_start is not None and v_pre_end is not None:
        preproc = v_pre_end - v_pre_start
        preprocessing_times.append(preproc)

    # Main deltas
    if broadcasted is not None and processing_end is not None:
        total_time = processing_end - first_ann
        b_time     = (broadcasted - processing_start) if processing_start else (broadcasted - first_ann)
        proc_time  = processing_end - broadcasted
        broadcasting_times.append(b_time)
        processing_times.append(proc_time)
        total_consumed_times.append(total_time)

    if broadcasted is not None:
        broadcasted_blocks += 1
    if None not in (ann_lat, b_time, proc_time):
        propagated_blocks += 1

    # Store for CSV and plots
    block_infos.append({
        "hash"              : block_hash,
        "BroadcastTime"     : b_time,
        "ProcessingTime"    : proc_time,
        "TotalConsumedTime": total_time,
    })
    detailed_metrics.append({
        "hash"                : block_hash,
        "AnnouncementLatency" : ann_lat,
        "HeaderValidation"    : hdr_valid,
        "ContainedValidation" : cont_val,
        "Preprocessing"       : preproc,
        "BroadcastTime"       : b_time,
        "ProcessingTime"      : proc_time,
        "TotalConsumedTime"   : total_time,
    })

# Write final CSV
with open(csv_output, "w", newline="") as out:
    w = csv.writer(out)
    w.writerow([
        "Block",
        "AnnouncementLatency",
        "HeaderValidation",
        "ContainedValidation",
        "Preprocessing",
        "BroadcastTime",
        "ProcessingTime",
        "TotalConsumedTime",
    ])
    for rec in detailed_metrics:
        w.writerow([
            rec["hash"],
            rec["AnnouncementLatency"],
            rec["HeaderValidation"],
            rec["ContainedValidation"],
            rec["Preprocessing"],
            rec["BroadcastTime"],
            rec["ProcessingTime"],
            rec["TotalConsumedTime"],
        ])

# Overall statistics
def stat(name, arr):
    return f"{name}: avg={mean(arr):.2f}ms, med={median(arr):.2f}ms" if arr else f"{name}: No data"

print("\n--- Overall Metrics ---\n")
print(stat("Announcement Latency", announcement_times))
print(stat("Header Validation", header_to_contained_times))
print(stat("Contained Validation", contained_to_preprocess_times))
print(stat("Preprocessing", preprocessing_times))
print(stat("Broadcast Time", broadcasting_times))
print(stat("Processing Time", processing_times))
print("\n-----------------------\n")
print(stat("Total Cumulative Time", total_consumed_times))
print("\n-----------------------\n")
print(f"Total Announcements: {total_announcements}")
print(f"Blocks Announced: {announced_blocks}")
print(f"Blocks Broadcasted: {broadcasted_blocks}")
print(f"Blocks Fully Processed: {propagated_blocks}")
print("\n-----------------------\n")
print(f"Analysis written to {csv_output}\n")

# ————— Plot cumulative timeline by block —————
filtered = [
    rec for rec in detailed_metrics
    if rec["hash"] not in EXCLUDED_BLOCK_HASHES
       and rec["TotalConsumedTime"] is not None
]
filtered = filtered[:1000]

idx   = list(range(len(filtered)))
a_cum = [rec["AnnouncementLatency"]                          for rec in filtered]
b_cum = [rec["AnnouncementLatency"] + rec["BroadcastTime"]     for rec in filtered]
p_cum = [rec["TotalConsumedTime"]                            for rec in filtered]

plt.figure(figsize=(12, 7))
plt.scatter(idx, a_cum, label="Announcement Cumulative")
plt.scatter(idx, b_cum, label="Broadcast Cumulative")
plt.scatter(idx, p_cum, label="Processing Cumulative")
plt.xticks([])  # remove X-axis labels
plt.title("Cumulative Timeline per Block (1000 Blocks)")
plt.xlabel("Block Index")
plt.ylabel("Cumulative Time (ms)")
plt.legend()
plt.grid(True, axis='y')
plt.tight_layout()
plt.show()

# ————— Stacked bar chart: Average vs Median per event —————
avg_ann = mean(announcement_times)
avg_b   = mean(broadcasting_times)
avg_p   = mean(processing_times)

med_ann = median(announcement_times)
med_b   = median(broadcasting_times)
med_p   = median(processing_times)

x = [0, 1]
width = 0.5
colors = ["tab:blue", "tab:orange", "tab:green"]

plt.figure(figsize=(8, 6))

# Average bar
plt.bar(x[0], avg_ann, width, color=colors[0])
plt.bar(x[0], avg_b,   width, bottom=avg_ann,             color=colors[1])
plt.bar(x[0], avg_p,   width, bottom=avg_ann + avg_b,     color=colors[2])

# Median bar
plt.bar(x[1], med_ann, width, color=colors[0])
plt.bar(x[1], med_b,   width, bottom=med_ann,             color=colors[1])
plt.bar(x[1], med_p,   width, bottom=med_ann + med_b,     color=colors[2])

plt.xticks(x, ["Average", "Median"])
plt.ylabel("Time (ms)")
plt.title("Average vs Median per Block Event")
plt.legend(["Announcement", "Broadcast", "Processing"], loc="upper left")
plt.grid(True, axis="y")
plt.tight_layout()
plt.show()

