# Neovim rendering performance

The picker reuses Tree-sitter highlights for unchanged grep text and filename layouts within a render context. These changes reduce repeated work during query updates and cursor movement.

## Measurements

Baseline: `5bd9943f7c81dfc32cce0b11825ecf83c023a73b`. Measurements use Neovim 0.12.5, LuaJIT 2.1, and an Intel Core i7-1370P on Linux.

The benchmark renders 40 rows in a 150-column window through the real Neovim buffer and extmark APIs. Each value is the median of seven samples with 180 operations per sample, after 20 warmup operations. Cursor movement alternates between two items. New-text renders change every grep row on each operation.

| Operation | Prompt | Baseline, ms | Cached, ms |
| --- | --- | ---: | ---: |
| File render | Top | 0.1357 | 0.1206 |
| File render | Bottom | 0.1574 | 0.1246 |
| Grep render, repeated text | Top | 3.4110 | 0.6655 |
| Grep render, repeated text | Bottom | 3.5354 | 0.6645 |
| Grep cursor movement | Top | 0.2108 | 0.0360 |
| Grep cursor movement | Bottom | 0.2152 | 0.0434 |
| Grep render, new text | Top | 4.1530 | 4.4099 |
| Grep render, new text | Bottom | 4.2740 | 4.4095 |

Repeated grep renders improve by 5.1 to 5.3 times. Grep cursor movement improves by 5.0 to 5.9 times, and file renders take 11 to 21 percent less time. Entirely new grep text takes 3 to 6 percent more time in this comparison. Earlier runs measured a 1 to 3 percent increase for new text.

These measurements isolate rendering with synthetic Lua search results. They exclude indexing, search latency, preview loading, terminal redraw, and active search score retrieval. The gain depends on how much text consecutive result pages share.

## Cache lifetime

Tree-sitter highlights use a FIFO cache keyed by language and text. It retains at most 256 entries and skips lines longer than 4096 bytes. Closing the picker clears the cache and its scratch buffers. Parser failures are retried rather than cached.

Filename layouts belong to the render context. A full render computes each layout once and reuses it when applying highlights. Cursor movement reuses that context. A query update or layout change creates a new context.

## Run the benchmark

Run from the repository root with Neovim and its Lua Tree-sitter parser installed:

```sh
make bench-nvim
FFF_BENCH_ITERATIONS=180 FFF_BENCH_SAMPLES=7 make bench-nvim
FFF_BENCH_REF=5bd9943f7c81dfc32cce0b11825ecf83c023a73b FFF_BENCH_ITERATIONS=180 FFF_BENCH_SAMPLES=7 make bench-nvim
```

`FFF_BENCH_REF` loads the baseline Tree-sitter and file renderer modules from Git without changing the working tree. Both comparisons use the same benchmark and native library.

The regression tests compare cached and fresh buffer text, cursor positions, selection marks, and highlights for file and grep results with both prompt positions. They also cover narrower layouts, cache eviction, language separation, cleanup, oversized lines, and parser retries.

`make test-lua` passes all 75 tests. `make test-lua-snap` reports 16 mismatches among 42 cases. The same 16 failures reproduce with both modified Lua modules restored to the baseline commit, including fuzzy scores that differ from the saved references.
