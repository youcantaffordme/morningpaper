-- Morning Paper v0.9 keeps the proven v0.7 KOReader UI/build pipeline.
-- The only newsroom enhancement is loaded first and patches the stable newsroom
-- module in place, so plugin startup/menu registration remains unchanged.
require("newsroom_v09")
return require("main_v07")
