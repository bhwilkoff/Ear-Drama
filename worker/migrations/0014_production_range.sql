-- One scene of a catalog play (docs/PLAYS-DESIGN.md section 2.12): the two line
-- ids {"from","to"} as JSON. `cast_sheet` is already the slice from `from`
-- through `to`, so every rule that reads the cast covers only the range; this
-- column only lets a client cut its script to the same lines. Null: the whole
-- play, as every production made before this was.

ALTER TABLE play_productions ADD COLUMN scene_range TEXT;
