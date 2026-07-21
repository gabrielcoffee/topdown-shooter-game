-- Level definition. CSV + tileset come from Tilesetter exports.
-- tileTypes maps tile IDs in the CSV to gameplay types; unlisted IDs are 'ground'.
return {
    csv = 'assets/maps/level1.csv',
    tileset = 'assets/images/tileset.png', -- optional: colored squares until exported

    tileTypes = {
        [1] = 'solid',
        [2] = 'spikes',
        [3] = 'water',
        [4] = 'mud',
        [5] = 'hole',
        [6] = 'torch', -- walkable like ground, emits flickering light
    },
    groundFillId = 0, -- written into the grid when a crate plugs a hole

    -- Map entities: free (pixel) coords, not grid-snapped
    objects = {
        { type = 'crate', x = 400, y = 400 },
        { type = 'crate', x = 500, y = 600 },
        { type = 'door',  x = 576, y = 224, price = 250, id = 'east' }, -- plugs the wall gap
        { type = 'chest', x = 576, y = 736 }, -- mystery box, next to the south torch

        -- zombie spawn points; door = only active once that door is bought
        { type = 'spawn', x = 64,   y = 64 },
        { type = 'spawn', x = 96,   y = 832 },
        { type = 'spawn', x = 1152, y = 832 },
        { type = 'spawn', x = 640,  y = 224, door = 'east' },
    },
}
