# Stored data format (contract)

Everything Plant Piping TH needs to edit a drawing lives **in the .skp file**, in the
attribute dictionary `ArtK_PlantPipe`. Uninstalling or updating the extension never
removes it, and any newer version must read every older format.

Current format: **2** (`DataFormat::CURRENT`, `src/artk_plant_pipe/lib/data_format.rb`).

| Format | Versions | Change |
|-------:|----------|--------|
| 1 | 1.0 – 1.6 | (no `fmt` key) |
| 2 | 1.7 – | adds the `fmt` stamp only |

## Rules for every future version

1. Never rename or remove a key, and never change the meaning or unit of a key.
   Add new keys with a default instead (`Settings.sanitize` fills missing settings).
2. If a change can't follow rule 1, raise `CURRENT` and add a step in
   `DataFormat::STEPS` that converts the previous format. Never edit a released step.
   A step may set `rec['rebuild'] = true` to regenerate the run's geometry.
3. Add a fixture from the outgoing version (see `test/fixtures/v1_6_0_model.json` and
   `test/test_migrate.rb`). Every old fixture must still open, rebuild, and accept
   new pipes snapped onto it.
4. Records with a newer `fmt` are left untouched. The run is not rebuilt, and the
   user is told to update.

`Migrate.model` runs in four situations:
- when a model is opened (`AppObserver#onOpenModel`)
- when the extension loads
- before any run is rebuilt (`Builder.render`)
- on parts pasted in from older files

## Part geometry revisions

Component definitions built by the extension carry a `rev` (`Refs.geometry_rev`;
`MeterModels::REV` for generated meters). When a model is opened, definitions with an
older `rev` are rebuilt in place, so every copy in the file updates.
**Raise the rev whenever a generated part's geometry changes.**

## Keys

**Run** (group, `type = run`):
- `cl` – JSON centre-line segments, in mm, run-local
- `tees` – JSON branch connections onto other runs
- `joins` – JSON joins onto other runs
- `supports` – JSON support records
- `drawn` – JSON (since 1.15.2) of the pieces the last rebuild drew: `pipes` (centre lines) and
  `fittings` (`[node, [arm ends]]`). Pieces missing at the next rebuild were deleted by the user:
  their centre line is dropped (`RunEdit.prune`) instead of being drawn again. Missing = no check.
- `smooth` – JSON centre-line points the pipe bends through without a fitting (vertices of
  drawn arcs / curves, since 1.13). Missing = none: older runs render exactly as before.
- `settings` – JSON, the full settings used
- `extras` – JSON
- `warnings` – JSON
- `seq`
- `joint`
- `fmt`
- the common keys below

**Common keys on runs and pieces:**
- `service`
- `catalog`
- `catalog_name`
- `material`
- `size`
- `rating`
- `od` (mm)
- `wall` (mm)
- `line_no`

**Pieces inside a run:**
- `type`: pipe, elbow, tee, reducer, valve, flange, support, centerline, and others.
  These are regenerated on rebuild, except valves.
- Valves are re-placed from these keys:
  - `valve_type`
  - `at` – JSON, mm
  - `dir` – JSON
  - `model` – the reference-library key. Always the base key; a standard-size key
    `…@DN25-33.4` also resolves.

- Library parts fixed to an open pipe end (since 1.6.2) carry `end_part` – JSON with
  `key`, `at` (run mm) and `angle`. They are re-placed on every rebuild.
- `geom` of a pipe holds `a`, `b` and, since 1.6.2, `ea` and `eb` (insertion into the
  fittings). Since 1.13 a pipe bent along a drawn curve also holds `path` – its
  centre-line points from `a` to `b` (run mm); read it with `ModelHelpers.pipe_path`,
  never assume `a`–`b` is straight. Such pipes also carry `bend_radius_mm` (tightest
  radius) and `bend_angle` (total turn, degrees).
- `type = end_center` – a group inside a pipe at an open end (since 1.6.1). It holds a
  real circle and a construction point, so SketchUp's own tools can snap to Center.

**Placed library parts** (`type = component`):
- `category`
- `size`
- `material`
- `name_desc`
- `model`
- `fmt`

**Shared supports** (group, `type = support`, added in 1.10 – new keys only, format unchanged):
- `at` – JSON, world mm
- `dir` – JSON
- `support_type` – trapeze / hframe / sleeper / bracket / column (1.12) / wallframe (1.16.0 only – moved to
  the Steel Supports TH extension in 1.16.1; still rebuilt / adapted, just no longer offered)
- `base_type` – the type the user chose
- `members` – JSON run persistent ids
- `signature` – of the pipes found at `at` (since 1.16: before a bracket / frame leaves out the
  ones it cannot reach – older groups that left one out are rebuilt once when a pipe next to them changes)

Shared supports from versions before 1.10 have no `at` and are left as they are.

**Settings:** `support_group_mm` (default 600, 0 = off); `hdpe_joint` (since 1.14 –
`auto` | `butt` | `ef` | `comp`, default `auto` = by size, so older HDPE runs rebuild with the
fittings of their size; their part definitions are new names, the old ones stay until rebuilt).

**HDPE pieces (1.14, new keys only):** `joint_desc` (Electrofusion / Compression (PP) / Butt
fusion spigot / … – shown in the BOM), `fitting_desc` on elbows, couplers and stub ends;
`type = coupling` (EF / compression coupler at a stick joint, in the BOM), `type = bead` (a
butt fusion stick joint, drawing only); valves on fusion lines carry `stub_ends` (count) and
`stub_dn`. Tee and join records may carry `main_joint` – the main run's `hdpe_joint`.

**Model:** `fmt` – the format the file was last upgraded to; `ins_spec` (1.17.0) – the file was drawn by 1.17+
or its runs with insulation set as 2" × 2 layers (100 / 101.6) were offered the BOQ's 1-1/2" (38.1) once, on open
(`Migrate.respec_runs`; yes = 38.1 and the run dropped by the difference unless tied to another run). Stored setting:
pref `ins_spec` – the same, once, for the saved settings. Steel Supports groups carry `rev` (2.5.1, `Builder::REV`):
older steel is redone by a refit and on open.

**Other extensions (1.16.1):** `ArtK::PlantPipe::API` (LEVEL 1, `su/api.rb`; LEVEL 2 in 1.16.2 adds
`register_rests` – the pipe tool lays a pipe picked on another extension's support on it; 1.16.3 passes the pipe
being drawn `{ od:, ins: }` as a 4th argument; 1.16.4 calls it with an empty path too) is the stable surface other
extensions call; Steel Supports TH keeps its own groups in the `ArtK_SteelSupport` dictionary
(docs/STEEL_SUPPORTS.md) and never writes Plant Piping data except through `API.drop_hangers` (the
same removal of single supports Plant Piping does itself). `SupportBuilder.drop_covered(model, point,
pipes)` keeps working for PipeBracket.

