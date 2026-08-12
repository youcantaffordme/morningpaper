-- Load Coverage Net first. It enhances the stable v0.7 newsroom table in place.
require("newsroom_v08")

-- Then load the proven v0.7 UI/build pipeline unchanged.
return require("main_v07")
