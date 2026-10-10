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
- `support_type` – trapeze / hframe / sleeper / bracket
- `base_type` – the type the user chose
- `members` – JSON run persistent ids
- `signature`

Shared supports from versions before 1.10 have no `at` and are left as they are.

**Settings:** `support_group_mm` (default 600, 0 = off); `hdpe_joint` (since 1.14 –
`auto` | `butt` | `ef` | `comp`, default `auto` = by size, so older HDPE runs rebuild with the
fittings of their size; their part definitions are new names, the old ones stay until rebuilt).

**HDPE pieces (1.14, new keys only):** `joint_desc` (Electrofusion / Compression (PP) / Butt
fusion spigot / … – shown in the BOM), `fitting_desc` on elbows, couplers and stub ends;
`type = coupling` (EF / compression coupler at a stick joint, in the BOM), `type = bead` (a
butt fusion stick joint, drawing only); valves on fusion lines carry `stub_ends` (count) and
`stub_dn`. Tee and join records may carry `main_joint` – the main run's `hdpe_joint`.

**Model:** `fmt` – the format the file was last upgraded to.
