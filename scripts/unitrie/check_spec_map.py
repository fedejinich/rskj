#!/usr/bin/env python3
"""Hard checks for unitrie spec-map completeness and evidence coverage."""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any, Iterable

REQUIRED_TOP_LEVEL_FIELDS = {"version", "generatedAt", "sourceOfTruth", "specs"}
REQUIRED_SPEC_FIELDS = {
    "specId",
    "specClass",
    "criticality",
    "javaSource",
    "javaBehavior",
    "rustTarget",
    "evidence",
    "status",
}
ALLOWED_SPEC_CLASSES = {
    "trie",
    "codec-rskip107",
    "codec-orchid",
    "storage-keys",
    "persistence",
    "hash",
    "jni",
    "diagnostics",
}
ALLOWED_CRITICALITY = {"consensus-critical", "non-critical"}
ALLOWED_STATUS = {"missing", "partial", "implemented", "verified"}
ALLOWED_RUST_TARGET = {"legacy-v1", "next"}
SPEC_ID_PATTERN = re.compile(r"^SPEC-[A-Z0-9-]+$")
REQUIRED_CRITICAL_PREFIXES = [
    "SPEC-TRIE-",
    "SPEC-CODEC-RSKIP107-",
    "SPEC-CODEC-ORCHID-",
    "SPEC-STORAGE-KEYS-",
    "SPEC-PERSISTENCE-",
    "SPEC-HASH-",
]


def main() -> int:
    repo_root = pathlib.Path(__file__).resolve().parents[2]
    schema_path = repo_root / "docs" / "engineering" / "unitrie-spec-map.schema.json"
    spec_map_path = repo_root / "docs" / "engineering" / "unitrie-spec-map.json"

    errors: list[str] = []

    schema = load_json(schema_path, errors, "schema")
    spec_map = load_json(spec_map_path, errors, "spec map")

    if schema is not None:
        validate_schema_shape(schema, errors)

    if spec_map is None:
        print_errors(errors)
        return 1

    validate_top_level(spec_map, errors)
    specs = spec_map.get("specs")
    if not isinstance(specs, list):
        errors.append("spec-map field `specs` must be a list")
        print_errors(errors)
        return 1

    seen_ids: set[str] = set()
    consensus_ids: list[str] = []

    for index, spec in enumerate(specs):
        validate_spec_entry(
            spec,
            index=index,
            errors=errors,
            seen_ids=seen_ids,
            consensus_ids=consensus_ids,
            repo_root=repo_root,
        )

    validate_required_prefixes(consensus_ids, errors)

    if errors:
        print_errors(errors)
        return 1

    print(
        "Spec map check passed: "
        f"{len(specs)} entries, {len(consensus_ids)} consensus-critical, "
        f"all required domains covered."
    )
    return 0


def load_json(path: pathlib.Path, errors: list[str], label: str) -> Any | None:
    if not path.exists():
        errors.append(f"Missing {label} file: {path}")
        return None

    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        errors.append(f"Invalid JSON in {label} file {path}: {exc}")
        return None


def validate_schema_shape(schema: Any, errors: list[str]) -> None:
    if not isinstance(schema, dict):
        errors.append("Schema root must be an object")
        return

    if schema.get("type") != "object":
        errors.append("Schema root type must be `object`")

    defs = schema.get("$defs")
    if not isinstance(defs, dict) or "specEntry" not in defs:
        errors.append("Schema must define `$defs.specEntry`")


def validate_top_level(spec_map: dict[str, Any], errors: list[str]) -> None:
    missing = sorted(REQUIRED_TOP_LEVEL_FIELDS - set(spec_map.keys()))
    if missing:
        errors.append(f"Spec map missing top-level fields: {', '.join(missing)}")

    extra = sorted(set(spec_map.keys()) - (REQUIRED_TOP_LEVEL_FIELDS | {"notes"}))
    if extra:
        errors.append(f"Spec map has unsupported top-level fields: {', '.join(extra)}")

    if spec_map.get("sourceOfTruth") != "java-unitrie":
        errors.append("sourceOfTruth must be `java-unitrie`")


def validate_spec_entry(
    spec: Any,
    index: int,
    errors: list[str],
    seen_ids: set[str],
    consensus_ids: list[str],
    repo_root: pathlib.Path,
) -> None:
    prefix = f"specs[{index}]"

    if not isinstance(spec, dict):
        errors.append(f"{prefix} must be an object")
        return

    missing = sorted(REQUIRED_SPEC_FIELDS - set(spec.keys()))
    if missing:
        errors.append(f"{prefix} missing required fields: {', '.join(missing)}")

    spec_id = spec.get("specId")
    if not isinstance(spec_id, str) or not SPEC_ID_PATTERN.match(spec_id):
        errors.append(f"{prefix}.specId must match {SPEC_ID_PATTERN.pattern}")
    else:
        if spec_id in seen_ids:
            errors.append(f"Duplicate specId detected: {spec_id}")
        seen_ids.add(spec_id)

    spec_class = spec.get("specClass")
    if spec_class not in ALLOWED_SPEC_CLASSES:
        errors.append(f"{prefix}.specClass must be one of {sorted(ALLOWED_SPEC_CLASSES)}")

    criticality = spec.get("criticality")
    if criticality not in ALLOWED_CRITICALITY:
        errors.append(f"{prefix}.criticality must be one of {sorted(ALLOWED_CRITICALITY)}")

    status = spec.get("status")
    if status not in ALLOWED_STATUS:
        errors.append(f"{prefix}.status must be one of {sorted(ALLOWED_STATUS)}")

    rust_target = spec.get("rustTarget")
    if not isinstance(rust_target, list) or not rust_target:
        errors.append(f"{prefix}.rustTarget must be a non-empty list")
    else:
        for target in rust_target:
            if target not in ALLOWED_RUST_TARGET:
                errors.append(f"{prefix}.rustTarget contains invalid value: {target}")

    java_behavior = spec.get("javaBehavior")
    if not isinstance(java_behavior, str) or not java_behavior.strip():
        errors.append(f"{prefix}.javaBehavior must be a non-empty string")

    java_source = spec.get("javaSource")
    if not isinstance(java_source, list) or not java_source:
        errors.append(f"{prefix}.javaSource must be a non-empty list")
    else:
        for source_index, anchor in enumerate(java_source):
            validate_java_source_anchor(anchor, prefix, source_index, errors, repo_root)

    evidence = spec.get("evidence")
    if not isinstance(evidence, dict):
        errors.append(f"{prefix}.evidence must be an object")
        evidence_tests: list[str] = []
        evidence_corpus: list[str] = []
    else:
        evidence_tests = ensure_string_list(evidence.get("requiredTests"), f"{prefix}.evidence.requiredTests", errors)
        evidence_corpus = ensure_string_list(evidence.get("requiredCorpus"), f"{prefix}.evidence.requiredCorpus", errors)

    if criticality == "consensus-critical" and isinstance(spec_id, str):
        consensus_ids.append(spec_id)

        if status == "missing":
            errors.append(f"Consensus-critical spec cannot be `missing`: {spec_id}")

        if not evidence_tests and not evidence_corpus:
            errors.append(
                f"Consensus-critical spec requires evidence mapping in tests or corpus: {spec_id}"
            )


def validate_java_source_anchor(
    anchor: Any,
    prefix: str,
    source_index: int,
    errors: list[str],
    repo_root: pathlib.Path,
) -> None:
    source_prefix = f"{prefix}.javaSource[{source_index}]"

    if not isinstance(anchor, dict):
        errors.append(f"{source_prefix} must be an object")
        return

    file_path = anchor.get("file")
    line = anchor.get("line")
    symbol = anchor.get("symbol")

    if not isinstance(file_path, str) or not file_path.strip():
        errors.append(f"{source_prefix}.file must be a non-empty string")
    else:
        source_file = repo_root / file_path
        if not source_file.exists():
            errors.append(f"{source_prefix}.file does not exist: {file_path}")

    if not isinstance(line, int) or line <= 0:
        errors.append(f"{source_prefix}.line must be a positive integer")

    if not isinstance(symbol, str) or not symbol.strip():
        errors.append(f"{source_prefix}.symbol must be a non-empty string")


def ensure_string_list(value: Any, field_name: str, errors: list[str]) -> list[str]:
    if not isinstance(value, list):
        errors.append(f"{field_name} must be a list")
        return []

    output: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, str) or not item.strip():
            errors.append(f"{field_name}[{index}] must be a non-empty string")
            continue
        output.append(item)

    return output


def validate_required_prefixes(consensus_ids: Iterable[str], errors: list[str]) -> None:
    ids = list(consensus_ids)
    for required_prefix in REQUIRED_CRITICAL_PREFIXES:
        if not any(spec_id.startswith(required_prefix) for spec_id in ids):
            errors.append(f"Missing consensus-critical domain prefix: {required_prefix}")


def print_errors(errors: list[str]) -> None:
    if not errors:
        return

    print("Spec map check failed:")
    for error in errors:
        print(f"- {error}")


if __name__ == "__main__":
    sys.exit(main())
