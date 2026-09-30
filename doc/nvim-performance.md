# Neovim rendering performance

The picker reuses Tree-sitter highlights for unchanged grep text and filename layouts within a render context. Preview lookup checks exact buffer names before resolving symlink aliases. These changes reduce work during query updates, cursor movement, and previews of loaded files.

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

`FFF_BENCH_REF` loads the baseline Tree-sitter, file renderer, and preview modules from Git without changing the working tree. Both comparisons use the same benchmark and native library.

The regression tests compare cached and fresh buffer text, cursor positions, selection marks, and highlights for file and grep results with both prompt positions. They also cover narrower layouts, cache eviction, language separation, cleanup, oversized lines, and parser retries.

`make test-lua` passes all 79 tests. `make test-lua-snap` reports 16 mismatches among 42 cases. The same 16 failures reproduce with both rendering modules restored to the baseline commit, including fuzzy scores that differ from the saved references.

## Preview buffer lookup

The preview first checks loaded buffer names for an exact match. If none matches, it resolves the recorded names and checks for symlink aliases. This avoids resolving every unrelated buffer path before finding an exact match. Buffer names are read on each lookup, so renames and unloads cannot leave stale cached paths.

The benchmark places the target buffer after the other loaded buffers. It also measures a path with no matching buffer. Symlink-only matches still need the fallback scan.

Baseline: `c2a9d32`, before the preview lookup change. These measurements use the same machine, sample count, and operation count as the rendering benchmark.

| Loaded buffers | Baseline match, ms | Exact match, ms | Baseline miss, ms | New miss, ms |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 0.0094 | 0.0034 | 0.0092 | 0.0093 |
| 201 | 0.6139 | 0.0213 | 0.6150 | 0.6412 |
| 1001 | 3.1238 | 0.1129 | 3.1254 | 3.2207 |

An exact match with 1001 loaded buffers takes about 28 times less time. Missing-buffer lookups take 3 to 4 percent more time at the larger buffer counts. The earlier prototype measured similar miss times before and after the change.

Preview regression tests cover unsaved edits, symlink requests, buffers opened through symlink aliases, and unloaded buffers.

## Long grep lines

Baseline: `687fee2`. The grep renderer previously measured the full line, counted every character, and searched across that character count to fit the window. Long minified lines made this work expensive despite the small visible area.

The renderer now checks a prefix one byte longer than the available width. A printable ASCII prefix can be clipped directly. For Unicode and tabs, it grows a character prefix until it exceeds the available display width, then searches within that bound. Combining marks and wide characters keep the previous truncation behavior.

Measurements use a 150-column window and the median of seven samples with 100 row renders per sample. The benchmark includes row formatting and padding. It excludes search, transfer of results from Rust, Tree-sitter highlights, and buffer updates.

| Content | Bytes | Baseline, ms | Bounded clipping, ms |
| --- | ---: | ---: | ---: |
| ASCII | 80 | 0.001295 | 0.000774 |
| ASCII | 1000 | 0.019974 | 0.001228 |
| ASCII | 100000 | 1.138468 | 0.001312 |
| ASCII | 1000000 | 11.938752 | 0.001233 |
| Unicode | 100002 | 2.087704 | 0.051327 |

ASCII clipping no longer scans the hidden part of the line. Unicode lines can still require more work when many combining characters occupy few display columns. Timings for short rows vary at the microsecond scale.

```sh
make bench-nvim-grep-lines
FFF_BENCH_REF=687fee2 make bench-nvim-grep-lines
```

`make -o build-e2e test-lua` passes all 81 tests using the existing native library. The added tests compare output and byte offsets against the previous truncation algorithm for both prompt positions. Cases include narrow windows, long ASCII lines, wide characters, combining marks, tabs, and emoji sequences.

## Opening and typing

Baseline: `75b9924`.

The input benchmark opens a child Neovim with a 160-column UI, waits for the repository's initial scan, and sends actual insert-mode keys. It tests an empty open, the first `m`, a single `ain` input burst, and reopening with `main` prefilled. File search and plain, regex, and fuzzy grep run with both prompt positions. Frecency, history, logging, and cross-mode suggestions are disabled for this check.

| Event | Before | After |
| --- | --- | --- |
| Warm empty file picker | 2 searches | 1 search |
| Warm prefilled file picker | 3 searches | 1 search |
| Warm prefilled grep picker | 3 searches | 1 search |
| First key | 1 search and 1 render | 1 search and 1 render |
| Same-tick typing burst | 1 search and 1 render | 1 search and 1 render |

The initial scan monitor previously searched again even when the index was already ready. Prefilling the prompt also queued an input callback after the synchronous search had processed that same buffer content. Opens now start scan monitoring only when needed, and input callbacks skip a buffer change already processed by a search. Prefetched-result opens retain their existing refresh behavior.

The processed-input marker includes the buffer identity and changed tick. It is recorded only when the buffer text matches the searched query. A scan refresh using the old query therefore cannot swallow newly queued input. Tests cover that race and the final refresh after an initial scan.

Grep rendering remains the largest measured typing cost. First-result rendering varied from roughly 3 to 34 ms, while search took roughly 1 to 3 ms. Tree-sitter extraction consumed most of the render time. Broad queries sometimes returned up to 200 rows, all of which currently receive syntax highlights, including rows outside the viewport. These measurements describe one repository and clean Neovim; result ordering and parser startup affect the timings.

```sh
make bench-nvim-input
```

The benchmark reports counts and time for backend searches, renders, preview updates, preview file loads, language detection, and Tree-sitter highlights. These times overlap, so they must not be added together. `make -o build-e2e test-lua` passes all 87 tests using the existing native library.
