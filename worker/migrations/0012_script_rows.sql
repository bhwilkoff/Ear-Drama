-- The manifest row a production was made from (R4-0, src/plays-castable.js):
-- revision, title, source, rights evidence, the cast sheet's SHA-256, and
-- whether it may be published, as JSON. It goes with its production. The
-- library may drop or change a play; a production made from it keeps this.
-- Null: made before rows were kept, so from the bundle. No person column.

ALTER TABLE play_productions ADD COLUMN script_row TEXT;
