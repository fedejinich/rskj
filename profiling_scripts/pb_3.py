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

block_infos = []

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

            block_infos.append(
                {
                    "hash": block_hash,
                    "propagation_time": propagation_time,
                    "broadcasting_time": broadcasting_time,
                    "anouncements": len(announcement_instants),
                }
            )

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

# ---------- Mini Table Summary ----------


def mini_table(title, block):
    print()
    print(f"{title}")
    print("-" * len(title))
    print(f"Block Hash: {block['hash'][:8]}...")
    print(f"Propagation Time: {block['propagation_time']} ms")
    print(f"Broadcasting Time: {block['broadcasting_time']} ms")
    print(f"Anouncements: {block['anouncements']}")
    print()


if block_infos:
    fastest_propagated = min(block_infos, key=lambda x: x["propagation_time"])
    slowest_propagated = max(block_infos, key=lambda x: x["propagation_time"])

    fastest_broadcasted = min(block_infos, key=lambda x: x["broadcasting_time"])
    slowest_broadcasted = max(block_infos, key=lambda x: x["broadcasting_time"])

    mini_table("Fastest Propagated Block", fastest_propagated)
    mini_table("Slowest Propagated Block", slowest_propagated)
    mini_table("Fastest Broadcasted Block", fastest_broadcasted)
    mini_table("Slowest Broadcasted Block", slowest_broadcasted)


import matplotlib.pyplot as plt

EXCLUDED_BLOCK_HASH = "db58f0a1033b7fba60ff54f92ad1223904aaf3633aa7edbecbca95236e4affa7"

if block_infos:
    # Exclude the specific block
    filtered_block_infos = [b for b in block_infos if b["hash"] != EXCLUDED_BLOCK_HASH]

    propagation_times = [b["propagation_time"] for b in filtered_block_infos]
    broadcasting_times = [b["broadcasting_time"] for b in filtered_block_infos]
    block_labels = [b["hash"] for b in filtered_block_infos]

    # Scatter plot
    plt.figure(figsize=(12, 7))

    plt.scatter(
        range(len(propagation_times)),
        propagation_times,
        color="blue",
        label="Propagation Time",
    )
    plt.scatter(
        range(len(broadcasting_times)),
        broadcasting_times,
        color="red",
        label="Broadcasting Time",
    )

    plt.title("Block Propagation and Broadcasting Times (Fully Propagated Blocks)")
    plt.xlabel("Block Index")
    plt.ylabel("Time (ms)")
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.show()

    # Pie chart: total propagation vs broadcasting time
    total_propagation = sum(propagation_times)
    total_broadcasting = sum(broadcasting_times)

    plt.figure(figsize=(7, 7))
    plt.pie(
        [total_propagation, total_broadcasting],
        labels=["Propagation Time", "Broadcasting Time"],
        autopct="%1.1f%%",
        startangle=140,
        colors=["blue", "red"],
    )
    plt.title("Total Propagation vs Broadcasting Time (Fully Propagated Blocks)")
    plt.tight_layout()
    plt.show()
