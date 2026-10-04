--!strict
-- CLIENT ENTRY POINT
-- Rojo turns this file into StarterPlayerScripts.Client, a LocalScript that runs on each
-- player's computer. The other files in src/client/ become ModuleScripts inside it.
--
-- Where to look for what:
--   Controllers/InputController     reads WASD / arrows / Shift
--   Controllers/MovementController  acceleration, speed, shot drift
--   Controllers/CameraController    the fixed rim-facing camera
--   Controllers/BallController      dribble, gather path, shot flight, make/miss detection
--   Controllers/ArmController       hands on the ball (arm IK) and the follow-through
--   Controllers/LegController       the knee dip and straight legs in the air (leg IK)
--   Controllers/ShotController      the E key: shot type, timing, aim
--   Controllers/HudController       timing meter, callouts, stats panel
-- All the numbers they use live in src/shared/Config/.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tunable = require(ReplicatedStorage.Shared.Tunable)
local CharacterRef = require(script.CharacterRef)
local Controllers = script.Controllers
local ArmController = require(Controllers.ArmController)
local BallController = require(Controllers.BallController)
local CameraController = require(Controllers.CameraController)
local HudController = require(Controllers.HudController)
local LegController = require(Controllers.LegController)
local InputController = require(Controllers.InputController)
local MovementController = require(Controllers.MovementController)
local ShotController = require(Controllers.ShotController)

-- In Studio, expose these configs under ReplicatedStorage.Tuning for live editing.
local Config = ReplicatedStorage.Shared.Config
Tunable.bind("Movement", require(Config.Movement))
Tunable.bind("Camera", require(Config.Camera))
Tunable.bind("Shooting", require(Config.Shooting))
Tunable.bind("Ball", require(Config.Ball))
Tunable.bind("Motion", require(Config.Motion))

-- Start order matters: character tracking first, then input before the systems that read it.
CharacterRef.start()
InputController.start()
MovementController.start()
CameraController.start()
BallController.start()
ArmController.start()
LegController.start()
HudController.start()
ShotController.start()
