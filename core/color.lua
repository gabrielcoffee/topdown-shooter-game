local Color = {}

Color.red     = function() return 1, 0, 0, 1 end
Color.green   = function() return 0, 1, 0, 1 end
Color.blue    = function() return 0, 0, 1, 1 end
Color.yellow  = function() return 1, 1, 0, 1 end
Color.black   = function() return 0, 0, 0, 1 end
Color.white   = function() return 1, 1, 1, 1 end
Color.magenta = function() return 1, 0, 1, 1 end
Color.cyan    = function() return 0, 1, 1, 1 end
Color.skyblue = function() return 0.5, 0.7, 1, 1 end

return Color