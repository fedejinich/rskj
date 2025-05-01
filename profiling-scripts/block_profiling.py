import csv
from collections import defaultdict
from statistics import mean, median
import matplotlib.pyplot as plt

# Input y output
csv_input  = "../logs/block_profiler.csv"
csv_output = "block_profiler_analyzed.csv"

# Bloques a excluir del plot
EXCLUDED_BLOCK_HASHES = [
    "db58f0a1033b7fba60ff54f92ad1223904aaf3633aa7edbecbca95236e4affa7",
    "5ce8fdaa288be18be7da8c224d4a845b06bab375ad971791ea4f8291d22dbe40",
    "2ef854d61d456e4ba4df6c9501936310e667da38054693ec062ad7a5f2d984d1",
    "6d7e47efc4cdf2f9cda7afede90c730db4f98f97394e45682dd096378329c518",
]

# Leer CSV y agrupar por hash
blocks = defaultdict(list)
with open(csv_input, newline="") as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) != 3:
            continue
        instant, block_hash, phase = row
        blocks[block_hash].append((int(instant), phase))

# Ordenar eventos por tiempo
for ev in blocks.values():
    ev.sort(key=lambda x: x[0])

# Contenedores de métricas
announcement_times            = []
header_to_contained_times     = []
contained_to_preprocess_times = []
preprocessing_times           = []
broadcasting_times            = []
propagation_times             = []

# Contadores
total_announcements = 0
announced_blocks    = 0
broadcasted_blocks  = 0
propagated_blocks   = 0

# Para CSV y detalle
block_infos      = []
detailed_metrics = []

# Procesar cada bloque
for block_hash, events in blocks.items():
    announcement_instants = []
    processing_start      = None
    v_header              = None
    v_contained           = None
    v_pre_start           = None
    v_pre_end             = None
    broadcasted           = None
    processing_end        = None

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

    if not announcement_instants:
        continue

    # primer instante de anuncio
    first_ann = min(announcement_instants)
    announced_blocks += 1
    total_announcements += len(announcement_instants)

    # sub-métricas
    ann_lat    = None
    hdr_valid  = None
    cont_val   = None
    preproc    = None
    b_time     = None
    p_time     = None
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

    # deltas principales
    if broadcasted is not None and processing_end is not None:
        total_time = processing_end - first_ann
        b_time     = (broadcasted - processing_start) if processing_start else (broadcasted - first_ann)
        p_time     = processing_end - broadcasted
        broadcasting_times.append(b_time)
        propagation_times.append(p_time)

    if broadcasted is not None:
        broadcasted_blocks += 1
    if None not in (ann_lat, b_time, p_time):
        propagated_blocks += 1

    # guardar todo
    block_infos.append({
        "hash"             : block_hash,
        "BroadcastingTime" : b_time,
        "PropagationTime"  : p_time,
        "TotalConsumedTime": total_time,
    })
    detailed_metrics.append({
        "hash"                : block_hash,
        "AnnouncementLatency" : ann_lat,
        "HeaderValidation"    : hdr_valid,
        "ContainedValidation" : cont_val,
        "Preprocessing"       : preproc,
        "BroadcastingTime"    : b_time,
        "PropagationTime"     : p_time,
        "TotalConsumedTime"   : total_time,
    })

# Escribir CSV final
with open(csv_output, "w", newline="") as out:
    w = csv.writer(out)
    w.writerow([
        "Block",
        "AnnouncementLatency",
        "HeaderValidation",
        "ContainedValidation",
        "Preprocessing",
        "BroadcastingTime",
        "PropagationTime",
        "TotalConsumedTime",
    ])
    for rec in detailed_metrics:
        w.writerow([
            rec["hash"],
            rec["AnnouncementLatency"],
            rec["HeaderValidation"],
            rec["ContainedValidation"],
            rec["Preprocessing"],
            rec["BroadcastingTime"],
            rec["PropagationTime"],
            rec["TotalConsumedTime"],
        ])
print(f"Analizado escrito en {csv_output}\n")

# Imprimir detalle por bloque
for rec in detailed_metrics:
    parts = [f"Block {rec['hash'][:8]}"]
    for key in [
        "AnnouncementLatency",
        "HeaderValidation",
        "ContainedValidation",
        "Preprocessing",
        "BroadcastingTime",
        "PropagationTime",
        "TotalConsumedTime",
    ]:
        val = rec.get(key)
        if val is not None:
            parts.append(f"{key}={val}ms")
    print(", ".join(parts))

# Estadísticas generales (sin cambios)
def stat(name, arr):
    return f"{name}: avg={mean(arr):.2f}ms, med={median(arr):.2f}ms" if arr else f"{name}: No data"

print("\n--- Overall Metrics ---")
print(stat("Announcement Latency", announcement_times))
print(stat("Header Validation", header_to_contained_times))
print(stat("Contained Validation", contained_to_preprocess_times))
print(stat("Preprocessing", preprocessing_times))
print(stat("Broadcasting Time", broadcasting_times))
print(stat("Propagation Time", propagation_times))
print(f"Total Announcements: {total_announcements}")
print(f"Blocks Announced: {announced_blocks}")
print(f"Blocks Broadcasted: {broadcasted_blocks}")
print(f"Blocks Fully Propagated: {propagated_blocks}")

# ————— Plot acumulados incluyendo Announcement, Broadcasting y Propagation —————
filtered = [
    rec for rec in detailed_metrics
    if rec["hash"] not in EXCLUDED_BLOCK_HASHES
       and rec["TotalConsumedTime"] is not None
]
filtered = filtered[:1000]

idx   = list(range(len(filtered)))
# Announcement Cumulative = AnnouncementLatency
a_cum = [rec["AnnouncementLatency"]                          for rec in filtered]
# Broadcasting Cumulative = AnnouncementLatency + BroadcastingTime
b_cum = [rec["AnnouncementLatency"] + rec["BroadcastingTime"] for rec in filtered]
# Propagation Cumulative = TotalConsumedTime
p_cum = [rec["TotalConsumedTime"]                            for rec in filtered]

plt.figure(figsize=(12, 7))
plt.scatter(idx, a_cum, label="Announcement Cumulative")
plt.scatter(idx, b_cum, label="Broadcasting Cumulative")
plt.scatter(idx, p_cum, label="Propagation Cumulative")
plt.xticks([])  # quita etiquetas en X
plt.title("Timeline acumulado por bloque")
plt.xlabel("Índice de bloque")
plt.ylabel("Tiempo acumulado (ms)")
plt.legend()
plt.grid(True, axis='y')   # solo horizontales
plt.tight_layout()
plt.show()

# Pie chart de proporción de DELTAS (opcional)
total_p = sum(propagation_times)
total_b = sum(broadcasting_times)
if total_p > 0:
    plt.figure(figsize=(7, 7))
    plt.pie(
        [total_b/total_p, 1 - total_b/total_p],
        labels=["Broadcasting", "Remaining"],
        autopct="%1.1f%%"
    )
    plt.title("Broadcasting vs Remaining Propagation Share")
    plt.tight_layout()
    plt.show()

