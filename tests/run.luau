--!strict
-- Runs every spec: `lune run tests/run`
local t = require("./harness")

require("./GaitMath.spec")
require("./MovementMath.spec")
require("./ShotMath.spec")
require("./SkillMath.spec")

t.finish()
