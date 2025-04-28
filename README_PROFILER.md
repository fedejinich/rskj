# Profiler

This node is instrumented with profiling capabilities. It generates several `.csv` corresponding each profiler type while running.
There are also profiling analysis scripts to get more details about the profiled data. You can run them independently.

## Block Profiling

```bash
python3 block_profiling.py
```

## NOTE

This node is configured with `import state` feature (syncs from a checkpoint), you can change it at the `reference.conf`.
