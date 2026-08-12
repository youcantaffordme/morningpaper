-- v0.8 keeps the stable v0.7 UI/build pipeline but swaps in the Coverage Net
-- newsroom engine before main_v07 is loaded.
-- newsroom_v08 already returns the wrapped newsroom table, so do not call a
-- nonexistent .wrap() helper here (that prevented the plugin from loading).
local CoverageNet = require("newsroom_v08")
package.loaded["newsroom_v07"] = CoverageNet
return require("main_v07")
