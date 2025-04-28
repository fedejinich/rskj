import csv
from collections import defaultdict
from statistics import mean, median

csv_file = "../logs/block_propagation.csv"

# Group block events by blockHash
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
    phases = {}
    for instant, phase in events:
        phases[phase] = instant

    if "ANOUNCEMENT" in phases:
        anounced_blocks += 1
    if "ANOUNCEMENT" in phases and "BROADCASTED" in phases:
        broadcasted_blocks += 1
    if all(
        p in phases
        for p in ["ANOUNCEMENT", "PROCESSING_START", "BROADCASTED", "PROCESSING_END"]
    ):
        announcement = phases["ANOUNCEMENT"]
        processing_start = phases["PROCESSING_START"]
        broadcasted = phases["BROADCASTED"]
        processing_end = phases["PROCESSING_END"]

        if announcement <= processing_start <= broadcasted <= processing_end:
            propagation_time = processing_end - announcement
            broadcasting_time = broadcasted - announcement

            propagated_blocks += 1
            propagation_times.append(propagation_time)
            broadcasting_times.append(broadcasting_time)

            print(
                f"Block {block_hash[:8]}: "
                f"Propagation={propagation_time}ms, "
                f"Broadcasting={broadcasting_time}ms"
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
print(f"Blocks announced (ANOUNCED): {anounced_blocks}")
print(f"Blocks broadcasted (ANOUNCED + BROADCASTED): {broadcasted_blocks}")
print(
    f"Blocks fully propagated (ANOUNCEMENT <= PROCESSING_START <= BROADCASTED <= PROCESSING_END): {propagated_blocks}"
)
