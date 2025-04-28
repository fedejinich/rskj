import csv
import sys
import statistics
from collections import defaultdict

if len(sys.argv) < 2:
    print("Usage: python3 analyze_bp.py <path_to_csv>")
    sys.exit(1)

csv_file = sys.argv[1]

# Load and group by blockHash
data = defaultdict(list)
announced_blocks = set()

with open(csv_file, newline="") as csvfile:
    reader = csv.reader(csvfile)
    for row in reader:
        # row order: blockHash, instant, peerId, phase, processingPhase
        if len(row) < 5:
            continue  # Skip malformed rows

        block_hash = row[0]
        instant = int(row[1])
        phase = row[3]
        processing_phase = row[4]

        data[block_hash].append(
            {
                "instant": instant,
                "phase": phase,
                "processingPhase": processing_phase,
            }
        )

        if phase == "ANOUNCEMENT" and processing_phase == "NONE":
            announced_blocks.add(block_hash)

# Sort each blockHash list by instant
for events in data.values():
    events.sort(key=lambda e: e["instant"])

# Analyze blocks
processed_blocks = 0
propagation_times = []

print("BlockHash,AnnouncementTime(ms),ProcessingTime(ms),PropagationTime(ms)")

for block_hash, events in data.items():
    announcement_instant = None
    processing_start_instant = None
    processing_end_instant = None

    for event in events:
        if event["phase"] == "ANOUNCEMENT" and event["processingPhase"] == "NONE":
            announcement_instant = event["instant"]
        elif event["phase"] == "PROCESSING" and event["processingPhase"] == "START":
            processing_start_instant = event["instant"]
        elif event["phase"] == "PROCESSING" and event["processingPhase"] == "END":
            processing_end_instant = event["instant"]

    if (
        announcement_instant is not None
        and processing_start_instant is not None
        and processing_end_instant is not None
    ):
        # Validate time sequence: announcement <= processing start <= processing end
        if not (announcement_instant <= processing_start_instant <= processing_end_instant):
            continue  # Skip invalid data

        processed_blocks += 1
        announcement_time = processing_start_instant - announcement_instant
        processing_time = processing_end_instant - processing_start_instant
        propagation_time = processing_end_instant - announcement_instant

        propagation_times.append(propagation_time)

        # Print compressed blockhash
        short_hash = block_hash[:8]
        print(f"{short_hash},{announcement_time},{processing_time},{propagation_time}")

# Overall stats
print("\n=== Summary ===")
print("Total announced blocks:", len(announced_blocks))
print("Total fully processed blocks:", processed_blocks)
if processed_blocks > 0:
    avg_propagation_time = sum(propagation_times) / processed_blocks
    median_propagation_time = statistics.median(propagation_times)
    print("Average block propagation time (ms):", avg_propagation_time)
    print("Median block propagation time (ms):", median_propagation_time)
else:
    print("No fully processed blocks found.")

