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

## Keys

**Run** (group, `type = run`):
- `cl` – JSON centre-line segments, in mm, run-local
- `tees` – JSON branch connections onto other runs
- `joins` – JSON joins onto other runs
- `supports` – JSON support records
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

**Placed library parts** (`type = component`):
- `category`
- `size`
- `material`
- `name_desc`
- `model`
- `fmt`

**Model:** `fmt` – the format the file was last upgraded to.
