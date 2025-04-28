import csv
from collections import defaultdict
from statistics import mean, median

csv_file = "../logs/block_propagation.csv"

# Group events by block hash
blocks = defaultdict(list)

with open(csv_file, newline="") as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) != 3:
            continue
        instant, block_hash, phase = row
        blocks[block_hash].append((int(instant), phase))

# Sort each block's events by instant
for events in blocks.values():
    events.sort(key=lambda e: e[0])

# Analyze
propagation_times = []
broadcasting_times = []
anounced_blocks = 0
broadcasted_blocks = 0
propagated_blocks = 0

print()

for block_hash, events in blocks.items():
    first_announcement = None
    processing_start = None
    broadcasted = None
    processing_end = None
    announcement_count = 0

    for instant, phase in events:
        if phase == "ANOUNCEMENT":
            announcement_count += 1
            if first_announcement is None:
                first_announcement = instant
        elif phase == "PROCESSING_START" and processing_start is None:
            processing_start = instant
        elif phase == "BROADCASTED" and broadcasted is None:
            broadcasted = instant
        elif phase == "PROCESSING_END" and processing_end is None:
            processing_end = instant

    if first_announcement:
        anounced_blocks += 1
    if first_announcement and broadcasted:
        broadcasted_blocks += 1
    if first_announcement and processing_start and broadcasted and processing_end:
        if first_announcement <= processing_start <= broadcasted <= processing_end:
            propagated_blocks += 1

            propagation_time = processing_end - first_announcement
            broadcasting_time = broadcasted - first_announcement

            propagation_times.append(propagation_time)
            broadcasting_times.append(broadcasting_time)

            print(
                f"Block {block_hash[:8]}: "
                f"Propagation={propagation_time}ms, "
                f"Broadcasting={broadcasting_time}ms, "
                f"Anouncements={announcement_count}"
            )


def print_stats(name, times):
    if times:
        print(f"{name}:")
        print(f"  Average: {mean(times):.2f} ms")
        print(f"  Median: {median(times):.2f} ms")
    else:
        print(f"{name}: No valid data")


print()
print_stats("Block Propagation Time", propagation_times)
print_stats("Block Broadcasting Time", broadcasting_times)

print()
print(f"Blocks announced (at least 1 ANOUNCEMENT): {anounced_blocks}")
print(f"Blocks broadcasted (BROADCASTED seen): {broadcasted_blocks}")
print(f"Blocks fully propagated (all phases ordered): {propagated_blocks}")
