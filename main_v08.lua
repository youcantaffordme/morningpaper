-- v0.8 keeps the stable v0.7 UI/build pipeline but wraps its newsroom engine
-- with the Coverage Net before main_v07 is loaded.
local BaseNewsroom = require("newsroom_v07")
local CoverageNet = require("newsroom_v08")
package.loaded["newsroom_v07"] = CoverageNet.wrap(BaseNewsroom)
return require("main_v07")
