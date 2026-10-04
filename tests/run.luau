--!strict
-- Runs every spec: `lune run tests/run`
local t = require("./harness")

require("./MovementMath.spec")
require("./ShotMath.spec")

t.finish()
