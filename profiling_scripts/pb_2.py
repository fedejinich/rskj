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
total_anouncements = 0

block_propagation_info = []  # for fastest search later
block_broadcasting_info = []  # for fastest search later

print()

for block_hash, events in blocks.items():
    announcement_instants = []
    processing_start = None
    broadcasted = None
    processing_end = None

    for instant, phase in events:
        if phase == "ANOUNCEMENT":
            announcement_instants.append(instant)
        elif phase == "PROCESSING_START" and processing_start is None:
            processing_start = instant
        elif phase == "BROADCASTED" and broadcasted is None:
            broadcasted = instant
        elif phase == "PROCESSING_END" and processing_end is None:
            processing_end = instant

    if announcement_instants:
        first_announcement = min(announcement_instants)
        anounced_blocks += 1
        total_anouncements += len(announcement_instants)
    else:
        continue

    if first_announcement and broadcasted:
        broadcasted_blocks += 1

    if first_announcement and processing_start and broadcasted and processing_end:
        if first_announcement <= processing_start <= broadcasted <= processing_end:
            propagated_blocks += 1

            propagation_time = processing_end - first_announcement
            broadcasting_time = broadcasted - first_announcement

            propagation_times.append(propagation_time)
            broadcasting_times.append(broadcasting_time)

            block_info = {
                "hash": block_hash,
                "propagation_time": propagation_time,
                "broadcasting_time": broadcasting_time,
                "anouncements": len(announcement_instants),
            }
            block_propagation_info.append(block_info)
            block_broadcasting_info.append(block_info)

            print(
                f"Block {block_hash[:8]}: "
                f"Propagation={propagation_time}ms, "
                f"Broadcasting={broadcasting_time}ms, "
                f"Anouncements={len(announcement_instants)}"
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
print(f"Total Anouncements (count all ANOUNCEMENT entries): {total_anouncements}")
print(f"Blocks announced (at least 1 ANOUNCEMENT): {anounced_blocks}")
print(f"Blocks broadcasted (ANOUNCEMENT + BROADCASTED): {broadcasted_blocks}")
print(
    f"Blocks fully propagated (ANOUNCEMENT <= PROCESSING_START <= BROADCASTED <= PROCESSING_END): {propagated_blocks}"
)

print()

# Find fastest propagated
if block_propagation_info:
    fastest_propagated = min(
        block_propagation_info, key=lambda x: x["propagation_time"]
    )
    print(f"Fastest propagated block {fastest_propagated['hash'][:8]}:")
    print(f"  Propagation Time: {fastest_propagated['propagation_time']} ms")
    print(f"  Broadcasting Time: {fastest_propagated['broadcasting_time']} ms")
    print(f"  Anouncements: {fastest_propagated['anouncements']}")

# Find fastest broadcasted
if block_broadcasting_info:
    fastest_broadcasted = min(
        block_broadcasting_info, key=lambda x: x["broadcasting_time"]
    )
    print()
    print(f"Fastest broadcasted block {fastest_broadcasted['hash'][:8]}:")
    print(f"  Broadcasting Time: {fastest_broadcasted['broadcasting_time']} ms")
    print(f"  Propagation Time: {fastest_broadcasted['propagation_time']} ms")
    print(f"  Anouncements: {fastest_broadcasted['anouncements']}")
